output "cloudfront_url" {
  value = aws_api_gateway_domain_name.subdomain.cloudfront_domain_name
}

output "lambda_invoke_url" {
  value = aws_api_gateway_deployment.mars_subdomain_gateway_rust_lambda.invoke_url
}

output "api_url" {
  value = "https://${local.sub_domain_name}"
}
