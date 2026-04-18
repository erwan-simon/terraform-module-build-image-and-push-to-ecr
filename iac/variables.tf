variable "ecr_name" {
  type        = string
  description = "Name of the ecr"
}

variable "tags_map" {
  type        = map(string)
  description = "Map of the tags to apply to the created resources"
}

variable "code_path" {
  type        = string
  description = "Path of the code of the lambda"
}

variable "image_tag" {
  type        = string
  description = "Tag of the image to push to the ECR. If empty, a hash computed from the files in code_path is used."
  default     = ""
}

variable "code_hash_ignore_patterns" {
  type        = list(string)
  description = "Path patterns to exclude when computing the code hash used for the image tag and rebuild trigger"
  default     = []
}

variable "image_tag_mutability" {
  type        = string
  description = "Is the tag of the image MUTABLE or IMMUTABLE ?"
  default     = "MUTABLE"
}

variable "image_rebuild_trigger" {
  type        = string
  description = "String which, if changed, will trigger the rebuild and reupload of the image in the ECR"
  default     = ""
}

variable "role_to_assume_arn" {
  type        = string
  description = "Role to assume in the image upload script"
  default     = ""
}

variable "docker_build_args" {
  type        = map(string)
  description = "Optional map of build arguments passed to docker build as --build-arg KEY=VALUE"
  default     = {}
}

variable "ecr_policy" {
  type        = string
  description = "The policy document for the ecr resource based policy. This is a JSON formatted string."
  default     = null
}
