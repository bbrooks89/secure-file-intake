variable "name_prefix" {
  type = string
}

variable "alert_email" {
  description = "Email for alarm notifications; empty string skips the subscription."
  type        = string
  default     = ""
}

variable "function_name" {
  type = string
}

variable "dlq_name" {
  type = string
}

variable "region" {
  description = "Region shown on dashboard widgets."
  type        = string
}
