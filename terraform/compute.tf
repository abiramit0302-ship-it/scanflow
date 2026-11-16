# Compute for ScanFlow: the ECS Fargate worker that runs the SAST scanner container.
# Learner Lab doesn't allow creating IAM roles, so we use the existing LabRole.

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

resource "aws_ecr_repository" "scanner" {
  name                 = "${var.project_name}-scanner"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${var.project_name}-worker"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.project_name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"  # 0.5 vCPU
  memory                   = "1024" # 1 GB
  execution_role_arn       = data.aws_iam_role.lab_role.arn
  task_role_arn            = data.aws_iam_role.lab_role.arn

  # CHANGED: run on ARM, so images built on our Apple-chip Mac work as they are
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name      = "worker"
    image     = "${aws_ecr_repository.scanner.repository_url}:latest"
    essential = true

    environment = [
      { name = "QUEUE_URL", value = aws_sqs_queue.scan_jobs.id },
      { name = "UPLOADS_BUCKET", value = data.aws_s3_bucket.uploads.bucket },
      { name = "REPORTS_BUCKET", value = data.aws_s3_bucket.reports.bucket },
      { name = "JOBS_TABLE", value = aws_dynamodb_table.scan_jobs.name }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.worker.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "worker"
      }
    }
  }])
}

resource "aws_ecs_service" "worker" {
  name            = "${var.project_name}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_desired_count # CHANGED: starts at 0, no image yet
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.worker.id]
    assign_public_ip = true
  }
}
