resource "aws_ecr_repository" "platform_pulse" {
  name                 = "platform-pulse"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "platform_pulse" {
  repository = aws_ecr_repository.platform_pulse.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 10 images — plenty for a POC, keeps storage (and the 500MB free-tier allotment) from creeping."
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
