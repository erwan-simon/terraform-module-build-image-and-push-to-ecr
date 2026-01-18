resource "aws_ecr_repository" "main" {
  name = var.ecr_name

  image_tag_mutability = var.image_tag_mutability
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = var.tags_map
}
