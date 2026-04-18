resource "null_resource" "ecr_upload" {
  provisioner "local-exec" {
    working_dir = path.module
    command     = "/bin/sh upload_image_to_registry.sh \"${var.code_path}\" \"${data.aws_caller_identity.current.account_id}\" \"${aws_ecr_repository.main.name}\" \"${data.aws_region.current.name}\" \"${local.image_tag}\" \"${var.role_to_assume_arn}\" \"${local.docker_build_args}\""
  }
  triggers = {
    image_rebuild_trigger = local.image_rebuild_trigger
  }
  depends_on = [aws_ecr_repository.main]
}
