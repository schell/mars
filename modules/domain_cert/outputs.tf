output "certificate_arn" {
  description = "The validated certificate ARN for your domain"
  value = aws_acm_certificate_validation.cert_validation.certificate_arn
}
