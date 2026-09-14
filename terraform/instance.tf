data "aws_ssm_parameter" "windows_ami" {
  name = var.windows_ami_ssm_parameter
}

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.windows_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  # The idle watchdog stops the box with an OS-level shutdown, so the shutdown
  # must stop the instance rather than terminate it.
  instance_initiated_shutdown_behavior = "stop"

  # First boot only. Editing the template afterwards does not re-run it; SSH in
  # and run bootstrap/setup.ps1 by hand, or rebuild the instance with
  # `terraform apply -replace=aws_instance.this`.
  user_data_replace_on_change = false

  user_data = templatefile("${path.module}/../bootstrap/userdata.ps1.tftpl", {
    ssh_public_key        = trimspace(var.ssh_public_key)
    region                = var.region
    ssm_prefix            = local.ssm_prefix
    idle_shutdown_minutes = var.idle_shutdown_minutes
    idle_cpu_threshold    = var.idle_shutdown_cpu_threshold
    setup_repo_url        = var.setup_repo_url
    setup_ref             = var.setup_ref
  })

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = { Name = var.name }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = { Name = var.name }

  lifecycle {
    # AWS publishes a new Windows AMI every month. Without this, an unrelated
    # apply would destroy the box and everything on its disk just because the
    # SSM parameter moved. Move to a newer AMI deliberately instead, with
    # `terraform apply -replace=aws_instance.this`.
    ignore_changes = [ami]
  }
}

resource "aws_eip" "this" {
  count = var.associate_eip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.this.id

  tags = { Name = var.name }

  depends_on = [aws_internet_gateway.this]
}
