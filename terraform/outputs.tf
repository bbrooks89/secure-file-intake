output "bucket_name" {
  description = "Upload test files to inbound/<partner>/ in this bucket."
  value       = module.storage.bucket_name
}

output "function_name" {
  value = module.validator.function_name
}

output "alert_topic_arn" {
  value = module.alerting.topic_arn
}

output "dashboard_name" {
  value = module.alerting.dashboard_name
}
