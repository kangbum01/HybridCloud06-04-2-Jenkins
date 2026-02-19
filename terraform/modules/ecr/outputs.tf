# modules/ecr/outputs.tf

output "repository_urls" {
  description = "ECR repository URLs by key (e.g., web/was)"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_names" {
  description = "ECR repository names by key (e.g., web/was)"
  value       = { for k, r in aws_ecr_repository.this : k => r.name }
}
