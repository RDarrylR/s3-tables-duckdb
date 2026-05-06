# =============================================================================
# Ingester Lambda execution role
# =============================================================================

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ingester" {
  name               = "${local.name_prefix}-ingester"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  description        = "Execution role for the OpenAQ ingester Lambda."
}

data "aws_iam_policy_document" "ingester" {
  statement {
    sid    = "WriteOwnLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.ingester.arn}:*"]
  }

  statement {
    sid    = "XRayWrite"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadOpenAQArchive"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [local.openaq_bucket_arn, "${local.openaq_bucket_arn}/*"]
  }

  statement {
    sid    = "TableBucketRead"
    effect = "Allow"
    actions = [
      "s3tables:GetTableBucket",
      "s3tables:GetNamespace",
      "s3tables:ListNamespaces",
      "s3tables:ListTables",
    ]
    resources = [aws_s3tables_table_bucket.this.arn]
  }

  # Tighter than the bucket-wide /table/* wildcard: lists the two specific
  # tables this function actually writes to. A future table added to the
  # bucket by mistake doesn't inherit write access.
  statement {
    sid    = "TableReadWrite"
    effect = "Allow"
    actions = [
      "s3tables:GetTable",
      "s3tables:GetTableMetadataLocation",
      "s3tables:UpdateTableMetadataLocation",
      "s3tables:GetTableData",
      "s3tables:PutTableData",
    ]
    resources = [
      aws_s3tables_table.measurements.arn,
      aws_s3tables_table.locations.arn,
    ]
  }
}

resource "aws_iam_policy" "ingester" {
  name        = "${local.name_prefix}-ingester"
  description = "Least-privilege policy for the OpenAQ ingester Lambda."
  policy      = data.aws_iam_policy_document.ingester.json
}

resource "aws_iam_role_policy_attachment" "ingester" {
  role       = aws_iam_role.ingester.name
  policy_arn = aws_iam_policy.ingester.arn
}

# =============================================================================
# Read-only role for the laptop / DuckDB session
# =============================================================================
# Trust policy is built from var.reader_principal_arns. The variable is
# required (validation enforces non-empty), so the module fails closed if
# nobody set it. terraform.tfvars.example provides a single-account
# convenience default for lab use.

data "aws_iam_policy_document" "reader_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = var.reader_principal_arns
    }
    # When account-root is in the principal list (lab default), require a
    # real human/role rather than (e.g.) the root account.
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalType"
      values   = ["User", "AssumedRole"]
    }
  }
}

resource "aws_iam_role" "reader" {
  name               = "${local.name_prefix}-reader"
  assume_role_policy = data.aws_iam_policy_document.reader_assume.json
  description        = "Read-only role for DuckDB sessions querying the lakehouse."

  max_session_duration = 3600
}

data "aws_iam_policy_document" "reader" {
  statement {
    sid    = "TableBucketRead"
    effect = "Allow"
    actions = [
      "s3tables:GetTableBucket",
      "s3tables:GetNamespace",
      "s3tables:ListNamespaces",
      "s3tables:ListTables",
    ]
    resources = [aws_s3tables_table_bucket.this.arn]
  }

  statement {
    sid    = "TableRead"
    effect = "Allow"
    actions = [
      "s3tables:GetTable",
      "s3tables:GetTableMetadataLocation",
      "s3tables:GetTableData",
    ]
    resources = [
      aws_s3tables_table.measurements.arn,
      aws_s3tables_table.locations.arn,
    ]
  }
}

resource "aws_iam_policy" "reader" {
  name        = "${local.name_prefix}-reader"
  description = "Read-only access to the lakehouse for DuckDB sessions."
  policy      = data.aws_iam_policy_document.reader.json
}

resource "aws_iam_role_policy_attachment" "reader" {
  role       = aws_iam_role.reader.name
  policy_arn = aws_iam_policy.reader.arn
}

# =============================================================================
# EventBridge Scheduler execution role
# =============================================================================

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.name_prefix}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
  description        = "EventBridge Scheduler role allowed to invoke the ingester Lambda."
}

data "aws_iam_policy_document" "scheduler_invoke" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.ingester.arn]
  }
}

resource "aws_iam_policy" "scheduler_invoke" {
  name   = "${local.name_prefix}-scheduler-invoke"
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}

resource "aws_iam_role_policy_attachment" "scheduler" {
  role       = aws_iam_role.scheduler.name
  policy_arn = aws_iam_policy.scheduler_invoke.arn
}
