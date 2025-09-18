terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    bucket = "madetech-bfielder-tfstate-bucket"
    key = "terraform.tfstate"
    region = "eu-west-2"
    use_lockfile = true
  }


  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.12.0"
    }
  }

}