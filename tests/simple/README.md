# tests/simple

End-to-end functional test for the module. Deploys a minimal Python Lambda from an image built and pushed by the module, invokes it, and asserts the response payload.

## What it does

1. Calls the module at `../../iac` to create an ECR repository and build + push `app/Dockerfile` (a Lambda-compatible Python 3.12 image that runs `handler.lambda_handler`).
2. Creates an IAM role for Lambda and a container-based `aws_lambda_function` pointing at the freshly pushed image.
3. Invokes the Lambda with `aws_lambda_invocation` passing `{"source": "terraform-test"}`.
4. Exposes the invocation result as the `lambda_result` output, which has a precondition asserting the response contains `hello from container`. If the image failed to build or the container didn't boot properly, `terraform apply` fails.

## Prerequisites

- Terraform >= 1.5
- Docker with `buildx` running locally
- AWS credentials with permission to create ECR repos, IAM roles, and Lambda functions
- Default region: `eu-west-1` (override with `-var aws_region=...`)

## Run

```bash
cd tests/simple
terraform init
terraform apply -auto-approve
terraform output lambda_result
terraform destroy -auto-approve
```

A successful apply ends with a `lambda_result` output containing `"message": "hello from container"`.

## Customization

- `name_prefix` — prefix applied to ECR repo, Lambda function, and IAM role names. Change it to run multiple tests in parallel without collisions.
- `aws_region` — target AWS region.

## Cost

Negligible: one ECR repo (force-deleted on destroy), one Lambda image, one invocation. Cleanup via `terraform destroy` is complete — `force_delete = true` on the ECR repo ensures the image is removed with the repository.
