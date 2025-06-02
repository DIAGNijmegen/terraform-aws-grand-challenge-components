resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr_block

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix} Components VPC"
  }
}

resource "aws_flow_log" "vpc" {
  log_destination      = "${var.logs_bucket_arn}/vpc/${aws_vpc.this.id}/"
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.this.id

  destination_options {
    file_format                = "parquet"
    hive_compatible_partitions = true
    per_hour_partition         = true
  }
}

resource "aws_default_security_group" "vpc" {
  vpc_id = aws_vpc.this.id
}

resource "aws_default_route_table" "this" {
  # NOTE DO NOT USE aws_main_route_table_association with this!
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_route_table
  default_route_table_id = aws_vpc.this.default_route_table_id

  route = []

  tags = {
    Name = "${var.name_prefix} Components VPC Main Routes"
  }
}

resource "aws_default_network_acl" "this" {
  default_network_acl_id = aws_vpc.this.default_network_acl_id

  tags = {
    Name = "${var.name_prefix} Components VPC Main NACL"
  }
}

resource "aws_route_table" "private" {
  for_each = var.private_subnet_cidr_blocks

  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix} Components VPC ${each.key} Private Routes"
  }
}

resource "aws_subnet" "private" {
  for_each = var.private_subnet_cidr_blocks

  vpc_id     = aws_vpc.this.id
  cidr_block = each.value

  availability_zone_id = each.key

  tags = {
    Name = "${var.name_prefix} Components VPC ${each.key} Private Subnet"
  }
}

resource "aws_route_table_association" "private" {
  for_each = var.private_subnet_cidr_blocks

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_network_acl" "private" {
  for_each = var.private_subnet_cidr_blocks

  vpc_id     = aws_vpc.this.id
  subnet_ids = [aws_subnet.private[each.key].id]

  dynamic "ingress" {
    for_each = aws_vpc_endpoint.s3.cidr_blocks
    content {
      protocol   = "tcp"
      rule_no    = 100 + ingress.key
      action     = "allow"
      cidr_block = ingress.value
      from_port  = 1024
      to_port    = 65535
    }
  }

  dynamic "egress" {
    for_each = aws_vpc_endpoint.s3.cidr_blocks
    content {
      protocol   = "tcp"
      rule_no    = 100 + egress.key
      action     = "allow"
      cidr_block = egress.value
      from_port  = 443
      to_port    = 443
    }
  }

  tags = {
    Name = "${var.name_prefix} Components VPC ${each.key} Private NACL"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  tags = {
    Name = "${var.name_prefix} Components VPC ${data.aws_region.current.name} S3 Gateway"
  }
}

data "aws_iam_policy_document" "s3_endpoint" {
  statement {
    principals {
      # Use conditions rather than principals for gateway policies
      # https://jackiechen.blog/2020/08/26/endpoint-policies-for-gateway-endpoints/
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "${aws_s3_bucket.io["inputs"].arn}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalArn"
      values   = [aws_iam_role.execution.arn]
    }
  }

  statement {
    principals {
      # Use conditions rather than principals for gateway policies
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "${aws_s3_bucket.io["outputs"].arn}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalArn"
      values   = [aws_iam_role.execution.arn]
    }
  }
}

resource "aws_vpc_endpoint_policy" "s3" {
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
  policy          = data.aws_iam_policy_document.s3_endpoint.json
}

resource "aws_vpc_endpoint_route_table_association" "s3" {
  for_each = aws_route_table.private

  route_table_id  = each.value.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}
