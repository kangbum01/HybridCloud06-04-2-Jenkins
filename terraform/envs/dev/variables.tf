variable "aws_region" {
  description = "Region you want to create (e.g., [ap-northeast-1/2,us-east-1/2])"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (e.g., 10.1.0.0/16)"
  default     = "10.1.0.0/16"
  type        = string
}

variable "name" {
  description = "VPC and resource name prefix"
  type        = string
}

variable "project" {
  description = "Project name prefix"
  type        = string
}

variable "env" {
  description = "AWS env"
  type        = string
}

variable "public_subnets" {
  description = "Public subnet CIDRs"
  type        = list(string)
}

variable "private_subnets" {
  description = "Private subnet CIDRs "
  type        = list(string)
}

variable "azs" {
  description = "AZ list"
  type        = list(string)
}


variable "image_tag_web" {
  description = "ECR image tag to web"
  type        = string
  default     = "latest"
}

variable "image_tag_was" {
  description = "ECR image tag to was"
  type        = string
  default     = "new-was"
}

variable "certificate_arn" {
  type        = string
  description = "Existing ACM certificate ARN"
}
