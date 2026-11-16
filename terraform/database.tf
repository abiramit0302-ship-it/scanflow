# DynamoDB table for ScanFlow scan jobs.
# Stores each job's status (PENDING, RUNNING, COMPLETED, FAILED, EXPIRED)
# and severity counts for the dashboard.

resource "aws_dynamodb_table" "scan_jobs" {
  name         = "${var.project_name}-scan-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "jobId"

  attribute {
    name = "jobId"
    type = "S"
  }
}
