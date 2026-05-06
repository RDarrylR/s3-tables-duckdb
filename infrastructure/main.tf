provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = var.tags
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  name_prefix = "${var.project}-${random_id.suffix.hex}"

  # Public OpenAQ archive bucket. Read-only, no-sign-request, but we still grant
  # the ingester explicit GetObject so least-privilege survives a future change
  # of source.
  openaq_bucket_arn = "arn:${local.partition}:s3:::openaq-data-archive"
}
