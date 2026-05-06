# EventBridge Scheduler runs the ingester on a cron. Disabled by default so a
# fresh apply doesn't put recurring charges on anyone's bill - flip
# schedule_state to ENABLED once you've verified the manual run works.

resource "aws_scheduler_schedule" "ingester_daily" {
  name        = "${local.name_prefix}-ingester-daily"
  description = "Daily incremental ingest of OpenAQ data into the lakehouse."
  state       = var.schedule_state

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.ingester.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = var.schedule_payload

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }
  }
}
