variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name used to label and prefix resources"
  type        = string
  default     = "scanflow"
}

variable "worker_desired_count" {
  description = "Number of worker tasks to run. Stays 0 until the scanner image is in ECR."
  type        = number
  default     = 0
}
