provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

data "aws_route53_zone" "zone" {
  provider = aws.virginia
  zone_id  = var.zone_id
}

///
// s3 bucket
///
resource "aws_s3_bucket_policy" "domain_bucket" {
  bucket = aws_s3_bucket.domain_bucket.id
  # defined below in the cloudfront section
  policy = local.cloudfront_website_bucket_access
}

resource "aws_s3_bucket" "domain_bucket" {
  bucket = var.domain_name

  provisioner "local-exec" {
    when    = destroy
    command = "aws s3 rm s3://${self.id}/ --recursive"
  }
}

resource "aws_s3_bucket_ownership_controls" "domain_bucket" {
  bucket = aws_s3_bucket.domain_bucket.id
  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_acl" "domain_bucket" {
  bucket     = aws_s3_bucket.domain_bucket.id
  acl        = "private"
  depends_on = [aws_s3_bucket_ownership_controls.domain_bucket]
}

// ssl & route53 record stuff
resource "aws_acm_certificate" "cert" {
  provider          = aws.virginia
  validation_method = "DNS"
  domain_name       = var.domain_name
  tags = {
    Name   = "cert"
    Domain = var.domain_name
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  provider = aws.virginia
  zone_id  = data.aws_route53_zone.zone.id
  ttl      = 60

  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
}


resource "aws_acm_certificate_validation" "cert_validation" {
  provider                = aws.virginia
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  timeouts {
    create = "60m"
  }
  lifecycle {
    ignore_changes = [id]
  }
}

///
// cloudfront
///
locals {
  cloudfront_website_bucket_access = jsonencode({
    "Version" : "2008-10-17",
    "Id" : "CloudfrontAccess to Website Files",
    "Statement" : [
      {
        "Sid" : "1",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "${aws_cloudfront_origin_access_identity.origin_identity.iam_arn}"
        },
        "Action" : "s3:GetObject",
        "Resource" : "arn:aws:s3:::${aws_s3_bucket.domain_bucket.id}/*"
      }
    ]
  })
}

// origin id & cloudfront
resource "aws_cloudfront_origin_access_identity" "origin_identity" {
  comment = "identity for ${var.domain_name} access origin"
}

resource "aws_cloudfront_distribution" "distribution" {
  origin {
    domain_name = aws_s3_bucket.domain_bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.domain_bucket.id
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_identity.cloudfront_access_identity_path
    }
  }
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.domain_name} cloudfront"
  default_root_object = "index.html"
  aliases             = [var.domain_name]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.domain_bucket.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  // Here's where our certificate is loaded in!
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert_validation.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }
}


// last bit of route53 stuff
resource "aws_route53_record" "main" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.distribution.domain_name
    zone_id                = aws_cloudfront_distribution.distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.distribution.id
}
