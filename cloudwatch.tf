locals {
  training_jobs_log_group_name = "/aws/sagemaker/TrainingJobs" # Set by SageMaker, do not change
  stopped_jobs_log_group_name  = "/aws/events/${var.name_prefix}-components-stopped-jobs"
}

data "aws_iam_policy_document" "kms_policy" {
  policy_id = "KMS_${var.name_prefix}-${local.training_jobs_log_group_name}_ENCRYPT_LOGS"

  #checkov:skip=CKV_AWS_109:Policy is from AWS
  #checkov:skip=CKV_AWS_111:Policy is from AWS
  #checkov:skip=CKV_AWS_356:Policy is from AWS
  # Policy from https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html#cmk-permissions

  statement {
    sid       = "Enable IAM User Permissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    sid    = "Allow CloudWatch Logs"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.training_jobs_log_group_name}",
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.stopped_jobs_log_group_name}",
      ]
    }
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "sagemaker" {
  description         = "KMS for SAGEMAKER ${var.name_prefix}"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms_policy.json
}

resource "aws_kms_alias" "sagemaker" {
  name          = "alias/${jsondecode(aws_kms_key.sagemaker.policy).Id}"
  target_key_id = aws_kms_key.sagemaker.key_id
}

resource "aws_cloudwatch_log_group" "training_jobs" {
  name              = local.training_jobs_log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.sagemaker.arn
}
