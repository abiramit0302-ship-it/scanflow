terraform {
  backend "s3" {
    bucket       = "scanflow-tfstate-283293091645"
    key          = "scanflow/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
