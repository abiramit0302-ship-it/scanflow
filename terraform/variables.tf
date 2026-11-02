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
