data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  ssm_prefix    = "/${var.name}"
  ssm_param_arn = "arn:${data.aws_partition.current.partition}:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}/*"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-instance"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Session Manager. This is the way back in when SSH is unreachable, for example
# after a change of network or a security group edit that locked you out.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# The instance generates its own Administrator password at first boot and files
# it here, so the password never passes through Terraform state.
data "aws_iam_policy_document" "instance" {
  statement {
    sid       = "PublishOwnParameters"
    actions   = ["ssm:PutParameter", "ssm:GetParameter"]
    resources = [local.ssm_param_arn]
  }

  statement {
    sid       = "EncryptOwnParameters"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "instance" {
  name   = "${var.name}-instance"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-instance"
  role = aws_iam_role.instance.name
}
