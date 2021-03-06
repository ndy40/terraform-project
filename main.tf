variable "stack_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_profile" {
  type = string
}

variable "public_ips" {
  type = map(any)
}

variable "stack_domain" {}

variable "mailgun_api_key" {}

variable "mailgun_smtp_password" {}



provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket  = "keyedin-private"
    key     = "infrastructure/terraform.tfstate"
    region  = "eu-west-2"
    profile = "keyedin"
  }
}

// VPC
module "vpc" {
  source     = "./modules/vpc"
  stack_name = var.stack_name
}

// vm
module "ec2" {
  source           = "./modules/ec2"
  stack_name       = var.stack_name
  vpc_id           = module.vpc.vpc_id
  public_subnet_id = module.vpc.public_subnet_ids[0]
  public_ips       = var.public_ips
}

module "s3" {
  source     = "./modules/s3"
  stack_name = var.stack_name
}

// database
module "aurora" {
  source     = "./modules/aurora"
  stack_name = var.stack_name
  subnet_ids = module.vpc.public_subnet_ids
  vpc_id     = module.vpc.vpc_id
}


module "ecr" {
  source     = "./modules/ecr"
  stack_name = var.stack_name
}

module "elb" {
  source     = "./modules/elb"
  stack_name = var.stack_name
  subnet_ids = module.vpc.public_subnet_ids
  # ec2_instance_ids = [module.ec2.vm_id]
  vpc_id = module.vpc.vpc_id
  security_groups = [
    module.vpc.vpc_sg,
    module.ec2.ec2_sg
  ]
}

module "bastion" {
  source        = "./modules/bastion"
  stack_name    = var.stack_name
  subnet_id     = module.vpc.public_subnet_ids[1]
  vpc_id        = module.vpc.vpc_id
  allowed_hosts = module.vpc.vpc_cidr_block
  key_name      = module.ec2.ec2_keyname
}

module "cloudwatch" {
  source     = "./modules/cloudwatch"
  stack_name = var.stack_name
}

module "autoscaling" {
  source               = "./modules/autoscaling"
  stack_name           = var.stack_name
  amz_ami              = module.ec2.amz_ami
  loadbalancer_arn     = module.elb.elb_arn
  iam_instance_profile = module.ec2.vm_profile_id
  subnet_ids           = module.vpc.public_subnet_ids
  ec2_sg               = module.ec2.ec2_sg
  key_name             = module.ec2.ec2_keyname
  alb_target_group_arn = module.elb.alb_target_group_arn
}


module "codedeploy" {
  source             = "./modules/codedeploy"
  stack_name         = var.stack_name
  keyedin_lb_tg_name = module.elb.alb_target_group_name
  keyedin_alb_id     = module.elb.elb_id
  keyedin_asg        = module.autoscaling.autoscaling_gp
}

module "dns" {
  source         = "./modules/dns"
  stack_name     = var.stack_name
  stack_domain   = var.stack_domain
  stack_alb_name = module.elb.elb_name
}

# provider "mailgun" {
#   api_key = "${var.mailgun_api_key}"
# }



# "module" "mailgun_domain" {
#   source                = "github.com/samstav/terraform-mailgun-aws"
#   domain                = "${var.stack_domain}"
#   mailgun_smtp_password = "${var.mailgun_smtp_password}"
# }
