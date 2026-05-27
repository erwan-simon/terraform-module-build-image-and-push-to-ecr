#!/bin/bash

code_path=$1
account_number=$2
docker_repository_name=$3
region_name=$4
image_tag=$5
# if the terraform assumes a role, it should be here because this script execution does not benefit from terraform assume role
role_to_assume_arn=$6
docker_build_args=$7
# Optional: when non-empty, the Dockerfile and its sibling files live in a separate
# directory from the application code. An isolated staging build context is then
# assembled under /tmp (dockerfile_path/ → staging root, code_path/ → staging/payload/).
dockerfile_path=$8

# Dedicated tag holding the BuildKit cache manifest for this ECR repo. Separate
# from the runtime image tag so (a) `mode=max` can export every stage (heavy
# builder stages included) and (b) pulling the cache doesn't drag in the full
# runtime image. Same tag every build — the ECR lifecycle policy (ecr.tf) keeps
# it around indefinitely via its `:buildcache` prefix rule.
registry_host=${account_number}.dkr.ecr.${region_name}.amazonaws.com
cache_image_ref=${registry_host}/${docker_repository_name}:buildcache
runtime_image_ref=${registry_host}/${docker_repository_name}:${image_tag}

# `--cache-to type=registry` requires the docker-container (or kubernetes)
# buildx driver — the default `docker` driver doesn't support registry cache
# export. Create + use a named builder, cleaned up on exit.
builder_name="ecr_module_builder_$$_${RANDOM}"
staging_dir=""
cleanup() {
  docker buildx rm -f "$builder_name" >/dev/null 2>&1 || true
  if [ -n "$staging_dir" ] && [ -d "$staging_dir" ]; then
    rm -rf "$staging_dir"
  fi
}
trap cleanup EXIT

if [ -n "$dockerfile_path" ]; then
  staging_dir=$(mktemp -d -t ecr_module_build_XXXXXX)
  cp -rf "$dockerfile_path"/. "$staging_dir/" || { echo "Could not copy dockerfile context from $dockerfile_path"; exit 1; }
  mkdir -p "$staging_dir/payload"
  cp -rf "$code_path"/. "$staging_dir/payload/" || { echo "Could not copy code from $code_path"; exit 1; }
  build_context="$staging_dir"
  dockerfile_arg=(-f "$dockerfile_path/Dockerfile")
  payload_build_arg=(--build-arg RELATIVE_CODE_PATH=./payload)
else
  build_context="$code_path"
  dockerfile_arg=()
  payload_build_arg=()
fi

if [ ! -z "$role_to_assume_arn" ]
then
    export OLD_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export OLD_SECRET_ACCESS_ID=$AWS_SECRET_ACCESS_KEY
    export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" $(aws sts assume-role --role-arn ${role_to_assume_arn} --role-session-name GitlabRunnerSession --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" --output text))
fi

# ECR login must happen BEFORE buildx build --push since the registry cache
# export and image push both need authenticated access.
login_error_file=$(mktemp -t ecr_login_error_XXXXXX.txt)
if ! aws ecr get-login-password --region $region_name | docker login -u AWS ${registry_host} --password-stdin 2> "$login_error_file";
then
  if grep -q "The specified item already exists in the keychain" "$login_error_file"
  then
    # https://github.com/hashicorp/terraform-provider-helm/issues/989
    echo "Cannot login to ECR due to bug, trying to build and push image anyway"
  else
    cat "$login_error_file"
    echo "Cannot login to ECR for unmanaged reason ('$(cat "$login_error_file")'), Exiting..."
    rm -f "$login_error_file"
    exit 1;
  fi
fi
rm -f "$login_error_file"

echo "Creating ephemeral buildx builder: $builder_name"
# Defensive: a previous invocation killed by SIGKILL or OOM would skip the EXIT
# trap and leak a builder of the same name. Remove first so create is idempotent.
docker buildx rm -f "$builder_name" >/dev/null 2>&1 || true
if ! docker buildx create --name "$builder_name" --driver docker-container; then
  echo "Cannot create buildx builder $builder_name — registry cache export requires the docker-container driver. Check that the docker daemon supports buildx (Docker 19.03+)."
  exit 1
fi

echo "Using BuildKit cache => ${cache_image_ref}"
echo "Build context => ${build_context}"
# `--push` performs build + push in a single step. Required with the
# docker-container driver, which doesn't load images into local docker by default.
# `--builder` targets the ephemeral builder without mutating the host's default
# buildx selection (developers running terraform apply locally keep their context).
if ! docker buildx build --builder "$builder_name" -t ${runtime_image_ref} "$build_context" \
    "${dockerfile_arg[@]}" \
    "${payload_build_arg[@]}" \
    --cache-from type=registry,ref=${cache_image_ref} \
    --cache-to type=registry,ref=${cache_image_ref},mode=max,image-manifest=true,oci-mediatypes=true \
    --provenance=false \
    --push \
    ${docker_build_args};
then
  echo "Cannot build and push docker image"
  exit 1
fi

# Buildx --push success is not a hard guarantee that the manifest is immediately
# readable from ECR's read path (rare transient registry lag, mode=max edge
# cases). The script must not exit 0 unless the tag is actually visible — any
# downstream resource (Lambda, ECS, EMR) that references the tag will 404
# otherwise. The terraform_data resource trusts this script's exit code as the
# proof that the image is ready to be consumed.
deadline=$(( $(date +%s) + 60 ))
until aws ecr describe-images \
        --repository-name "${docker_repository_name}" \
        --image-ids imageTag="${image_tag}" \
        --region "${region_name}" >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "${deadline}" ]; then
        echo "Image ${docker_repository_name}:${image_tag} not visible in ECR 60s after push — aborting"
        exit 1
    fi
    sleep 2
done
echo "Confirmed ${docker_repository_name}:${image_tag} is present in ECR"
