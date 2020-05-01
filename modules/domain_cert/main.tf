provider "aws" {
  alias = "virginia"
  region = "us-east-1"
}


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


data "aws_route53_zone" "zone" {
  provider = aws.virginia
  zone_id = var.zone_id
}


resource "aws_route53_record" "cert_validation" {
  provider = aws.virginia
  zone_id = data.aws_route53_zone.zone.id

  name = aws_acm_certificate.cert.domain_validation_options.0.resource_record_name
  type = aws_acm_certificate.cert.domain_validation_options.0.resource_record_type
  records = [aws_acm_certificate.cert.domain_validation_options.0.resource_record_value]
  ttl = 60
}


resource "aws_acm_certificate_validation" "cert_validation" {
  provider                = aws.virginia
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = aws_route53_record.cert_validation.*.fqdn
  timeouts {
    create = "60m"
  }
  lifecycle {
    ignore_changes = [id]
  }
}
