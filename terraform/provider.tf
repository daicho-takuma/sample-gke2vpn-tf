provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Environment = local.env
      Project     = local.project
    }
  }
}

provider "google" {
  project = local.project_id
  region  = var.gcp_region
}
