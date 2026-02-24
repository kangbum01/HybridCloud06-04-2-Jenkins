####################################
# 1. ECS cluster 생성
# 2. ECS Log 수집
# 3. ECS용 IAM(Role) 생성
# 4. ECS Tasks 정의
# 4.0 Service Discovery (Cloud Map)
# 4-1. web
# 4-2. was
# 5. ECS  Service (ALB Target Group 연결)
# 6. ECS HPA 생성
####################################

# 1. ECS cluster 생성
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.name}-cluster"
}

# 2. ECS Log 수집
locals {
  effective_log_group_name = coalesce(var.log_group_name, "/ecs/${var.name}")
}

resource "aws_cloudwatch_log_group" "ecs_log_group"{
  name = local.effective_log_group_name
  retention_in_days = var.log_retention_days
}

# 3. ECS용 IAM(Role) 생성
data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "task_execution" {
  name        = "${var.name}-ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role_policy_attachment" "task_execution_attach" {
  role        = aws_iam_role.task_execution.name
  policy_arn  = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ✅ [추가] Task Role (앱이 AWS API 호출할 때: S3 등)
resource "aws_iam_role" "task_role" {
  name               = "${var.name}-ecsTaskRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

# ✅ [추가] S3 접근 정책 (uploads/results)
resource "aws_iam_policy" "task_s3_policy" {
  name = "${var.name}-task-s3"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:PutObject","s3:AbortMultipartUpload"],
        Resource = ["arn:aws:s3:::${var.s3_bucket}/uploads/*"]
      },
      {
        Effect = "Allow",
        Action = ["s3:GetObject"],
        Resource = [
          "arn:aws:s3:::${var.s3_bucket}/uploads/*",
          "arn:aws:s3:::${var.s3_bucket}/results/*"
        ]
      },
      {
        Effect = "Allow",
        Action = ["s3:ListBucket"],
        Resource = ["arn:aws:s3:::${var.s3_bucket}"],
        Condition = { StringLike = { "s3:prefix" = ["uploads/*","results/*"] } }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_s3_attach" {
  role       = aws_iam_role.task_role.name
  policy_arn = aws_iam_policy.task_s3_policy.arn
}

# 4. ECS Tasks 정의
# local 구성
locals {
  web_container_definitions = jsonencode([
    {
      name      = var.web_container_name
      image     = var.web_image
      essential = true

      portMappings = [{
        containerPort = var.web_container_port
        protocol      = "tcp"
      }]

      environment = [
        {
          name = "WAS_BASE_URL"
          value = "http://${var.was_sd_service_name}.${var.sd_namespace_name}:${var.was_container_port}"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs-web"
        }
      }
    }
  ])

  was_container_definitions = jsonencode([
    {
      name      = var.was_container_name
      image     = var.was_image
      essential = true
      portMappings = [{
        containerPort = var.was_container_port
        protocol      = "tcp"
      }]
      
      environment = [
      { name = "DB_HOST", value = var.db_host },
      { name = "DB_PORT", value = tostring(var.db_port) },
      { name = "DB_NAME", value = var.db_name },
      { name = "DB_USER", value = var.db_user },
      { name = "DB_PASS", value = var.db_pass },

      # (선택) S3도 같이 넣고 싶으면
      # { name = "S3_BUCKET", value = var.s3_bucket },
      # { name = "AWS_REGION", value = var.region }
    ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs-was"
        }
      }
    }
  ])
}

############################
# 4.0 Service Discovery (Cloud Map)
############################
resource "aws_service_discovery_private_dns_namespace" "sd_ns" {
  name = var.sd_namespace_name   # 예: "beat-dev.local"
  vpc  = var.vpc_id
}

resource "aws_service_discovery_service" "sd_was" {
  name = var.was_sd_service_name

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.sd_ns.id

    dns_records {
      type = "A"
      ttl  = 10
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# 4-1. web
resource "aws_ecs_task_definition" "ecs_definition" {
  family           = "${var.name}-web-task"
  network_mode     = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu               = tostring(var.cpu)
  memory            = tostring(var.memory)

  execution_role_arn = aws_iam_role.task_execution.arn

  container_definitions = local.web_container_definitions
}

# 4-2 was
resource "aws_ecs_task_definition" "ecs_definition_was" {
  family           = "${var.name}-was-task"
  network_mode     = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu               = tostring(var.cpu)
  memory            = tostring(var.memory)

  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task_role.arn

  container_definitions = local.was_container_definitions 
}


# 5. ECS  Service (ALB Target Group 연결)
resource "aws_ecs_service" "ecs_service" {
  name        = "${var.name}-service"
  cluster     = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_definition.arn
  desired_count   = var.desired_count
  launch_type  = "FARGATE"
  # sg는 alb에서 만든 sg 가져오기
  network_configuration {
    subnets     = var.private_subnet_ids
    security_groups = [var.ecs_service_sg_id]
    assign_public_ip = false
  }

# web 서버
  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.web_container_name
    container_port   = var.web_container_port
  }
}

# was 서버
resource "aws_ecs_service" "ecs_service_was" {
  name        = "${var.name}-was-service"
  cluster     = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_definition_was.arn
  desired_count   = var.was_desired_count
  launch_type  = "FARGATE"

  # sg는 alb에서 만든 sg 가져오기
  network_configuration {
    subnets     = var.private_subnet_ids
    security_groups = [var.ecs_service_sg_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.sd_was.arn
  }
  
  load_balancer {
    target_group_arn = var.was_target_group_arn
    container_name   = var.was_container_name
    container_port   = var.was_container_port
  }
}

# web/was 둘 다 같은 SG를 사용하고 있기 때문에 자기 자신 SG를 열어줘야 한다
# was 포트는 ecs에서 관리하는 것이 좀 더 좋다
resource "aws_vpc_security_group_ingress_rule" "ecs_allow_was_from_self" {
  security_group_id = var.ecs_service_sg_id
  referenced_security_group_id = var.ecs_service_sg_id
  from_port = var.was_container_port
  to_port = var.was_container_port
  ip_protocol = "tcp"
}


# 6. ECS HPA 생성
# Autoscaling Target
resource "aws_appautoscaling_target" "ecs_hpa" {
  depends_on = [aws_ecs_service.ecs_service]
  min_capacity    = var.web_min_capacity
  max_capacity    = var.web_max_capacity
  service_namespace   = "ecs"
  scalable_dimension  = "ecs:service:DesiredCount"

  # ECS Service desireCound를 스케일링 대상으로 지정
  resource_id = "service/${aws_ecs_cluster.ecs_cluster.name}/${aws_ecs_service.ecs_service.name}"
}

# ALB resource_label 만들기
# target_group_arn에서 targetgroup/<tg-name>/<tg-id> 부분 추출
locals {
  # targetgroup/<tg-name>/<tg-id>
  tg_suffix = regex("targetgroup/.+$", var.target_group_arn)

  # app/<lb-name>/<lb-id>
  lb_suffix = regex("app/.+$", var.alb_arn)

  # app/<lb-name>/<lb-id>/targetgroup/<tg-name>/<tg-id>
  alb_resource_label = "${local.lb_suffix}/${local.tg_suffix}"
}

# Policy 1. CPU Target Tracking
resource "aws_appautoscaling_policy" "cpu_target_tracking" {
  name          = "${var.name}-cpu-tt"
  policy_type   = "TargetTrackingScaling"
  service_namespace = aws_appautoscaling_target.ecs_hpa.service_namespace
  scalable_dimension = aws_appautoscaling_target.ecs_hpa.scalable_dimension
  resource_id       = aws_appautoscaling_target.ecs_hpa.resource_id

  target_tracking_scaling_policy_configuration {
    target_value      = 50
    scale_out_cooldown  = 60
    scale_in_cooldown   = 120

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}


# Policy 2. ALB RequestCountPerTarget
resource "aws_appautoscaling_policy" "alb_rps_target_tracking" {
  name               = "${var.name}-alb-req-tt"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.ecs_hpa.service_namespace
  scalable_dimension = aws_appautoscaling_target.ecs_hpa.scalable_dimension
  resource_id        = aws_appautoscaling_target.ecs_hpa.resource_id

  target_tracking_scaling_policy_configuration {
    # "타겟(태스크) 1개당 초당 요청" 개념이 아니라,
    # AWS에서는 RequestCountPerTarget이 "대략 1분 단위"로 집계되는 지표라
    # target_value는 서비스 특성에 맞게 튜닝이 필요함.
    target_value       = 100
    scale_out_cooldown = 60
    scale_in_cooldown  = 120

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = local.alb_resource_label
    }
  }
}


####################################
# WAS HPA
####################################

# WAS Autoscaling Target
resource "aws_appautoscaling_target" "ecs_hpa_was" {
  depends_on         = [aws_ecs_service.ecs_service_was]
  min_capacity       = var.was_min_capacity
  max_capacity       = var.was_max_capacity
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"

  resource_id = "service/${aws_ecs_cluster.ecs_cluster.name}/${aws_ecs_service.ecs_service_was.name}"
}

# WAS Policy 1. CPU Target Tracking
resource "aws_appautoscaling_policy" "cpu_target_tracking_was" {
  name               = "${var.name}-was-cpu-tt"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.ecs_hpa_was.service_namespace
  scalable_dimension = aws_appautoscaling_target.ecs_hpa_was.scalable_dimension
  resource_id        = aws_appautoscaling_target.ecs_hpa_was.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.was_cpu_target
    scale_out_cooldown = 60
    scale_in_cooldown  = 120

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# WAS Policy 2. Memory Target Tracking
resource "aws_appautoscaling_policy" "mem_target_tracking_was" {
  name               = "${var.name}-was-mem-tt"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.ecs_hpa_was.service_namespace
  scalable_dimension = aws_appautoscaling_target.ecs_hpa_was.scalable_dimension
  resource_id        = aws_appautoscaling_target.ecs_hpa_was.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.was_mem_target
    scale_out_cooldown = 60
    scale_in_cooldown  = 120

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}



