# SQS queues for ScanFlow.
# A new zip upload in S3 sends a message to scan_jobs, and the worker picks up jobs from there.
# A job that fails 3 times moves to the dead-letter queue (DLQ) so it isn't lost.

resource "aws_sqs_queue" "scan_jobs_dlq" {
  name                      = "${var.project_name}-scan-jobs-dlq"
  message_retention_seconds = 1209600 # 14 days, time to look into failed jobs
}

resource "aws_sqs_queue" "scan_jobs" {
  name                       = "${var.project_name}-scan-jobs"
  visibility_timeout_seconds = 900    # 15 minutes, longer than one scan should take
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 20     # long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.scan_jobs_dlq.arn
    maxReceiveCount     = 3
  })
}

# Allow only our uploads bucket to send messages to the queue
resource "aws_sqs_queue_policy" "scan_jobs" {
  queue_url = aws_sqs_queue.scan_jobs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.scan_jobs.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_s3_bucket.uploads.arn }
      }
    }]
  })
}

# When a .zip file is uploaded, S3 sends a message to the queue
resource "aws_s3_bucket_notification" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  queue {
    queue_arn     = aws_sqs_queue.scan_jobs.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".zip"
  }

  depends_on = [aws_sqs_queue_policy.scan_jobs]
}