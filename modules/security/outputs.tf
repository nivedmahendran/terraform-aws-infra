output "lb_security_group_id" {
  description = "Security group attached to the load balancer"
  value       = aws_security_group.lb.id
}

output "app_security_group_id" {
  description = "Security group attached to application instances"
  value       = aws_security_group.app.id
}
