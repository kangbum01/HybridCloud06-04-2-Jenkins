variable "name_prefix" {
  description = "리소스 이름 접두어 (ex: beat-dev)"
  type        = string
}

variable "aws_region" {
  description = "AWS Region (ex: ap-northeast-2)"
  type        = string
}

variable "ecr_repository_arn" {
  description = "푸시 대상 ECR Repository ARN"
  type        = string
}

