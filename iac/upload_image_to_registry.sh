#!/bin/bash

code_path=$1
account_number=$2
docker_repository_name=$3
region_name=$4
image_tag=$5
# if the terraform assumes a role, it should be here because this script execution does not benefit from terraform assume role
role_to_assume_arn=$6
cd $code_path

if [ ! -z "$role_to_assume_arn" ]
then
    export OLD_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export OLD_SECRET_ACCESS_ID=$AWS_SECRET_ACCESS_KEY
    export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" $(aws sts assume-role --role-arn ${role_to_assume_arn} --role-session-name GitlabRunnerSession --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" --output text))
fi

# Get latest tag from image repository for this environment in ECR in order to maximize cache usage during docker build
latest_image_tag=$(aws ecr describe-images --repository-name ${docker_repository_name} --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' | tr -d '"')
echo "Using following image as cache => ${docker_repository_name}:${latest_image_tag}"
if ! docker buildx build -t ${account_number}.dkr.ecr.${region_name}.amazonaws.com/${docker_repository_name}:${image_tag} . \
    --cache-from type=registry,ref=${account_number}.dkr.ecr.${region_name}.amazonaws.com/${docker_repository_name}:${latest_image_tag} \
    --cache-to type=inline \
    --provenance=false;
then
  echo "Cannot build docker image"
  exit 1
fi

if ! aws ecr get-login-password --region $region_name | docker login -u AWS ${account_number}.dkr.ecr.${region_name}.amazonaws.com --password-stdin 2> login_error_message.txt;
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

if ! docker push ${account_number}.dkr.ecr.${region_name}.amazonaws.com/${docker_repository_name}:${image_tag};
then
  echo "Cannot push docker image to ECR"
  exit 1
fi

cd -

if [[ -z ${role_to_assume_arn} ]]
then
    export AWS_ACCESS_KEY_ID=$OLD_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_ID=$OLD_SECRET_ACCESS_KEY
fi
