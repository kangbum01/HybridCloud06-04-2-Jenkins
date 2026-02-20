####################################
# 1. SG 설정
# 2. TG 생성
# 3. ALB 생성 및 연결
####################################


# 1. SG 설정
# * SG - ALB
# * 80/tcp
resource "aws_security_group" "alb_sg" {
  name        = "${var.name}-alb-sg"
  description = "Allow HTTP inbound ${var.alb_ingress_port}/tcp and all outbound traffic"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-alb-sg" }
}

# 80 port
resource "aws_vpc_security_group_ingress_rule" "alb_in_http" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = var.alb_ingress_port
  to_port           = var.alb_ingress_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_out_all" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# 443 port
# ALB SG Inbound :443
resource "aws_vpc_security_group_ingress_rule" "alb_in_https" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = var.alb_listener_port_https
  to_port           = var.alb_listener_port_https
  ip_protocol       = "tcp"
}


# * SG - ECS
# * 8080/tcp
resource "aws_security_group" "ecs_sg" {
  name   = "${var.name}-ecs-sg"
  vpc_id = var.vpc_id

  tags = { Name = "${var.name}-ecs-sg" }
}

# WEB port (예: 80)
resource "aws_vpc_security_group_ingress_rule" "ecs_in_web_from_alb" {
  security_group_id            = aws_security_group.ecs_sg.id
  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port                    = var.web_target_port
  to_port                      = var.web_target_port
  ip_protocol                  = "tcp"
}

# WAS port (예: 8080)
resource "aws_vpc_security_group_ingress_rule" "ecs_in_was_from_alb" {
  security_group_id            = aws_security_group.ecs_sg.id
  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port                    = var.was_target_port      # 보통 8080
  to_port                      = var.was_target_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ecs_out_all" {
  security_group_id = aws_security_group.ecs_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}



# 2. TG 생성
# * TG - web
resource "aws_lb_target_group" "tg_web" {
  name        = "${var.name}-tg-web"
  port        = var.web_target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path    = var.health_check_path # "/"
    matcher = "200-399"
  }
}

# * TG - was
resource "aws_lb_target_group" "tg_was" {
  name      = "${var.name}-tg-was"
  port      = var.was_target_port
  protocol  = "HTTP"
  vpc_id    = var.vpc_id
  target_type = "ip"

  health_check {
    path = "/api/health"
    matcher = "200-399"
  }
}

# 3. ALB 생성 및 연결
# * ALB
resource "aws_lb" "alb" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids

  tags = { Name = "${var.name}-alb" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = var.alb_listener_port # 80
  protocol          = "HTTP"

  default_action {
    type             = "redirect"

    redirect {
      port    = "443"
      protocol  = "HTTPS"
      status_code = "HTTP_301"
      # 필요하면 host/path/query 유지 옵션도 가능(기본적으로 유지됨)
      # host  = "#{host}"
      # path  = "/#{path}"
      # query = "#{query}"
    }
  }
}

# HTTPS default -> WEB
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = var.alb_listener_port_https # 433
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
  certificate_arn   = var.acm_certificate_arn
  default_action {
    type          = "forward"
    target_group_arn = aws_lb_target_group.tg_web.arn
  }
}


# /api/* -> was
resource "aws_lb_listener_rule" "api_to_was" {
  listener_arn = aws_lb_listener.https.arn
  priority      = 10

  condition {
    path_pattern {
      values = ["/api/*"] 
    }
  }

  action {
    type        = "forward"
    target_group_arn = aws_lb_target_group.tg_was.arn
  }
}
