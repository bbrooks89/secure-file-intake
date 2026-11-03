# Alerting: SNS topic, three alarms, and a CloudWatch dashboard.

locals {
  alarm_defaults = {
    period              = 300
    evaluation_periods  = 1
    threshold           = 1
    comparison_operator = "GreaterThanOrEqualToThreshold"
    treat_missing_data  = "notBreaching"
  }
}

resource "aws_sns_topic" "alerts" {
  # Not encrypted with the AWS-managed aws/sns key on purpose: CloudWatch alarms
  # can't publish to a topic using that key. Use a customer-managed KMS key
  # (with a policy allowing cloudwatch.amazonaws.com) if encryption is required.
  name = "${var.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "validator_errors" {
  alarm_name          = "${var.name_prefix}-validator-errors"
  alarm_description   = "Validator Lambda threw an error (file may be stuck in inbound/)."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.function_name }
  statistic           = "Sum"
  period              = local.alarm_defaults.period
  evaluation_periods  = local.alarm_defaults.evaluation_periods
  threshold           = local.alarm_defaults.threshold
  comparison_operator = local.alarm_defaults.comparison_operator
  treat_missing_data  = local.alarm_defaults.treat_missing_data
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "files_rejected" {
  alarm_name          = "${var.name_prefix}-files-rejected"
  alarm_description   = "A partner file failed validation and was quarantined."
  namespace           = "SecureFileIntake"
  metric_name         = "FilesRejected"
  statistic           = "Sum"
  period              = local.alarm_defaults.period
  evaluation_periods  = local.alarm_defaults.evaluation_periods
  threshold           = local.alarm_defaults.threshold
  comparison_operator = local.alarm_defaults.comparison_operator
  treat_missing_data  = local.alarm_defaults.treat_missing_data
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "dead_letters" {
  alarm_name          = "${var.name_prefix}-dead-letters"
  alarm_description   = "Events exhausted retries and landed in the dead-letter queue."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = var.dlq_name }
  statistic           = "Maximum"
  period              = local.alarm_defaults.period
  evaluation_periods  = local.alarm_defaults.evaluation_periods
  threshold           = local.alarm_defaults.threshold
  comparison_operator = local.alarm_defaults.comparison_operator
  treat_missing_data  = local.alarm_defaults.treat_missing_data
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Files accepted vs rejected"
          region = var.region
          stat   = "Sum"
          period = 300
          view   = "timeSeries"
          metrics = [
            ["SecureFileIntake", "FilesAccepted"],
            ["SecureFileIntake", "FilesRejected"],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Validator errors and duration"
          region = var.region
          period = 300
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", var.function_name, { stat = "Sum" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.function_name, { stat = "Average", yAxis = "right" }],
          ]
        }
      },
      {
        type   = "alarm"
        x      = 0
        y      = 6
        width  = 24
        height = 3
        properties = {
          title = "Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.validator_errors.arn,
            aws_cloudwatch_metric_alarm.files_rejected.arn,
            aws_cloudwatch_metric_alarm.dead_letters.arn,
          ]
        }
      },
    ]
  })
}
