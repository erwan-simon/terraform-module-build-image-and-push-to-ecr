#!/bin/bash

code_path=$1
account_number=$2
docker_repository_name=$3
region_name=$4
image_tag=$5
# if the terraform assumes a role, it should be here because this script execution does not benefit from terraform assume role
role_to_assume_arn=$6
docker_build_args=$7

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
cleanup() {
  docker buildx rm -f "$builder_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cd $code_path

if [ ! -z "$role_to_assume_arn" ]
then
    export OLD_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export OLD_SECRET_ACCESS_ID=$AWS_SECRET_ACCESS_KEY
    export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" $(aws sts assume-role --role-arn ${role_to_assume_arn} --role-session-name GitlabRunnerSession --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" --output text))
fi

# ECR login must happen BEFORE buildx build --push since the registry cache
# export and image push both need authenticated access.
if ! aws ecr get-login-password --region $region_name | docker login -u AWS ${registry_host} --password-stdin 2> login_error_message.txt;
then
  if grep -q "The specified item already exists in the keychain" login_error_message.txt
  then
    # https://github.com/hashicorp/terraform-provider-helm/issues/989
    echo "Cannot login to ECR due to bug, trying to build and push image anyway"
  else
    cat login_error_message.txt
    echo "Cannot login to ECR for unmanaged reason ('$(cat login_error_message.txt)'), Exiting..."
    exit 1;
  fi
fi

echo "Creating ephemeral buildx builder: $builder_name"
docker buildx create --name "$builder_name" --driver docker-container --use

echo "Using BuildKit cache => ${cache_image_ref}"
# `--push` performs build + push in a single step. Required with the
# docker-container driver, which doesn't load images into local docker by default.
if ! docker buildx build -t ${runtime_image_ref} . \
    --cache-from type=registry,ref=${cache_image_ref} \
    --cache-to type=registry,ref=${cache_image_ref},mode=max,image-manifest=true,oci-mediatypes=true \
    --provenance=false \
    --push \
    ${docker_build_args};
then
  echo "Cannot build and push docker image"
  exit 1
fi

cd -
