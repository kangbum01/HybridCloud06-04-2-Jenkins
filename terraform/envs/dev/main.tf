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
  #  target_port       = 8080
  #  health_check_path = "/"

  acm_certificate_arn = var.certificate_arn
  web_target_port     = 8080
  was_target_port     = 8080
}

module "ecr" {
  source = "../../modules/ecr"
  name   = local.name
}

locals {
  web_image = "${module.ecr.web_repository_url}:${var.image_tag_web}"
  was_image = "${module.ecr.was_repository_url}:${var.image_tag_was}"
}

module "ecs" {
  vpc_id              = module.vpc.vpc_id
  source              = "../../modules/ecs"
  sd_namespace_name   = "beat-dev.local"
  was_sd_service_name = "was"

  db_host = var.db_host
  db_port = var.db_port
  db_name = var.db_name
  db_user = var.db_user
  db_pass = var.db_pass

  s3_bucket = var.s3_bucket
  name      = "ecs-integrated"
  region    = var.aws_region

  private_subnet_ids = module.vpc.private_subnet_ids

  ecs_service_sg_id = module.alb.ecs_sg_id

  #ALB 모듈 output
  target_group_arn     = module.alb.target_group_arn
  was_target_group_arn = module.alb.target_group_arn_was
  alb_arn              = module.alb.alb_arn
  web_image            = local.web_image
  was_image            = local.was_image
  web_container_name   = "web"
  web_container_port   = 8080
  was_container_name   = "was"
  was_container_port   = 8080

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

# SQS (Job / Result + DLQ )

# DLQ - Job
resource "aws_sqs_queue" "job_dlq" {
  name                      = "${local.name}-job-dlq"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = "alias/aws/sqs"
}

# DLQ - Result
resource "aws_sqs_queue" "result_dlq" {
  name                      = "${local.name}-result-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = "alias/aws/sqs"
}

# Job Queue
resource "aws_sqs_queue" "job_queue" {
  name                       = "${local.name}-job-queue"
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 300
  message_retention_seconds  = 345600
  kms_master_key_id          = "alias/aws/sqs"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.job_dlq.arn
    maxReceiveCount     = 5
  })
}

# Result Queue
resource "aws_sqs_queue" "result_queue" {
  name                       = "${local.name}-result-queue"
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600
  kms_master_key_id          = "alias/aws/sqs"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.result_dlq.arn
    maxReceiveCount     = 5
  })
}

############################
# Outputs (Queue URL)
############################
output "job_queue_url" {
  value = aws_sqs_queue.job_queue.url
}

output "result_queue_url" {
  value = aws_sqs_queue.result_queue.url
}

output "job_dlq_url" {
  value = aws_sqs_queue.job_dlq.url
}

output "result_dlq_url" {
  value = aws_sqs_queue.result_dlq.url
}


