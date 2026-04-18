output "ecr_name" {
  value = aws_ecr_repository.main.name
}

output "ecr_url" {
  value = aws_ecr_repository.main.repository_url
}

output "ecr_arn" {
  value = aws_ecr_repository.main.arn
}

output "code_path" {
  value = var.code_path
}

output "image_tag" {
  value = local.image_tag
}
