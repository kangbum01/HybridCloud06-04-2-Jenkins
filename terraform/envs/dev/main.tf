############################
# envs/dev/main.tf
############################

# 0. provider 생성
provider "aws" {
  region = var.aws_region
}

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  # dev 환경에서 쓰는 공통 이름
  name = "${var.project}-${var.env}"
}

module "vpc" {
  source = "../../modules/vpc"

  aws_region = var.aws_region
  name       = local.name
  vpc_cidr   = var.vpc_cidr

  azs             = var.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
}

module "alb" {
  source            = "../../modules/alb"
  name              = local.name
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  # sg/tg/listner 기준 값들
  target_port       = 8080
  health_check_path = "/"

  acm_certificate_arn = var.certificate_arn
}

module "ecr" {
  source       = "../../modules/ecr"
  name         = local.name
  repositories = ["web", "was"]
}

locals {
  web_image = "${module.ecr.repo_urls["web"]}:${var.image_tag_web}"
  was_image = "${module.ecr.repo_urls["was"]}:${var.image_tag_was}"
}



module "ecs" {
  vpc_id              = module.vpc.vpc_id
  source              = "../../modules/ecs"
  sd_namespace_name   = "beat-dev.local"
  was_sd_service_name = "was"

  name   = "ecs-integrated"
  region = var.aws_region

  private_subnet_ids = module.vpc.private_subnet_ids

  ecs_service_sg_id = module.alb.ecs_sg_id

  #ALB 모듈 output
  target_group_arn = module.alb.target_group_arn
  alb_arn          = module.alb.alb_arn
  web_image = local.web_image
  was_image = local.was_image
  web_container_name = "web"
  web_container_port = 8080
  was_container_name = "was"
  was_container_port = 80

  cpu           = 512
  memory        = 1024
  desired_count = 2

  web_min_capacity = 2
  web_max_capacity = 4

  was_desired_count = 2
  was_min_capacity  = 2
  was_max_capacity  = 4
  was_cpu_target    = 50
  was_mem_target    = 70
}
