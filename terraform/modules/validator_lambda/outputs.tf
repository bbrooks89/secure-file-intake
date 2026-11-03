output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "function_arn" {
  value = aws_lambda_function.this.arn
}

output "dlq_name" {
  value = aws_sqs_queue.dlq.name
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "inbound_object_scope" {
  description = "S3 object ARNs the function may read and delete. Exposed for review and tests."
  value       = local.inbound_objects
}

output "output_object_scope" {
  description = "S3 object ARNs the function may write. Exposed for review and tests."
  value       = local.output_objects
}
