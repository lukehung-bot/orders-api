output "alb_url" {
  value = "http://${aws_lb.main.dns_name}"
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "service_name" {
  value = aws_ecs_service.app.name
}

output "task_family" {
  value = aws_ecs_task_definition.app.family
}

output "log_group" {
  value = aws_cloudwatch_log_group.app.name
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.service_unhealthy.alarm_name
}
