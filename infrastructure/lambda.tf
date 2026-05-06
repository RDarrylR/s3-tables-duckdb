# =============================================================================
# Ingester Lambda - python 3.14 on Graviton (arm64)
# =============================================================================
# Two layers:
#   1. Powertools-and-friends layer with all runtime deps (built by `make layer`)
#   2. (none) - Powertools is bundled into layer 1 instead of using the
#      AWS-published layer, so builds are deterministic without depending on
#      a particular published layer version.

resource "aws_lambda_layer_version" "deps" {
  layer_name               = "${local.name_prefix}-ingester-deps"
  s3_bucket                = aws_s3_object.ingester_layer.bucket
  s3_key                   = aws_s3_object.ingester_layer.key
  source_code_hash         = aws_s3_object.ingester_layer.source_hash
  compatible_runtimes      = ["python3.13"]
  compatible_architectures = ["arm64"]
  description              = "PyIceberg, pyarrow, AWS Lambda Powertools and supporting libs (arm64)."
}

resource "aws_cloudwatch_log_group" "ingester" {
  name              = "/aws/lambda/${local.name_prefix}-ingester"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "ingester" {
  function_name = "${local.name_prefix}-ingester"
  role          = aws_iam_role.ingester.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.13"
  architectures = ["arm64"]
  memory_size   = var.lambda_memory_mb
  timeout       = var.lambda_timeout_s

  filename         = "${path.module}/../ingester/dist/ingester.zip"
  source_code_hash = filebase64sha256("${path.module}/../ingester/dist/ingester.zip")

  layers = [aws_lambda_layer_version.deps.arn]

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
    log_group             = aws_cloudwatch_log_group.ingester.name
  }

  environment {
    variables = {
      POWERTOOLS_SERVICE_NAME      = "openaq-ingester"
      POWERTOOLS_METRICS_NAMESPACE = "OpenAQLakehouse"
      POWERTOOLS_LOG_LEVEL         = "INFO"

      OPENAQ_SOURCE_BUCKET = "openaq-data-archive"
      TABLE_BUCKET_ARN     = aws_s3tables_table_bucket.this.arn
      NAMESPACE            = aws_s3tables_namespace.airquality.namespace
      MEASUREMENTS_TABLE   = aws_s3tables_table.measurements.name
      LOCATIONS_TABLE      = aws_s3tables_table.locations.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ingester,
    aws_cloudwatch_log_group.ingester,
  ]
}
