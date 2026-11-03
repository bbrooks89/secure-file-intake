# Plan-only tests with a mocked AWS provider: no credentials, no cost.
# Run from the terraform/ folder with: terraform test

mock_provider "aws" {}

run "bucket_is_private_encrypted_and_versioned" {
  command = plan

  module {
    source = "./modules/secure_bucket"
  }

  variables {
    name_prefix    = "test"
    retention_days = { "processed/" = 30, "acks/" = 30 }
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four public access blocks must be on."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled."
  }

  assert {
    condition = alltrue(flatten([
      for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : [
        for d in r.apply_server_side_encryption_by_default : d.sse_algorithm == "AES256"
      ]
    ]))
    error_message = "Default encryption must be AES256."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 3
    error_message = "Expected one expiration rule per prefix plus the old-versions rule."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must default to false outside the lab."
  }
}

run "rejects_zero_day_retention" {
  command = plan

  module {
    source = "./modules/secure_bucket"
  }

  variables {
    name_prefix    = "test"
    retention_days = { "processed/" = 0 }
  }

  expect_failures = [var.retention_days]
}
