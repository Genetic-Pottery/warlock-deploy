# --- Required: who you are -------------------------------------------------

variable "git_user_name" {
  description = "Name for git commits made on the box, for example \"Ada Lovelace\"."
  type        = string
}

variable "git_user_email" {
  description = "Email for git commits made on the box. Use the one tied to your GitHub account."
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key you log in with."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH in. Use your own IP as a /32, for example [\"203.0.113.7/32\"]."
  type        = list(string)

  validation {
    condition     = length(var.allowed_ssh_cidrs) > 0
    error_message = "Give at least one CIDR. Find your IP with `curl -s https://checkip.amazonaws.com`."
  }

  validation {
    condition     = alltrue([for c in var.allowed_ssh_cidrs : can(cidrhost(c, 0)) && strcontains(c, "/")])
    error_message = "Each entry must be a CIDR block. For a single IP, add /32, for example \"203.0.113.7/32\"."
  }
}

# --- Optional: AWS ---------------------------------------------------------

variable "aws_region" {
  description = "AWS region to run the box in."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use. Leave null to use the default credential chain."
  type        = string
  default     = null
}

variable "name" {
  description = "Name prefix for every AWS resource. Change it to run more than one box in an account."
  type        = string
  default     = "warlock-box"
}

variable "instance_type" {
  description = "EC2 instance type. The first boot builds warlock from source, which wants at least 4 GiB of memory."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size_gb" {
  description = "Root disk size. The Nix store and cloned repos live here."
  type        = number
  default     = 40
}

# --- Optional: NixOS -------------------------------------------------------

variable "nixos_release" {
  description = "NixOS release of the base image. Also used as system.stateVersion; don't change it on a running box."
  type        = string
  default     = "26.05"
}

variable "architecture" {
  description = "CPU architecture: \"x86_64\" (t3 and similar) or \"arm64\" (Graviton, such as t4g). Must match instance_type."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be \"x86_64\" or \"arm64\"."
  }
}

variable "username" {
  description = "Login user created on the box."
  type        = string
  default     = "warlock"
}

variable "auto_update" {
  description = "Update warlock to the latest commit on main and rebuild once a day."
  type        = bool
  default     = true
}

# --- Optional: shell -------------------------------------------------------

variable "auto_tmux" {
  description = "Attach every interactive SSH login to a persistent tmux session named `main`."
  type        = bool
  default     = true
}
