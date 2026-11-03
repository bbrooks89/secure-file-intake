variable "name_prefix" {
  description = "Prefix for the bucket name; AWS appends a unique suffix."
  type        = string
}

variable "retention_days" {
  description = "Map of key prefix => days before objects under it expire."
  type        = map(number)
  default     = {}

  validation {
    condition     = alltrue([for days in values(var.retention_days) : days >= 1])
    error_message = "Every retention period must be at least 1 day."
  }
}

variable "noncurrent_version_days" {
  description = "Days to keep overwritten or deleted object versions."
  type        = number
  default     = 7
}

variable "force_destroy" {
  description = "Allow destroying the bucket while it still contains objects."
  type        = bool
  default     = false
}
