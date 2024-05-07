output "app_server_ip" {
  value = aws_instance.app_server.public_ip
}

output "app_server_id" {
  value = aws_instance.app_server.id
}