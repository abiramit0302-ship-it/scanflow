# CloudWatch alarms for ScanFlow.
# They watch the queues so we know when scans fail or get stuck.

resource "aws_cloudwatch_metric_alarm" "dlq_has_messages" {
  alarm_name          = "${var.project_name}-dlq-has-messages"
  alarm_description   = "A scan job failed 3 times and moved to the dead-letter queue"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.scan_jobs_dlq.name
  }
}

resource "aws_cloudwatch_metric_alarm" "jobs_stuck" {
  alarm_name          = "${var.project_name}-jobs-stuck"
  alarm_description   = "The oldest scan job has waited over 15 minutes, so the worker may be down"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 900
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.scan_jobs.name
  }
}