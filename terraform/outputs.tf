output "instance_id" {
  description = "EC2 instance ID, for stopping and starting the box."
  value       = aws_instance.this.id
}

output "ssh_command" {
  description = "Command to log in from a device on your tailnet."
  value       = "ssh ${var.username}@${var.name}"
}

output "next_steps" {
  description = "What to do after apply."
  value       = <<-EOT
    From your phone, with Tailscale and an SSH app (see the README):
    1. Wait for ${var.name} to appear in the Tailscale app.
    2. SSH to ${var.name} as ${var.username}. No password or key.
    3. Log in to GitHub:  gh auth login
    4. Log in to Claude:  cd ~/Projects && claude
    5. Install warlock:   warlock-install
    6. Check your tracker: in claude, run /mcp
    7. Turn on Remote Control: remote-control-enable
       Press Ctrl-C once ${var.name} appears in the Claude app.
  EOT
}
