variable "aws_region" {
  type        = string
  description = "AWS region in which the test stack is deployed"
  default     = "eu-west-1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to every named resource so parallel test runs do not collide"
  default     = "tf-mod-ecr-test"
}
