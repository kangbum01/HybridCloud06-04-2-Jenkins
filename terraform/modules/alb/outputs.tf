# modules/alb/outputs.tf
output "alb_arn" {
  value = aws_lb.alb.arn
}

output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}

output "target_group_arn" {
  description = "web target group arn"
  value = aws_lb_target_group.tg_web.arn
}

output "target_group_arn_was" {
  description = "was target group arn"
  value = aws_lb_target_group.tg_was.arn
}


output "listener_arn" {
  value = aws_lb_listener.http.arn
}

output "alb_sg_id" {
  value = aws_security_group.alb_sg.id
}

output "ecs_sg_id" {
  value = aws_security_group.ecs_sg.id
}
