# A dedicated VPC rather than the default one, so the stack reproduces
# identically in any account or region without inheriting local defaults.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.name }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 0)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "this" {
  name        = var.name
  description = "Inbound SSH (and optionally RDP) for ${var.name}"
  vpc_id      = aws_vpc.this.id

  tags = { Name = var.name }
}

# Only standalone rule resources are used, never an inline `ingress` block.
# Terraform then manages exactly the rules declared below and leaves any other
# rule on the group alone, which is what lets `vm allow-ip` add a temporary
# rule for whatever network you happen to be on without the next apply
# reverting it.

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "SSH"
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rdp" {
  for_each = var.enable_rdp ? toset(var.allowed_cidrs) : toset([])

  security_group_id = aws_security_group.this.id
  description       = "RDP"
  cidr_ipv4         = each.value
  from_port         = 3389
  to_port           = 3389
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
