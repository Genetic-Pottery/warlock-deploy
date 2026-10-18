output "public_ip" {
  description = "Fixed public IP of the box."
  value       = aws_eip.this.public_ip
}

output "instance_id" {
  description = "EC2 instance ID, for stopping and starting the box."
  value       = aws_instance.this.id
}

output "ssh_command" {
  description = "Command to log in."
  value       = "ssh ${var.username}@${aws_eip.this.public_ip}"
}

output "next_steps" {
  description = "What to do after apply."
  value       = <<-EOT
    1. Wait for first boot to finish (it builds the NixOS system):
         ../scripts/wait-for-box.sh ${var.username}@${aws_eip.this.public_ip}
    2. Log in:            ssh ${var.username}@${aws_eip.this.public_ip}
    3. Log in to GitHub:  gh auth login
    4. Log in to Claude:  claude
    5. Install warlock:   warlock-install
    6. Sign in to your tracker: in claude, run /mcp
    7. Optional, from your own machine, copy your Claude config:
         ../scripts/sync-claude-config.sh ${var.username}@${aws_eip.this.public_ip}
  EOT
}
