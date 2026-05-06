variable "aws_region" {
  description = "AWS region. S3 Tables is GA in us-east-1, us-east-2, us-west-2 (and others - check the docs)."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Named AWS profile used by the provider."
  type        = string
  default     = "default"
}

variable "project" {
  description = "Project name. Used as a prefix on most resource names."
  type        = string
  default     = "openaq-lakehouse"
}

variable "namespace_name" {
  description = "S3 Tables namespace inside the table bucket."
  type        = string
  default     = "airquality"
}

variable "lambda_memory_mb" {
  description = "Lambda memory size. PyIceberg and pyarrow benefit from headroom; 1769 MB is the 1-vCPU break point."
  type        = number
  default     = 1769
}

variable "lambda_timeout_s" {
  description = "Lambda timeout. Backfills can take a while; 15 minutes is the hard ceiling."
  type        = number
  default     = 900
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the ingester."
  type        = number
  default     = 14
}

variable "schedule_state" {
  description = "DISABLED keeps you off the recurring-cost meter until you explicitly turn it on. Flip to ENABLED for real ingestion."
  type        = string
  default     = "DISABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.schedule_state)
    error_message = "schedule_state must be ENABLED or DISABLED."
  }
}

variable "schedule_expression" {
  description = "EventBridge Scheduler expression. Default runs once per day at 06:00 UTC."
  type        = string
  default     = "cron(0 6 * * ? *)"
}

variable "schedule_payload" {
  description = "JSON payload sent to the Lambda by the daily schedule."
  type        = string
  default     = "{\"stations\": 500, \"days\": 1}"
}

variable "reader_principal_arns" {
  description = "IAM principal ARNs allowed to assume the read-only DuckDB role. Required - the module fails closed if no principals are supplied. terraform.tfvars.example provides an account-root fallback for single-account lab use."
  type        = list(string)

  validation {
    condition     = length(var.reader_principal_arns) > 0
    error_message = "reader_principal_arns must contain at least one IAM principal ARN. For lab use, copy infrastructure/terraform.tfvars.example to terraform.tfvars; for production, list specific user or role ARNs."
  }
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default = {
    project   = "openaq-lakehouse"
    managedBy = "terraform"
  }
}
