terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Local state by default so the lab works out of the box.
  # For a team setup, copy backend.tf.example to backend.tf and fill it in.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "secure-file-intake"
      owner      = "brad-brooks"
      managed_by = "terraform"
    }
  }
}
