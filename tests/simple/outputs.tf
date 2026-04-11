output "lambda_result" {
  description = "Raw JSON response returned by the Lambda invocation. Postcondition asserts the handler's expected message is present."
  value       = aws_lambda_invocation.test.result

  precondition {
    condition     = can(regex("hello from container", aws_lambda_invocation.test.result))
    error_message = "Lambda invocation did not return the expected 'hello from container' payload. The image likely did not build or start correctly."
  }
}

output "ecr_url" {
  description = "URL of the ECR repository created by the module under test"
  value       = module.ecr.ecr_url
}
