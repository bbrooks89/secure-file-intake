# Validator Lambda with least-privilege IAM, a dead-letter queue, and retries.

locals {
  function_name = "${var.name_prefix}-validator"

  # Read and delete only what arrives in the drop zone...
  inbound_objects = ["${var.bucket_arn}/${var.inbound_prefix}*"]
  # ...and write only to the output prefixes.
  output_objects = [for p in var.output_prefixes : "${var.bucket_arn}/${p}*"]

  role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadInbound"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = local.inbound_objects
      },
      {
        Sid      = "DeleteInbound"
        Effect   = "Allow"
        Action   = ["s3:DeleteObject"]
        Resource = local.inbound_objects
      },
      {
        Sid      = "WriteOutputs"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = local.output_objects
      },
      {
        Sid      = "SendToDeadLetterQueue"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.dlq.arn]
      },
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.this.arn}:*"]
      },
    ]
  }
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-validator-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue_policy" "dlq_tls_only" {
  queue_url = aws_sqs_queue.dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "sqs:*"
      Resource  = aws_sqs_queue.dlq.arn
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "this" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "this" {
  name   = "least-privilege"
  role   = aws_iam_role.this.id
  policy = jsonencode(local.role_policy)
}

resource "aws_lambda_function" "this" {
  function_name    = local.function_name
  role             = aws_iam_role.this.arn
  filename         = var.package_path
  source_code_hash = var.package_hash
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  architectures    = ["arm64"]
  memory_size      = 256
  timeout          = 60

  depends_on = [aws_cloudwatch_log_group.this, aws_iam_role_policy.this]
}

resource "aws_lambda_function_event_invoke_config" "this" {
  function_name          = aws_lambda_function.this.function_name
  maximum_retry_attempts = var.max_retries

  destination_config {
    on_failure {
      destination = aws_sqs_queue.dlq.arn
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.bucket_arn
}
