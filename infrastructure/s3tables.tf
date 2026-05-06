# --- table bucket -------------------------------------------------------------

resource "aws_s3tables_table_bucket" "this" {
  name = "${local.name_prefix}-tb"

  encryption_configuration = {
    sse_algorithm = "AES256"
    kms_key_arn   = null
  }

  maintenance_configuration = {
    iceberg_unreferenced_file_removal = {
      status = "enabled"
      settings = {
        unreferenced_days = 3
        non_current_days  = 10
      }
    }
  }
}

# --- namespace ---------------------------------------------------------------

resource "aws_s3tables_namespace" "airquality" {
  namespace        = var.namespace_name
  table_bucket_arn = aws_s3tables_table_bucket.this.arn
}

# --- measurements table ------------------------------------------------------
# Non-partitioned by design for this demo - it keeps the write path easy
# to reason about. DuckDB 1.5.2 supports UPDATE/DELETE on partitioned
# tables, but the DuckDB-Iceberg path is moving quickly and S3 Tables
# support is still flagged experimental in DuckDB docs. For production
# you'd partition (e.g. by parameter, days(datetime)) and verify your
# specific DuckDB + extension version handles mutations on that spec.

resource "aws_s3tables_table" "measurements" {
  name             = "measurements"
  namespace        = aws_s3tables_namespace.airquality.namespace
  table_bucket_arn = aws_s3tables_table_bucket.this.arn
  format           = "ICEBERG"

  metadata {
    iceberg {
      schema {
        field {
          name     = "location_id"
          type     = "long"
          required = true
        }
        field {
          name = "sensors_id"
          type = "long"
        }
        field {
          name = "location"
          type = "string"
        }
        field {
          name     = "datetime"
          type     = "timestamptz"
          required = true
        }
        field {
          name = "lat"
          type = "double"
        }
        field {
          name = "lon"
          type = "double"
        }
        field {
          name     = "parameter"
          type     = "string"
          required = true
        }
        field {
          name = "units"
          type = "string"
        }
        field {
          name = "value"
          type = "double"
        }
        field {
          name     = "ingested_at"
          type     = "timestamptz"
          required = true
        }
      }
    }
  }

  maintenance_configuration = {
    iceberg_compaction = {
      status = "enabled"
      settings = {
        target_file_size_mb = 256
      }
    }
    iceberg_snapshot_management = {
      status = "enabled"
      settings = {
        max_snapshot_age_hours = 168 # 7 days of history available for time-travel queries
        min_snapshots_to_keep  = 5
      }
    }
  }
}

# --- locations table (small, slowly-changing) -------------------------------

resource "aws_s3tables_table" "locations" {
  name             = "locations"
  namespace        = aws_s3tables_namespace.airquality.namespace
  table_bucket_arn = aws_s3tables_table_bucket.this.arn
  format           = "ICEBERG"

  metadata {
    iceberg {
      schema {
        field {
          name     = "location_id"
          type     = "long"
          required = true
        }
        field {
          name = "location"
          type = "string"
        }
        field {
          name = "country"
          type = "string"
        }
        field {
          name = "lat"
          type = "double"
        }
        field {
          name = "lon"
          type = "double"
        }
        field {
          name = "first_seen_at"
          type = "timestamptz"
        }
        field {
          name     = "last_seen_at"
          type     = "timestamptz"
          required = true
        }
        field {
          name = "measurement_count"
          type = "long"
        }
      }
    }
  }

  maintenance_configuration = {
    iceberg_compaction = {
      status = "enabled"
      settings = {
        target_file_size_mb = 64 # tiny table - no point chasing 256MB files
      }
    }
    iceberg_snapshot_management = {
      status = "enabled"
      settings = {
        max_snapshot_age_hours = 168
        min_snapshots_to_keep  = 5
      }
    }
  }
}
