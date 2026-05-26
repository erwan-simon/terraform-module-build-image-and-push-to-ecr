locals {
  code_path_trimmed = trimsuffix(var.code_path, "/")
  code_file_hashes = {
    for file_path in fileset(local.code_path_trimmed, "**") :
    file_path => filemd5("${local.code_path_trimmed}/${file_path}")
    if alltrue([
      for directory_pattern_to_ignore in var.code_hash_ignore_patterns :
      !strcontains(file_path, directory_pattern_to_ignore)
    ])
  }
  computed_code_hash = sha1(jsonencode(local.code_file_hashes))
  # The `runtime-` prefix lets the ECR lifecycle policy (ecr.tf) target hash-derived
  # runtime images specifically without sweeping the `:buildcache` tag. Applied only
  # when the consumer relies on the default hash — an explicit `var.image_tag` is
  # respected as-is to preserve consumer-side tag conventions.
  image_tag             = var.image_tag == "" ? "runtime-${local.computed_code_hash}" : var.image_tag
  image_rebuild_trigger = "${local.computed_code_hash}-${var.image_rebuild_trigger == "" ? timestamp() : var.image_rebuild_trigger}"
  docker_build_args     = join(" ", [for k, v in var.docker_build_args : "--build-arg ${k}=${v}"])
}
