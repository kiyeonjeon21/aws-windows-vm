output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "Address to SSH to. Stable across stop/start only when associate_eip is true."
  value       = var.associate_eip ? aws_eip.this[0].public_ip : aws_instance.this.public_ip
}

output "ssh_command" {
  description = "Ready to paste SSH command."
  value       = "ssh Administrator@${var.associate_eip ? aws_eip.this[0].public_ip : aws_instance.this.public_ip}"
}

output "administrator_password_command" {
  description = "Reads the Administrator password the instance generated for itself at first boot. Needed for RDP only; SSH uses your key."
  value       = "aws ssm get-parameter --name ${local.ssm_prefix}/administrator-password --with-decryption --region ${var.region} --query Parameter.Value --output text"
}

output "session_manager_command" {
  description = "Fallback shell that does not depend on port 22 or on your source address."
  value       = "aws ssm start-session --target ${aws_instance.this.id} --region ${var.region}"
}

output "ssh_config_block" {
  description = "Block to append to ~/.ssh/config so the instance is reachable by name."
  value       = <<-EOT
    Host ${var.name}
      HostName ${var.associate_eip ? aws_eip.this[0].public_ip : aws_instance.this.public_ip}
      User Administrator
      IdentityFile ~/.ssh/id_ed25519
      ServerAliveInterval 30
      ServerAliveCountMax 6
  EOT
}
