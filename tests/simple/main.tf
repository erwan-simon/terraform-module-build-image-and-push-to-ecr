terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  tags_map = {
    project_name = "terraform-module-build-image-and-push-to-ecr"
    domain_name  = "tests"
    stage_name   = "simple"
  }

  image_tag = substr(md5(join("", [
    filemd5(abspath("${path.root}/app/Dockerfile")),
    filemd5(abspath("${path.root}/app/handler.py")),
  ])), 0, 12)
}

module "ecr" {
  source = "../../iac"

  ecr_name              = "${var.name_prefix}-simple"
  code_path             = abspath("${path.root}/app")
  image_tag             = local.image_tag
  image_rebuild_trigger = local.image_tag
  tags_map              = local.tags_map
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name_prefix}-simple-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.tags_map
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "test" {
  function_name = "${var.name_prefix}-simple"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "${module.ecr.ecr_url}:${local.image_tag}"
  timeout       = 10
  tags          = local.tags_map

  depends_on = [
    module.ecr,
    aws_iam_role_policy_attachment.lambda_basic,
  ]
}

resource "aws_lambda_invocation" "test" {
  function_name = aws_lambda_function.test.function_name
  input         = jsonencode({ source = "terraform-test" })
}
