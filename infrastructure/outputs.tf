output "table_bucket_arn" {
  description = "ARN of the S3 Tables bucket. Used by the DuckDB ATTACH statement."
  value       = aws_s3tables_table_bucket.this.arn
}

output "table_bucket_name" {
  description = "Name of the S3 Tables bucket."
  value       = aws_s3tables_table_bucket.this.name
}

output "namespace" {
  description = "S3 Tables namespace holding the measurements and locations tables."
  value       = aws_s3tables_namespace.airquality.namespace
}

output "measurements_table" {
  description = "Three-part table identifier: catalog.namespace.table format hint."
  value       = "${aws_s3tables_namespace.airquality.namespace}.${aws_s3tables_table.measurements.name}"
}

output "locations_table" {
  description = "Three-part table identifier hint for the locations table."
  value       = "${aws_s3tables_namespace.airquality.namespace}.${aws_s3tables_table.locations.name}"
}

output "ingester_function_name" {
  description = "Lambda function name. `make ingest` resolves this and invokes the function."
  value       = aws_lambda_function.ingester.function_name
}

output "ingester_function_arn" {
  description = "Lambda function ARN."
  value       = aws_lambda_function.ingester.arn
}

output "ingester_log_group" {
  description = "CloudWatch log group for the ingester. `make logs` tails it."
  value       = aws_cloudwatch_log_group.ingester.name
}

output "reader_role_arn" {
  description = "ARN of the read-only role for DuckDB sessions. Assume it from your laptop profile."
  value       = aws_iam_role.reader.arn
}

output "scheduler_state" {
  description = "Whether the daily ingest schedule is currently armed."
  value       = aws_scheduler_schedule.ingester_daily.state
}

output "aws_region" {
  description = "Region everything is deployed in."
  value       = local.region
}
