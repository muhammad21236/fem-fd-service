terraform {
  backend "s3" {
    bucket = "fem-fd-service-m0d"
    key    = "terraform.tfstate"
    region = "ap-south-1"
  }
}