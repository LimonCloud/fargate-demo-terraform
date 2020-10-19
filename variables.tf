variable "ssl_certificate" {
  default = "cert-manager-ssl-arn"
}

variable "vpc_id" {
  default = "existing-vpc-id"
}

variable "subnet_a_id" {
  default = "existing-public-a-subnet-id"
}

variable "subnet_b_id" {
  default = "existing-public-b-subnet-id"
}

variable "subnet_c_id" {
  default = "existing-public-c-subnet-id"
}