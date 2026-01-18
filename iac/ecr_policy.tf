resource "aws_ecr_repository_policy" "main" {
  count      = var.ecr_policy == null ? 0 : 1
  repository = aws_ecr_repository.main.name
  policy     = var.ecr_policy
}
