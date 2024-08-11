terraform {
  backend "s3" {
    bucket = "diraht-sadcloud-terraform-state"
    key    = "diraht-sadcloud.tfstate"
    region = "us-east-1"
  }
}
