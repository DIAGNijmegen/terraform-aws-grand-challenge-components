terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "region-name"
    values = [data.aws_region.current.name]
  }

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  private_subnet_cidr_blocks = {
    for idx, subnet in sort(data.aws_availability_zones.available.zone_ids) :
    subnet => cidrsubnet(var.vpc_cidr_block, 4, idx)
  }
}
