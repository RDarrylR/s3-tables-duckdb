-- =============================================================================
-- 01_setup.sql - one-time DuckDB session setup for the lakehouse
-- =============================================================================
-- Run this from `make query`, which generates duckdb/.attach.sql from the
-- current terraform outputs and reads it back into your session.

-- Iceberg + AWS extensions. The stable Iceberg extension carries full
-- read/write support as of DuckDB 1.5.2, including REST catalog INSERT,
-- UPDATE, DELETE, and time travel. S3 Tables support is still labeled
-- experimental in DuckDB's docs even on the stable channel; if you hit
-- a feature gap, swap in `INSTALL iceberg FROM core_nightly` to test.
INSTALL aws;
INSTALL httpfs;
INSTALL iceberg;

LOAD aws;
LOAD httpfs;
LOAD iceberg;

-- Pull the SECRET and ATTACH statements out of duckdb/.attach.sql, which
-- `make query` regenerates from terraform outputs. The generated file pins
-- the AWS profile explicitly (DuckDB's credential_chain provider doesn't
-- honor AWS_PROFILE on its own; you have to pass PROFILE on the secret).
.read duckdb/.attach.sql

USE lake.airquality;

-- Confirm we're connected and can see both tables.
SHOW ALL TABLES;
