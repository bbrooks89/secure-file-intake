# Secure File Intake, Terraform edition.
# Same design as the CDK stack, composed from three reusable modules:
#   secure_bucket   -> encrypted, private, TLS-only S3 with lifecycle retention
#   validator       -> TypeScript Lambda + least-privilege IAM + DLQ + retries
#   alerting        -> SNS topic, CloudWatch alarms, dashboard

module "storage" {
  source = "./modules/secure_bucket"

  name_prefix    = var.name_prefix
  retention_days = var.retention_days
  force_destroy  = var.allow_destroy
}

data "archive_file" "validator" {
  type        = "zip"
  source_file = "${path.module}/${var.lambda_bundle_dir}/index.js"
  output_path = "${path.module}/.dist/validator.zip"
}

module "validator" {
  source = "./modules/validator_lambda"

  name_prefix        = var.name_prefix
  bucket_arn         = module.storage.bucket_arn
  package_path       = data.archive_file.validator.output_path
  package_hash       = data.archive_file.validator.output_base64sha256
  inbound_prefix     = "inbound/"
  output_prefixes    = ["processed/", "quarantine/", "acks/"]
  max_retries        = 2
  log_retention_days = 14
}

# Wire S3 -> Lambda. Lives at the root because it joins two modules.
resource "aws_s3_bucket_notification" "inbound" {
  bucket = module.storage.bucket_name

  lambda_function {
    lambda_function_arn = module.validator.function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "inbound/"
  }

  depends_on = [module.validator]
}

module "alerting" {
  source = "./modules/alerting"

  name_prefix   = var.name_prefix
  alert_email   = var.alert_email
  function_name = module.validator.function_name
  dlq_name      = module.validator.dlq_name
  region        = var.region
}
