mock_provider "aws" {}

variables {
  name_prefix     = "test"
  bucket_arn      = "arn:aws:s3:::test-bucket"
  package_path    = "validator.zip"
  package_hash    = "dGVzdA=="
  output_prefixes = ["processed/", "quarantine/", "acks/"]
}

run "function_settings" {
  command = plan

  module {
    source = "./modules/validator_lambda"
  }

  assert {
    condition     = aws_lambda_function.this.runtime == "nodejs22.x"
    error_message = "Validator must run on Node.js 22."
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.this.maximum_retry_attempts == 2
    error_message = "Failed events must be retried twice before the dead-letter queue."
  }

  assert {
    condition     = aws_sqs_queue.dlq.sqs_managed_sse_enabled == true
    error_message = "The dead-letter queue must be encrypted."
  }
}

run "least_privilege_scope" {
  command = plan

  module {
    source = "./modules/validator_lambda"
  }

  assert {
    condition     = output.inbound_object_scope == ["arn:aws:s3:::test-bucket/inbound/*"]
    error_message = "Read and delete must be limited to inbound/."
  }

  assert {
    condition = output.output_object_scope == [
      "arn:aws:s3:::test-bucket/processed/*",
      "arn:aws:s3:::test-bucket/quarantine/*",
      "arn:aws:s3:::test-bucket/acks/*",
    ]
    error_message = "Writes must be limited to the three output prefixes."
  }
}

run "rejects_too_many_retries" {
  command = plan

  module {
    source = "./modules/validator_lambda"
  }

  variables {
    max_retries = 3
  }

  expect_failures = [var.max_retries]
}

run "rejects_prefix_without_slash" {
  command = plan

  module {
    source = "./modules/validator_lambda"
  }

  variables {
    output_prefixes = ["processed"]
  }

  expect_failures = [var.output_prefixes]
}
