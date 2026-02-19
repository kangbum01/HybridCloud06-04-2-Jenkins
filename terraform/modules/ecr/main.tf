####################################
# 1. ECR Repository 생성
####################################

# 1. Web, Was ECR Repository 생성
resource "aws_ecr_repository" "this" {
  for_each             = var.repositories
  name                 = "${var.name}-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

####################################
# 2. ECR Lifecycle Policy (오래된 이미지 정리)
####################################
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
