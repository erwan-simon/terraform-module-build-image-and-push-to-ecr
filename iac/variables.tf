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
  description = "Path of the code of the lambda. When `dockerfile_path` is empty (default), this directory MUST also contain the Dockerfile at its root — the build context is `code_path` directly. When `dockerfile_path` is set, this directory holds only the application code and is copied into `./payload/` of an isolated staging build context."
}

variable "dockerfile_path" {
  type        = string
  description = "Optional path of the directory containing the Dockerfile (and any files that must sit at the build context root, e.g. entrypoints). If non-empty, an isolated staging directory under /tmp is used as the build context: the contents of `dockerfile_path/` are copied to the staging root, and the contents of `code_path/` are copied into `staging/payload/` (exposed to the Dockerfile via `--build-arg RELATIVE_CODE_PATH=./payload`). Leave empty (default) to keep the legacy behavior — Dockerfile expected at the root of `code_path`."
  default     = ""
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
  description = "Is the tag of the image MUTABLE or IMMUTABLE ? Note: the module's BuildKit cache strategy rewrites a dedicated `:buildcache` tag on every build, which requires `MUTABLE`. Setting this to `IMMUTABLE` will cause the second `terraform apply` to fail with `ImageTagAlreadyExistsException` when the cache push happens."
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
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
