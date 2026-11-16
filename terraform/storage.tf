# S3 buckets for ScanFlow.
# uploads: the zipped code people submit for scanning
# reports: the JSON scan reports the worker saves
#
# Learner Lab's service control policy blocks s3:GetBucketObjectLockConfiguration,
# which the AWS provider calls when it manages an aws_s3_bucket resource.
# So the two buckets are created once outside Terraform (like the state bucket),
# and Terraform looks them up with data sources. Everything attached to them
# (public access blocks, the SQS notification) is still managed here.

data "aws_caller_identity" "current" {}

data "aws_s3_bucket" "uploads" {
  bucket = "${var.project_name}-uploads-${data.aws_caller_identity.current.account_id}"
}

data "aws_s3_bucket" "reports" {
  bucket = "${var.project_name}-reports-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = data.aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = data.aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
