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
# One dashboard to watch the whole pipeline.
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "Scan jobs waiting in the queue"
          region  = var.aws_region
          stat    = "Maximum"
          period  = 60
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.scan_jobs.name]]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title   = "Failed jobs in the dead-letter queue"
          region  = var.aws_region
          stat    = "Maximum"
          period  = 60
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.scan_jobs_dlq.name]]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title   = "Age of oldest waiting job (seconds)"
          region  = var.aws_region
          stat    = "Maximum"
          period  = 60
          metrics = [["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", aws_sqs_queue.scan_jobs.name]]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title   = "Worker CPU (%)"
          region  = var.aws_region
          stat    = "Average"
          period  = 60
          metrics = [["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.worker.name]]
        }
      }
    ]
  })
}
