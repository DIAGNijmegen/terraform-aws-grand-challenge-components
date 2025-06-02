# Creates buckets for temporary objects, note that all objects
# will be automatically deleted!

resource "aws_s3_bucket" "io" {
  for_each = toset(["inputs", "outputs"])

  #checkov:skip=CKV_AWS_21:No need for versioning on this bucket
  #checkov:skip=CKV_AWS_144:No need for cross-region replication on this bucket
  #checkov:skip=CKV_AWS_145:KMS not required, AES256 is ok
  #checkov:skip=CKV2_AWS_62:No need for event notifications for this bucket

  # False positives:
  #checkov:skip=CKV_AWS_18:Logging is enabled
  #checkov:skip=CKV2_AWS_61:Bucket has a lifecycle configuration
  #checkov:skip=CKV2_AWS_6:Bucket has a public access block
  bucket = "${var.name_prefix}-components-${each.key}"
}

resource "aws_s3_bucket_accelerate_configuration" "io" {
  for_each = aws_s3_bucket.io

  bucket = each.value.id
  status = "Suspended"
}

resource "aws_s3_bucket_ownership_controls" "io" {
  for_each = aws_s3_bucket.io

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "io" {
  for_each = aws_s3_bucket.io

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_logging" "io" {
  for_each = aws_s3_bucket.io

  bucket        = each.value.id
  target_bucket = var.logs_bucket_name
  target_prefix = "s3/${each.value.id}/"
}

resource "aws_s3_bucket_versioning" "io" {
  for_each = aws_s3_bucket.io

  bucket = each.value.id

  versioning_configuration {
    status     = "Suspended"
    mfa_delete = "Disabled"
  }

  lifecycle {
    ignore_changes = [
      mfa
    ]
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "io" {
  for_each = aws_s3_bucket.io

  bucket = each.value.id

  rule {
    id = "cleanup-deleted-objects"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    status = "Enabled"
  }

  rule {
    id = "expire-old-objects"

    filter {
      prefix = ""
    }

    expiration {
      days = 1
    }

    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "io" {
  for_each = aws_s3_bucket.io

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
