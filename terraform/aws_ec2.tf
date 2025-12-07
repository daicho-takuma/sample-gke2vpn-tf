#########################
# EC2
#########################
resource "aws_instance" "vms" {
  for_each                    = merge(local.aws_instance_config.ec2_public, local.aws_instance_config.ec2_private)
  ami                         = data.aws_ssm_parameter.amzn2_ami.value
  availability_zone           = each.value.az
  ebs_optimized               = true
  disable_api_termination     = each.value.protected
  instance_type               = each.value.type
  key_name                    = each.value.key_name
  vpc_security_group_ids      = [aws_security_group.web.id]
  subnet_id                   = can(regex(".*public.*", each.value.subnet_name)) ? aws_subnet.public[each.value.subnet_name].id : aws_subnet.private[each.value.subnet_name].id
  associate_public_ip_address = can(regex(".*public.*", each.value.subnet_name))
  private_ip                  = each.value.private_ip
  iam_instance_profile        = aws_iam_instance_profile.vms[each.key].id
  tags = {
    Name = each.key
  }
  volume_tags = {
    Name = "${local.env}-${local.project}-${each.key}-root"
  }
  root_block_device {
    volume_type = each.value.vol_type
    volume_size = each.value.vol_size
    encrypted   = each.value.vol_encrypted
  }

  user_data = <<EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "Hello World from ${each.key}" > /var/www/html/index.html
  EOF

  metadata_options {
    instance_metadata_tags = "enabled"
  }
  lifecycle {
    ignore_changes = [ami, root_block_device.0.delete_on_termination]
  }
}

resource "aws_eip" "public_eip" {
  for_each = local.aws_instance_config.ec2_public
  instance = aws_instance.vms[each.key].id
  tags = {
    Name = each.key
  }
  depends_on = [aws_internet_gateway.igw]
}

# ----------------------
# AMI
# ----------------------
data "aws_ssm_parameter" "amzn2_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

# ----------------------
# IAM Role
# ----------------------
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vms" {
  for_each           = merge(local.aws_instance_config.ec2_public, local.aws_instance_config.ec2_private)
  name               = "${each.key}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags = {
    Name = "${each.key}-role"
  }
}

resource "aws_iam_role_policy_attachment" "vms" {
  for_each   = merge(local.aws_instance_config.ec2_public, local.aws_instance_config.ec2_private)
  role       = aws_iam_role.vms[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "vms" {
  for_each = merge(local.aws_instance_config.ec2_public, local.aws_instance_config.ec2_private)
  name     = "${each.key}-profile"
  role     = aws_iam_role.vms[each.key].name
}

# ----------------------
# Security Group
# ----------------------
resource "aws_security_group" "web" {
  vpc_id = aws_vpc.vpc.id
  name   = "${local.env}-${local.project}-sg"
  tags = {
    Name = "${local.env}-${local.project}-web-sg"
  }
}

# Ingress Rules
resource "aws_security_group_rule" "web_ingress_http_all" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [local.gcp_producer_network_config.proxy_subnet["${local.env}-${local.project}-gcp-producer-ilb-proxy-subnet"].cidr]
  security_group_id = aws_security_group.web.id
  description       = "Allow HTTP from GCP Producer VPC"
}

resource "aws_security_group_rule" "web_ingress_icmp_all" {
  type              = "ingress"
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
  description       = "Allow ICMP from ALL"
}

# Egress Rules
resource "aws_security_group_rule" "web_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

# ----------------------
# key-par
# ----------------------
resource "tls_private_key" "ec2-user" {
  #algorithm = "ED25519"
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ec2-user" {
  filename        = "../misc/${local.env}-${local.project}-ec2-user.key"
  content         = tls_private_key.ec2-user.private_key_pem
  file_permission = 0600
}

resource "local_file" "ec2-user-private" {
  filename        = "../misc/${local.env}-${local.project}-ec2-user.key.pub"
  content         = tls_private_key.ec2-user.public_key_openssh
  file_permission = 0600
}

resource "aws_key_pair" "ec2-user" {
  key_name   = "${local.env}-${local.project}-ec2-user-key"
  public_key = tls_private_key.ec2-user.public_key_openssh
}
