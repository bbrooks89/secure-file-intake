variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-2"
}

variable "name_prefix" {
  description = "Prefix for every resource name. Keeps this stack separate from the CDK version."
  type        = string
  default     = "sfi-tf"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-20 characters: lowercase letters, digits, or hyphens."
  }
}

variable "alert_email" {
  description = "Email address for alarm notifications. Leave empty to skip the subscription."
  type        = string
  default     = ""
}

variable "lambda_bundle_dir" {
  description = "Folder containing the bundled Lambda (index.js). Built by `npm run build:lambda`."
  type        = string
  default     = "build"
}

variable "retention_days" {
  description = "How long to keep files under each prefix before they expire."
  type        = map(number)
  default = {
    "processed/" = 30
    "acks/"      = 30
  }
}

variable "allow_destroy" {
  description = "Let `terraform destroy` delete the bucket even when it still holds files. Lab setting."
  type        = bool
  default     = true
}
