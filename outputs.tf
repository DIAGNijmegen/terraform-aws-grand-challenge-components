######
# ECR
######
output "aws_ecr_repositories" {
  value = aws_ecr_repository.this
}

output "registry_read_write_delete_policy_arn" {
  value = aws_iam_policy.read_write_delete.arn
}

locals {
  repository_url_parts = split(
    "/",
    coalesce(
      # SUPER UGLY, but all the prefixes will be the same
      [for r in aws_ecr_repository.this : r.repository_url]...
    )
  )
}

output "registry_prefix" {
  value = local.repository_url_parts[1]
}

output "registry_url" {
  value = local.repository_url_parts[0]
}

############
# SAGEMAKER
############
output "schedule_policy_arn" {
  value = aws_iam_policy.schedule.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "input_bucket_name" {
  value = aws_s3_bucket.io["inputs"].bucket
}

output "output_bucket_name" {
  value = aws_s3_bucket.io["outputs"].bucket
}

output "private_subnet_ids" {
  value = [for v in values(aws_subnet.private) : v.id]
}

output "security_group_id" {
  value = aws_security_group.execution.id
}

output "cloudwatch_event_stopped_training_jobs_arn" {
  value = aws_cloudwatch_event_rule.stopped_training_jobs.arn
}
