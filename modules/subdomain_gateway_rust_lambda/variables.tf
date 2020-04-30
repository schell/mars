variable "region" {
  type = string
  description = "The default AWS region"
  default = "us-west-2"
}


variable "api_name" {
  type = string
  description = "A programmy name to used to identify your api's use of various aws resources"
  default = "mars_subdomain_gateway_rust_lambda"
}


variable "display_name" {
  type = string
  description = "A human-friendly name to identify your api to yourself"
  default = "Mars Subdomain+APIGateway+Lambda+Rust"
}


variable "lambda_bin_zipfile" {
  type = string
  description = "The name of the built zip file that will be uploaded to your lambda"
}


variable "lambda_function_name" {
  type = string
  description = "The name of the lambda function"
}


variable "zone_id" {
  type = string
  description = "Id of the zone that holds the domain"
}


variable "subdomain" {
  type = string
  description = "Name of the subdomain"
}
