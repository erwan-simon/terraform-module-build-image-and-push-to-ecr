data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Ground the build trigger in ECR's actual state, not just terraform inputs.
# When the lifecycle policy expires a manifest terraform later expects (e.g. a
# stale `runtime-` tag), downstream resources referencing the image tag would
# 404 at runtime. Reading ECR at plan-time and feeding the result into the
# build trigger (see upload_image_to_registry.tf) turns "image was expired"
# into a normal rebuild trigger, making the system self-healing.
#
# The external provider is used (not `data "aws_ecr_image"`) because the AWS
# provider's data sources raise a plan error on `ImageNotFoundException`,
# which is precisely the case we want to handle as data. The wrapper script
# swallows that exit code and returns `{"present_tag": "MISSING"}`.
data "external" "ecr_image_presence" {
  program = ["bash", "${path.module}/check_ecr_image_presence.sh"]
  query = {
    repository_name = aws_ecr_repository.main.name
    image_tag       = local.image_tag
    region          = data.aws_region.current.name
    role_to_assume  = var.role_to_assume_arn
  }
}

