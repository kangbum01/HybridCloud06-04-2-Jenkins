output "jenkins_user_name" {
  value = aws_iam_user.jenkins.name
}

output "jenkins_user_arn" {
  value = aws_iam_user.jenkins.arn
}

output "jenkins_access_key_id" {
  value     = try(aws_iam_access_key.jenkins[0].id, null)
  sensitive = true
}

output "jenkins_secret_access_key" {
  value     = try(aws_iam_access_key.jenkins[0].secret, null)
  sensitive = true
}
