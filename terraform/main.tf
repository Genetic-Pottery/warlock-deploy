data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Official NixOS images, published weekly by the NixOS project.
# See https://nixos.github.io/amis/
data "aws_ami" "nixos" {
  most_recent = true
  owners      = ["427812963091"]

  filter {
    name   = "name"
    values = ["nixos/${var.nixos_release}*"]
  }

  filter {
    name   = "architecture"
    values = [var.architecture]
  }
}

locals {
  # Per-person values the NixOS configuration reads from /etc/nixos/box.json.
  box_json = jsonencode({
    username       = var.username
    hostname       = var.name
    git_user_name  = var.git_user_name
    git_user_email = var.git_user_email
    auto_tmux      = var.auto_tmux
    auto_update    = var.auto_update
    warlock_ref    = var.warlock_ref
    state_version  = var.nixos_release
    host_platform  = var.architecture == "arm64" ? "aarch64-linux" : "x86_64-linux"
  })

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    flake_nix         = base64encode(file("${path.module}/nixos/flake.nix"))
    configuration_nix = base64encode(file("${path.module}/nixos/configuration.nix"))
    box_json          = base64encode(local.box_json)
    tailscale_authkey = base64encode(var.tailscale_auth_key)
  })
}

resource "aws_security_group" "this" {
  name        = var.name
  description = "No inbound traffic; all traffic out."
  vpc_id      = data.aws_vpc.default.id

  # No ingress rules. Tailscale and Remote Control both connect outbound.
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.nixos.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.this.id]

  # A public IP for outbound traffic only. It avoids paying for a NAT gateway.
  associate_public_ip_address = true

  user_data                   = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = var.name
  }

  lifecycle {
    # A newer NixOS image must not silently rebuild the box and wipe your
    # logins; the flake keeps the running system current instead. Run `terraform apply -replace=aws_instance.this` to rebuild.
    ignore_changes = [ami]
  }
}

