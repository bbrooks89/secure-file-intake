variable "name_prefix" {
  type = string
}

variable "bucket_arn" {
  description = "ARN of the intake bucket."
  type        = string
}

variable "package_path" {
  description = "Path to the zipped Lambda bundle."
  type        = string
}

variable "package_hash" {
  description = "Base64 SHA-256 of the bundle, so code changes trigger a redeploy."
  type        = string
}

variable "inbound_prefix" {
  description = "Key prefix the function may read and delete from."
  type        = string
  default     = "inbound/"
}

variable "output_prefixes" {
  description = "Key prefixes the function may write to."
  type        = list(string)

  validation {
    condition     = alltrue([for p in var.output_prefixes : endswith(p, "/")])
    error_message = "Each output prefix must end with a slash, e.g. \"processed/\"."
  }
}

variable "max_retries" {
  description = "Async retry attempts before an event goes to the dead-letter queue (0-2)."
  type        = number
  default     = 2

  validation {
    condition     = var.max_retries >= 0 && var.max_retries <= 2
    error_message = "Lambda allows 0 to 2 retry attempts."
  }
}

variable "log_retention_days" {
  type    = number
  default = 14
}
