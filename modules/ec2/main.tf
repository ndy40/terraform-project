variable "stack_name" {}
variable "public_subnet_id" {}
variable "vpc_id" {}

variable "public_ips" { type = map(any) }

locals {
  use_eip = length(lookup(var.public_ips, terraform.workspace, "")) > 0
}

# data "aws_eip" "ec2_ip" {
#   count     = local.use_eip == true ? 1 : 0
#   public_ip = lookup(var.public_ips, terraform.workspace)
# }

data "aws_region" "current" {}

data "aws_ami" "azm_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["packer-keyedin-*"]
  }

  filter {
    name   = "tag:Name"
    values = ["Packer-Keyedin-AMI"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["self"] # Canonical
}


# resource "aws_eip_association" "proxy_eip" {
#   count         = local.use_eip == true ? 1 : 0
#   instance_id   = aws_instance.vm.id
#   allocation_id = data.aws_eip.ec2_ip[count.index].id
# }

# resource "aws_instance" "vm" {
#   ami                         = data.aws_ami.azm_linux.id
#   instance_type               = "t2.medium"
#   associate_public_ip_address = true
#   key_name                    = aws_key_pair.generated.key_name
#   vpc_security_group_ids      = [aws_security_group.ec2_security_group.id]
#   subnet_id                   = var.public_subnet_id
#   iam_instance_profile        = aws_iam_instance_profile.vm_profile.name
#   user_data                   = file("${path.module}/user_data.sh")

#   tags = {
#     Name      = var.stack_name
#     Terraform = true
#   }
# }

resource "aws_security_group" "ec2_security_group" {
  name   = "${var.stack_name}-ec2"
  vpc_id = var.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 2376
    to_port     = 2376
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = var.stack_name
    Terraform = true
  }
}

resource "aws_iam_instance_profile" "vm_profile" {
  name = "vm_profile_${var.stack_name}_${terraform.workspace}"
  role = aws_iam_role.role.name
}

resource "aws_iam_role" "role" {
  name = "ec2_role_${var.stack_name}_${terraform.workspace}"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "ec2_role_policy" {
  name = "ec2-policy-${var.stack_name}"
  role = aws_iam_role.role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
         "Effect": "Allow",
         "Action": [
            "logs:*"
         ],
         "Resource": [
            "*"
         ]
      },
      {
         "Effect": "Allow",
         "Action": [
            "s3:ListBucket"
         ],
         "Resource": [
            "arn:aws:s3:::keyedin-private",
            "arn:aws:s3:::keyedin-public"
         ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:Put*",
          "s3:Get*",
          "s3:List*",
          "s3:AbortMultipartUpload"

        ],
        "Resource": [
          "arn:aws:s3:::keyedin-private/*",
          "arn:aws:s3:::keyedin-public/*"
        ]
      },
      {
         "Effect": "Allow",
         "Action": [
            "s3:Get*",
            "s3:List*"
         ],
         "Resource": [
            "arn:aws:s3:::aws-codedeploy-${data.aws_region.current.name}/*"
         ]
      },
      {
        "Effect": "Allow",
        "Action": [
            "ssm:DescribeAssociation",
            "ssm:GetDocument",
            "ssm:ListAssociations",
            "ssm:UpdateAssociationStatus",
            "ssm:UpdateInstanceInformation",
            "ssm:GetParameters"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
            "ec2messages:AcknowledgeMessage",
            "ec2messages:DeleteMessage",
            "ec2messages:FailMessage",
            "ec2messages:GetEndpoint",
            "ec2messages:GetMessages",
            "ec2messages:SendReply"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "ecr:*"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "elasticloadbalancing:Describe*",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:RegisterTargets",
          "autoscaling:Describe*",
          "autoscaling:EnterStandby",
          "autoscaling:ExitStandby",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:SuspendProcesses",
          "autoscaling:ResumeProcesses"
        ],
        "Resource": "*"
      }
  ]
}
EOF
}

locals {
  public_key_filename  = "./ssh/key-keyedin-${terraform.workspace}.pub"
  private_key_filename = "./ssh/key-keyedin-${terraform.workspace}"
}

resource "tls_private_key" "default" {
  algorithm = "RSA"
}

resource "aws_key_pair" "generated" {
  depends_on = [tls_private_key.default]
  key_name   = "key-${var.stack_name}-${terraform.workspace}"
  public_key = tls_private_key.default.public_key_openssh
}

resource "local_file" "public_key_openssh" {
  depends_on = [tls_private_key.default]
  content    = tls_private_key.default.public_key_openssh
  filename   = local.public_key_filename
}

resource "local_file" "private_key_pem" {
  depends_on = [tls_private_key.default]
  content    = tls_private_key.default.private_key_pem
  filename   = local.private_key_filename
}

resource "null_resource" "chmod" {
  depends_on = [local_file.private_key_pem]

  provisioner "local-exec" {
    command = "chmod 400 ${local.private_key_filename}"
  }
}
