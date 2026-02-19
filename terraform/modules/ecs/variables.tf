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

variable "web_image" {
  description = "ECR Image name - web"
  type = string
}

variable "was_image" {
  description = "ECR Image name - was"
  type = string
}

variable "was_container_name" {
  description = "ECS Container Name - was"
  type = string
}

variable "web_container_name" {
  description = "ECS Container Name - web"
  type = string
}

variable "web_container_port"{
  description = "ECS Task container port - web(8080)"
  type = number
}

variable "was_container_port"{
  description = "ECS Task container port - was(80)"
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

variable "was_min_capacity" { 
  type = number 
}

variable "was_max_capacity" { 
  type = number 
}

variable "was_cpu_target" { 
  type = number 
}  
variable "was_mem_target" { 
  type = number 
}

variable "was_desired_count" {
  type = number
}

variable "web_max_capacity" {
  type = number
}

variable "web_min_capacity" {
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

variable "sd_namespace_name" {
  description = "sd namespace" 
  type = string
}

variable "vpc_id" {
  type = string
}

variable "was_sd_service_name" {
  type = string
}
