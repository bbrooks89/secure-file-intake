output "topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.this.dashboard_name
}

output "alarm_names" {
  value = [
    aws_cloudwatch_metric_alarm.validator_errors.alarm_name,
    aws_cloudwatch_metric_alarm.files_rejected.alarm_name,
    aws_cloudwatch_metric_alarm.dead_letters.alarm_name,
  ]
}
