output "web_repository_url" {
  value = aws_ecr_repository.web.repository_url
}

output "was_repository_url" {
  value = aws_ecr_repository.was.repository_url
}