
terraform {
    backend "s3" {
        encrypt = "true"
        bucket  = "tf-state-xxxx"
        key     = "aws-backup.tfstate"
        region  = "eu-west-1"
    }
    required_providers {
      aws = {
        source  = "hashicorp/aws"
        version = "> 4.0.0"
      }
    }
}

provider "aws" {
    region = "eu-west-1"
    alias  = "sandbox"
    profile = "sandbox"
}

# root account
provider "aws" {
    region = "eu-west-1"
    alias  = "central"
    profile = "central"
}

provider "aws" {
    region = "eu-west-1"
    alias  = "backup"
    profile = "backup"
}

provider "aws" {
    region = "eu-west-2"
    alias  = "backup_dr"
    profile = "backup"
}