mock_provider "aws" {}

variables {
  name_prefix   = "test"
  function_name = "test-validator"
  dlq_name      = "test-validator-dlq"
  region        = "us-east-2"
}

run "email_subscription_when_address_given" {
  command = plan

  module {
    source = "./modules/alerting"
  }

  variables {
    alert_email = "alerts@example.com"
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1
    error_message = "An email address should create one subscription."
  }

  assert {
    condition     = length(output.alarm_names) == 3
    error_message = "Expected three alarms."
  }
}

run "no_subscription_without_address" {
  command = plan

  module {
    source = "./modules/alerting"
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "No email address should mean no subscription."
  }
}
