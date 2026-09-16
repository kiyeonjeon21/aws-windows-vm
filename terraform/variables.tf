variable "name" {
  description = "Name prefix applied to every resource, and the value of the EC2 Name tag. The `vm` CLI locates the instance by this tag."
  type        = string
  default     = "winvm"
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Instance type. c6i.xlarge and c7i.xlarge are both exactly 4 vCPU / 8 GiB."
  type        = string
  default     = "c6i.xlarge"
}

variable "windows_ami_ssm_parameter" {
  description = "Public SSM parameter that resolves to the latest Windows AMI. Swap the 2025 for 2022 if you need the older server release."
  type        = string
  default     = "/aws/service/ami-windows-latest/Windows_Server-2025-English-Full-Base"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB. Windows Server itself takes roughly 20 GiB before you install anything."
  type        = number
  default     = 100

  validation {
    condition     = var.root_volume_size >= 40
    error_message = "Windows Server needs at least 40 GiB to leave usable room for tooling."
  }
}

variable "ssh_public_key" {
  description = "OpenSSH public key authorised for the Administrator account. Paste the contents of a .pub file."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) ", var.ssh_public_key))
    error_message = "Expected an OpenSSH public key line, for example the contents of ~/.ssh/id_ed25519.pub."
  }
}

variable "allowed_cidrs" {
  description = "Source CIDRs allowed to reach SSH (and RDP, if enabled). Keep this to your own address. `vm allow-ip` rewrites it to your current address without a terraform run."
  type        = list(string)

  validation {
    condition     = !contains(var.allowed_cidrs, "0.0.0.0/0")
    error_message = "Refusing to expose SSH/RDP to the whole internet. Use your own address, or reach the host through Session Manager instead."
  }
}

variable "enable_rdp" {
  description = "Open TCP 3389 to allowed_cidrs. SSH alone is enough for a coding agent; enable this only when you actually need the desktop."
  type        = bool
  default     = false
}

variable "associate_eip" {
  description = "Attach an Elastic IP so the address survives stop/start. Costs about USD 3.60 per month, and saves rewriting ~/.ssh/config after every restart."
  type        = bool
  default     = true
}

variable "idle_shutdown_minutes" {
  description = "Stop the instance after this many consecutive idle minutes. Idle means no established SSH or RDP connection and low CPU. Set to 0 to disable."
  type        = number
  default     = 30
}

variable "idle_shutdown_cpu_threshold" {
  description = "CPU percentage above which the host counts as busy even with no session attached, so a long build started over SSH is not killed after you disconnect."
  type        = number
  default     = 15
}

variable "setup_repo_url" {
  description = "HTTPS URL of this repository. The instance clones it at first boot and runs bootstrap/setup.ps1 from it."
  type        = string
}

variable "setup_ref" {
  description = "Branch or tag of setup_repo_url to clone."
  type        = string
  default     = "main"
}

variable "vpc_cidr" {
  description = "CIDR for the dedicated VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "tags" {
  description = "Extra tags merged into the provider default tags."
  type        = map(string)
  default     = {}
}

variable "idle_backstop_hours" {
  description = "Stop the instance after this many hours of low CPU, regardless of what the in-guest watchdog is doing. This is a backstop for the watchdog failing silently, not the normal mechanism, so keep it well above idle_shutdown_minutes. Set to 0 to disable."
  type        = number
  default     = 2
}

variable "idle_backstop_cpu_threshold" {
  description = "CPU percentage below which the backstop alarm counts a period as idle."
  type        = number
  default     = 5
}

variable "budget_alert_email" {
  description = "Address to email when account spend crosses the thresholds below. Empty disables the budget entirely."
  type        = string
  default     = ""
}

variable "budget_monthly_limit" {
  description = "Monthly account spend in USD that the alerts are measured against."
  type        = number
  default     = 50
}
