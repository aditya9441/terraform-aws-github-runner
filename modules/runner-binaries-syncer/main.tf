locals {
  action_runner_distribution_object_key = "actions-runner-${var.runner_os}.${var.runner_os == "linux" ? "tar.gz" : "zip"}"
}

resource "aws_s3_bucket" "action_dist" {
  bucket        = var.distribution_bucket_name
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_acl" "action_dist_acl" {
  bucket = aws_s3_bucket.action_dist.id
  depends_on = [aws_s3_bucket_ownership_controls.s3_bucket_acl_ownership]
  acl    = "private"
}

resource "aws_s3_bucket_ownership_controls" "s3_bucket_acl_ownership" {
  bucket = aws_s3_bucket.action_dist.id
  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket-config" {
  bucket = aws_s3_bucket.action_dist.id

  rule {
    id     = "lifecycle_config"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = 35
      storage_class = "INTELLIGENT_TIERING"
    }


  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "action_dist" {
  bucket = aws_s3_bucket.action_dist.id
  count  = try(var.server_side_encryption_configuration, null) != null ? 1 : 0

  dynamic "rule" {
    for_each = [lookup(var.server_side_encryption_configuration, "rule", {})]

    content {
      bucket_key_enabled = lookup(rule.value, "bucket_key_enabled", null)

      dynamic "apply_server_side_encryption_by_default" {
        for_each = length(keys(lookup(rule.value, "apply_server_side_encryption_by_default", {}))) == 0 ? [] : [
        lookup(rule.value, "apply_server_side_encryption_by_default", {})]

        content {
          sse_algorithm     = apply_server_side_encryption_by_default.value.sse_algorithm
          kms_master_key_id = lookup(apply_server_side_encryption_by_default.value, "kms_master_key_id", null)
        }
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "action_dist" {
  bucket                  = aws_s3_bucket.action_dist.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}



data "aws_iam_policy_document" "action_dist_sse_policy" {
  count = try(var.server_side_encryption_configuration.rule.apply_server_side_encryption_by_default, null) != null ? 1 : 0

  statement {
    effect = "Deny"

    principals {
      type = "AWS"

      identifiers = [
        "*",
      ]
    }

    actions = [
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.action_dist.arn}/*",
    ]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = [var.server_side_encryption_configuration.rule.apply_server_side_encryption_by_default.sse_algorithm]
    }
  }
}

resource "aws_s3_bucket_policy" "action_dist_sse_policy" {
  count  = try(var.server_side_encryption_configuration.rule.apply_server_side_encryption_by_default, null) != null ? 1 : 0
  bucket = aws_s3_bucket.action_dist.id
  policy = data.aws_iam_policy_document.action_dist_sse_policy[0].json
}
