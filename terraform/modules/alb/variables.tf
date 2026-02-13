# modules/alb/variables.tf
variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_ingress_port" {
  type    = number
  default = 80
}

variable "alb_listener_port" {
  type    = number
  default = 80
}

variable "alb_listener_port_https" {
  type    = number
  default = 443
}


variable "target_port" {
  type    = number
  default = 8080
}

variable "ecs_alb_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  type    = string
  default = "/"
}

variable "acm_certificate_arn" {
  type      = string
  description = "Existing ACM certificate ARN"
}


