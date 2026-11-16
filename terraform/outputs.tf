# Values printed after terraform apply. Mrunal's worker and test commands use these.

output "uploads_bucket" {
  value = data.aws_s3_bucket.uploads.bucket
}

output "reports_bucket" {
  value = data.aws_s3_bucket.reports.bucket
}

output "scan_queue_url" {
  value = aws_sqs_queue.scan_jobs.id
}

output "dlq_url" {
  value = aws_sqs_queue.scan_jobs_dlq.id
}

output "jobs_table" {
  value = aws_dynamodb_table.scan_jobs.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.scanner.repository_url
}

output "ecs_cluster" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service" {
  value = aws_ecs_service.worker.name
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}
