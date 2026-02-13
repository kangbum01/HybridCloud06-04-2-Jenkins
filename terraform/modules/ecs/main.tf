####################################
# 1. ECS cluster 생성
# 2. ECS Log 수집
# 3. ECS용 IAM(Role) 생성
# 4. ECS Tasks 정의
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

# 4. ECS Tasks 정의
locals {
  container_definitions = jsonencode([
    {
      name  =   var.container_name
      image =   var.image
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group   = aws_cloudwatch_log_group.ecs_log_group.name
          awslogs-region  = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "ecs_definition" {
  family           = "${var.name}-task"
  network_mode     = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu               = tostring(var.cpu)
  memory            = tostring(var.memory)

  execution_role_arn = aws_iam_role.task_execution.arn

  container_definitions = local.container_definitions
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

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.container_name
    container_port   = var.container_port
  }
}

# 6. ECS HPA 생성
# Autoscaling Target
resource "aws_appautoscaling_target" "ecs_hpa" {
  depends_on = [aws_ecs_service.ecs_service]
  min_capacity    = 2
  max_capacity    = 4
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
