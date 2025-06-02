resource "aws_ecr_repository" "this" {
  #checkov:skip=CKV_AWS_136:AES256 encryption is OK for these
  for_each = var.repository_names

  name                 = "${var.name_prefix}/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

######
# IAM
######
data "aws_iam_policy_document" "read_write_delete" {
  policy_id = "ECR_${var.name_prefix}_READ_WRITE_DELETE"

  # From https://docs.aws.amazon.com/AmazonECR/latest/userguide/security_iam_id-based-policy-examples.html
  statement {
    sid = "GetAuthorizationToken"
    actions = [
      "ecr:GetAuthorizationToken",
      "sts:GetServiceBearerToken",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageRepositoryContents"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchDeleteImage",
    ]
    resources = [for r in aws_ecr_repository.this : r.arn]
  }
}

resource "aws_iam_policy" "read_write_delete" {
  name   = data.aws_iam_policy_document.read_write_delete.policy_id
  policy = data.aws_iam_policy_document.read_write_delete.json
}
