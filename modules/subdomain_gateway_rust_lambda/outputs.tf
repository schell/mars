output "api_url" {
  value = aws_api_gateway_domain_name.subdomain.cloudfront_domain_name
}

output "invoke_url" {
  value = aws_api_gateway_deployment.mars_subdomain_gateway_rust_lambda.invoke_url
}
