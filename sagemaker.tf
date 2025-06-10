# All SageMaker resources are created in grand challenge itself
# Here, we only set the security groups and permissions
#
# Execution - The role that SageMaker assumes, and the inference jobs use.
#             Permissions are attached to this for the inference jobs to
#             read and write from the components I/O buckets.
#             There is currently no way to separate SageMakers Role
#             (the execution role in ECS) with the Inference Jobs Role
#             (the task role in ECS).
#             Therefore, the permissions given to the task are broad,
#             but, we're running in a VPC with only access to the
#             components I/O buckets.
#
# Schedule - This role is passed to our own grand challenge workers
#            who can create SageMaker jobs, read/write/delete
#            components I/O bucket contents, etc.
#

resource "aws_security_group" "execution" {
  #checkov:skip=CKV2_AWS_5: This will be attached to SageMaker instances by the django application
  name        = "${var.name_prefix}-components"
  description = "Restrict network for component execution"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_egress_rule" "to_s3_gateway" {
  security_group_id = aws_security_group.execution.id
  description       = "To S3 gateway"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
}

##################
# IAM - Execution
##################
resource "aws_iam_role" "execution" {
  name               = "SAGEMAKER_${var.name_prefix}-components_EXECUTION"
  assume_role_policy = data.aws_iam_policy_document.sm_assume_role.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = aws_iam_policy.execution.arn
}

data "aws_iam_policy_document" "sm_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "execution" {
  policy_id = "SAGEMAKER_${var.name_prefix}-components_EXECUTION"

  # From https://docs.aws.amazon.com/AmazonECR/latest/userguide/security_iam_id-based-policy-examples.html
  statement {
    sid = "GetAuthorizationToken"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ReadInputs"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${aws_s3_bucket.io["inputs"].arn}/*"
    ]
  }

  statement {
    sid = "WriteOutputs"
    actions = [
      "s3:PutObject",
    ]
    resources = [
      "${aws_s3_bucket.io["outputs"].arn}/*"
    ]
  }

  statement {
    sid = "GetRepositoryContents"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [for r in aws_ecr_repository.this : r.arn]
  }

  statement {
    sid = "PutLogEvents"
    actions = [
      "logs:CreateLogGroup", # SM tries to create the log group even if it exists
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.training_jobs.arn}:*"
    ]
  }

  statement {
    sid = "PutMetrics"
    actions = [
      "cloudwatch:PutMetricData",
    ]
    resources = [
      "*" # Resource level scopes not supported for cloudwatch
    ]
  }

  statement {
    sid = "ViewVPCInfo"
    actions = [
      # All of these can only can be limited by ec2:Region
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs",
      "ec2:DescribeDhcpOptions",
    ]
    resources = [
      "*"
    ]
  }

  statement {
    sid = "AttachToVPC"
    actions = [
      "ec2:CreateNetworkInterface",
    ]
    resources = flatten([
      [for s in aws_subnet.private : s.arn],
      aws_security_group.execution.arn,
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*",
    ])
  }

  statement {
    sid = "DetatchFromVPC"
    actions = [
      "ec2:DeleteNetworkInterface",
    ]
    resources = [
      # Allows deleting any network interface but this is safe
      # as there is no EC2 endpoint in the VPC
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*",
    ]
  }

  statement {
    sid = "ModifyInterfaces"
    actions = [
      "ec2:CreateNetworkInterfacePermission",
      "ec2:DeleteNetworkInterfacePermission",
    ]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "ec2:Vpc"
      values   = [aws_vpc.this.arn]
    }
  }
}

resource "aws_iam_policy" "execution" {
  name   = data.aws_iam_policy_document.execution.policy_id
  policy = data.aws_iam_policy_document.execution.json
}

#################
# IAM - Schedule
#################
data "aws_iam_policy_document" "schedule" {
  policy_id = "SAGEMAKER_${var.name_prefix}-components_SCHEDULE"

  statement {
    sid = "GetJobLogs"
    actions = [
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.training_jobs_log_group_name}:log-stream:",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.training_jobs_log_group_name}:log-stream:${var.name_prefix}-*",
    ]
  }

  statement {
    sid = "PassExecutionRole"
    actions = [
      "iam:PassRole",
    ]
    resources = [
      aws_iam_role.execution.arn,
    ]
  }

  statement {
    sid = "CreateSageMakerJobs"
    actions = [
      "sagemaker:CreateTrainingJob",
    ]
    resources = [
      "arn:aws:sagemaker:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:training-job/${var.name_prefix}-*",
    ]

    condition {
      test     = "NumericLessThanEquals"
      variable = "sagemaker:MaxRuntimeInSeconds"
      values   = ["${var.maximum_runtime_seconds}"]
    }

    condition {
      test     = "Null"
      values   = ["false"]
      variable = "sagemaker:VpcSubnets"
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "sagemaker:VpcSubnets"
      values   = [for s in aws_subnet.private : s.id]
    }

    condition {
      test     = "Null"
      values   = ["false"]
      variable = "sagemaker:VpcSecurityGroupIds"
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "sagemaker:VpcSecurityGroupIds"
      values   = [aws_security_group.execution.id]
    }

    condition {
      test     = "Null"
      values   = ["false"]
      variable = "sagemaker:InstanceTypes"
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "sagemaker:InstanceTypes"
      values   = var.allowed_instance_types
    }

    condition {
      test     = "Bool"
      variable = "sagemaker:EnableRemoteDebug"
      values   = ["false"]
    }
  }

  statement {
    sid = "ReadStopSageMakerJobs"
    actions = [
      "sagemaker:DescribeTrainingJob",
      "sagemaker:StopTrainingJob",
    ]
    resources = [
      "arn:aws:sagemaker:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:training-job/${var.name_prefix}-*",
    ]
  }

  statement {
    sid = "GetMetricData"
    actions = [
      "cloudwatch:GetMetricData",
    ]
    resources = [
      # GetMetricData does not allow resource limitation
      "*"
    ]
  }

  statement {
    sid = "ReadWriteDeleteInputs"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
    ]
    resources = [
      "${aws_s3_bucket.io["inputs"].arn}/*",
      aws_s3_bucket.io["inputs"].arn
    ]
  }

  statement {
    sid = "ReadDeleteOutputs"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListMultipartUploadParts",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
    ]
    resources = [
      "${aws_s3_bucket.io["outputs"].arn}/*",
      aws_s3_bucket.io["outputs"].arn
    ]
  }
}

resource "aws_iam_policy" "schedule" {
  name   = data.aws_iam_policy_document.schedule.policy_id
  policy = data.aws_iam_policy_document.schedule.json
}
