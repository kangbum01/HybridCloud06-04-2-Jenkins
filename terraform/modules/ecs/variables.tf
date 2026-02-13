variable "name" {
  description = "ECS Cluster name"
  type = string
}

variable "log_group_name" {
  description = "ECS Log Group Name"
  default = null
  type = string
}

variable "log_retention_days" {
  description = "Limit time to keep logs"
  default = 7
  type = number
}

variable "container_name" {
  description = "ECS Container Name"
  type = string
}

variable "image" {
  description = "ECR Image name"
  type = string
}

variable "container_port"{
  description = "ECS Task container port"
  type = number
}

variable "region" {
  description = "ECS region"
  type = string
}

variable "cpu" {
  description = "ECS cpu"
  type = number
}

variable "memory" {
  description = "ECS memory"
  type = number
}

variable "desired_count" {
  description = "desired_count"
  type = number
}

variable "private_subnet_ids" {
  description = "private subnets"
  type = list(string)
}

variable "ecs_service_sg_id" {
  description = "Sg id for ecs"
  type = string
}

variable "target_group_arn" {
  description = "ALB Target Group ARN to attach the ECS service"
  type = string
}

variable "alb_arn" {
  description = "ARN of the Application Load Balancer used for ALBRequestCountPerTarget resource_label"
  type = string
}

