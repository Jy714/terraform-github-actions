terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket = "terraform-vpc-github-actions"
    key    = "dev/terraform.tfstate"
    region = "ap-southeast-2"
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "ap-southeast-2"
}