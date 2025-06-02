resource "aws_cloudwatch_log_group" "stopped_jobs" {
  # Must be prefixed with /aws/events/
  # This is very sensitive, see https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-use-resource-based.html#eb-cloudwatchlogs-permissions
  # and https://github.com/aws-cloudformation/cloudformation-coverage-roadmap/issues/351
  name              = local.stopped_jobs_log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.sagemaker.arn
}

data "aws_iam_policy_document" "stopped_jobs" {
  # This is very sensitive, see https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-use-resource-based.html#eb-cloudwatchlogs-permissions
  # and https://github.com/aws-cloudformation/cloudformation-coverage-roadmap/issues/351
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/events/*:*"
    ]

    principals {
      identifiers = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "stopped_jobs" {
  policy_document = data.aws_iam_policy_document.stopped_jobs.json
  policy_name     = "${var.name_prefix}-components-stopped-jobs-put-logs"
}

resource "aws_cloudwatch_event_rule" "stopped_training_jobs" {
  name = "${var.name_prefix}-components-stopped-training-jobs"
  # Pattern from https://docs.aws.amazon.com/sagemaker/latest/dg/automating-sagemaker-with-eventbridge.html#eventbridge-training
  # Filters from https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_DescribeTrainingJob.html#API_DescribeTrainingJob_ResponseSyntax
  event_pattern = <<EOF
{
  "detail-type": [
    "SageMaker Training Job State Change"
  ],
  "source": [
    "aws.sagemaker"
  ],
  "detail": {
    "TrainingJobStatus": [
      "Completed",
      "Failed",
      "Stopped"
    ]
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "stopped_training_jobs" {
  rule = aws_cloudwatch_event_rule.stopped_training_jobs.name
  arn  = aws_cloudwatch_log_group.stopped_jobs.arn
}

resource "aws_cloudwatch_event_target" "stopped_training_jobs_sqs" {
  rule = aws_cloudwatch_event_rule.stopped_training_jobs.name
  arn  = var.stopped_events_queue_arn

  input_transformer {
    input_paths = {
      id    = "$.id"
      event = "$.detail"
    }
    input_template = <<EOF
{
  "id": <id>,
  "content-encoding": "utf-8",
  "content-type": "application/json",
  "task": "grandchallenge.components.tasks.handle_event",
  "kwargs": {
    "event": <event>,
    "backend": "grandchallenge.components.backends.amazon_sagemaker_training.AmazonSageMakerTrainingExecutor"
  }
}
EOF
  }
}
