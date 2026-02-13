variable "aws_region"{
  description = "Region you want to create (e.g., [ap-northeast-1/2,us-east-1/2])"
  type = string
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

variable "public_subnets" {
  description = "Public subnet CIDRs (same length as public_azs)"
  type = list(string)
}

variable "private_subnets" {
  description = "Private subnet CIDRs (same length as private_azs)"
  type = list(string)
}

variable "azs" {
  description = "AZ list"
  type = list(string)
}
