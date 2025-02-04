

module "vpc" {
  source = "./modules/vpc"
  vpc_cidr = var.vpc_cidr
}

module "s3_cloudfront" {
  source = "./modules/s3_cloudfront"
}



