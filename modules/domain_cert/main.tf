resource "aws_acm_certificate" "cert" {
  provider = aws.virginia
  validation_method = "DNS"
  domain_name = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  tags = {
    Name = "mars_domain_cert_for_${var.domain_name}"
    Domain = var.domain_name
  }
  lifecycle {
    create_before_destroy = true
  }
}
