provider "aws" {
  region = "ap-northeast-1"
  default_tags {
    tags = {
      Environment = local.env
      Project     = local.project
    }
  }
}

provider "google" {
  project = local.project_id
  region  = "asia-northeast1"
}
