resource "terraform_data" "ecr_upload" {
  provisioner "local-exec" {
    working_dir = path.module
    command     = "/bin/bash upload_image_to_registry.sh \"${var.code_path}\" \"${data.aws_caller_identity.current.account_id}\" \"${aws_ecr_repository.main.name}\" \"${data.aws_region.current.name}\" \"${local.image_tag}\" \"${var.role_to_assume_arn}\" \"${local.docker_build_args}\""
  }
  # `image_tag` is included so a change to the tag scheme itself forces a rebuild —
  # `image_rebuild_trigger` alone doesn't see derivation tweaks. `ecr_presence` flips
  # to "MISSING" when the expected manifest isn't in ECR, which forces a rebuild even
  # if inputs are unchanged (self-healing after lifecycle expiry).
  triggers_replace = {
    image_rebuild_trigger = local.image_rebuild_trigger
    image_tag             = local.image_tag
    ecr_presence          = data.external.ecr_image_presence.result.present_tag
  }
  depends_on = [aws_ecr_repository.main]
}
