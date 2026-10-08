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
    ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
    git_user_name  = var.git_user_name
    git_user_email = var.git_user_email
    auto_tmux      = var.auto_tmux
    auto_update    = var.auto_update
    state_version  = var.nixos_release
    host_platform  = var.architecture == "arm64" ? "aarch64-linux" : "x86_64-linux"
  })

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    flake_nix         = base64encode(file("${path.module}/nixos/flake.nix"))
    configuration_nix = base64encode(file("${path.module}/nixos/configuration.nix"))
    box_json          = base64encode(local.box_json)
  })
}

resource "aws_key_pair" "this" {
  key_name   = var.name
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_security_group" "this" {
  name        = var.name
  description = "SSH in from allowed CIDRs; all traffic out."
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

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
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [aws_security_group.this.id]

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

# A fixed address that survives stopping and starting the instance.
resource "aws_eip" "this" {
  instance = aws_instance.this.id
  domain   = "vpc"

  tags = {
    Name = var.name
  }
}
