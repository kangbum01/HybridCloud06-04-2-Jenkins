####################################
# 1. ECR Repository 생성
####################################

# 1. Web, Was ECR Repository 생성
resource "aws_ecr_repository" "web" {
  name                 = "${var.name}-web"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "was" {
  name                 = "${var.name}-was"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

####################################
# 2. 오래된 이미지 정리 정책 (web/was)
####################################

resource "aws_ecr_lifecycle_policy" "web_lifecycle" {
  repository = aws_ecr_repository.web.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "was_lifecycle" {
  repository = aws_ecr_repository.was.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}