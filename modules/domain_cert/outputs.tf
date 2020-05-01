output "aws_acm_certificate" {
  description = "The validated aws_acm_certificate for your domain"
  value = aws_acm_certificate.cert
}
