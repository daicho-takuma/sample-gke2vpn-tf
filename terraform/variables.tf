variable "project_id" {
  description = "GCP Project ID"
  type        = string
  # No default value. Specify via terraform.tfvars or environment variable TF_VAR_project_id
}

variable "environment" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
  default     = "test"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "gke2vpn"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "asia-northeast1"
}
