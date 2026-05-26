resource "aws_ecr_repository" "main" {
  name = var.ecr_name

  image_tag_mutability = var.image_tag_mutability
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = var.tags_map
}

resource "aws_ecr_lifecycle_policy" "main" {
  repository = aws_ecr_repository.main.name

  # Rule 1 keeps the `:buildcache` tag (BuildKit's mode=max cache manifest, written
  # and pulled by upload_image_to_registry.sh) — only one image ever carries it.
  # Rule 2 keeps only the most recent runtime image, scoped via the `runtime-` tag
  # prefix (set in locals.tf when var.image_tag is empty) so the buildcache image,
  # which lives in the same repo, is never swept by this rule. Consumers passing an
  # explicit `var.image_tag` are NOT covered by rule 2 — they manage their own tag
  # rotation. Rule 3 reaps untagged manifests (orphaned BuildKit cache pushes,
  # ex-runtime manifests whose tag was moved to a new digest) after 1 day.
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the BuildKit cache manifest (only one ever has this tag)"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["buildcache"]
          countType     = "imageCountMoreThan"
          countNumber   = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the latest runtime image (scoped by runtime- prefix to spare buildcache)"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["runtime-"]
          countType     = "imageCountMoreThan"
          countNumber   = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 3
        description  = "Reap untagged manifests (orphaned BuildKit cache, ex-runtime) after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}
