provider "aws" {
  region = "us-west-2"
}


provider "aws" {
  alias = "virginia"
  region = "us-east-1"
}


terraform {
  backend "s3" {
    bucket = "ad-to-bag-terraform"
    key    = "ad-to-bag"
    region = "us-west-2"
  }
}


# ROLES & POLICIES

resource "aws_iam_role" "cache_to_bag" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}


resource "aws_iam_policy" "cache_to_bag" {
  name        = "iam_policy_for_cache_to_bag"
  path        = "/"
  description = "IAM policy for CacheToBag's lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF

}


resource "aws_iam_role_policy_attachment" "cache_to_bag" {
  role       = aws_iam_role.cache_to_bag.name
  policy_arn = aws_iam_policy.cache_to_bag.arn
}


# The lambda itself
resource "aws_lambda_function" "cache_to_bag" {
  filename      = "cache_to_bag.zip"
  handler       = "cache-to-bag"
  function_name = "cache-to-bag"
  runtime       = "provided"
  timeout       = 30
  memory_size   = 1024
  role          = aws_iam_role.cache_to_bag.arn
  publish       = true

  source_code_hash = filebase64sha256("cache_to_bag.zip")

  environment {
    variables = {
      RUST_BACKTRACE = "1"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.cache_to_bag
  ]
}


# GATEWAY API STUFF
resource "aws_api_gateway_rest_api" "cache_to_bag" {
  name        = "cache_to_bag"
  description = "CacheToBag's API Gateway"
}


resource "aws_api_gateway_resource" "cache_to_bag" {
  rest_api_id = aws_api_gateway_rest_api.cache_to_bag.id
  parent_id   = aws_api_gateway_rest_api.cache_to_bag.root_resource_id
  path_part   = "{proxy+}"
}


resource "aws_api_gateway_method" "cache_to_bag_root" {
  rest_api_id   = aws_api_gateway_rest_api.cache_to_bag.id
  resource_id   = aws_api_gateway_rest_api.cache_to_bag.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}


resource "aws_api_gateway_method" "cache_to_bag_path" {
  rest_api_id   = aws_api_gateway_rest_api.cache_to_bag.id
  resource_id   = aws_api_gateway_resource.cache_to_bag.id
  http_method   = "ANY"
  authorization = "NONE"
}


resource "aws_api_gateway_integration" "cache_to_bag_path" {
  rest_api_id = aws_api_gateway_rest_api.cache_to_bag.id
  resource_id = aws_api_gateway_method.cache_to_bag_path.resource_id
  http_method = aws_api_gateway_method.cache_to_bag_path.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.cache_to_bag.invoke_arn
}


resource "aws_api_gateway_integration" "cache_to_bag_root" {
  rest_api_id = aws_api_gateway_rest_api.cache_to_bag.id
  resource_id = aws_api_gateway_method.cache_to_bag_root.resource_id
  http_method = aws_api_gateway_method.cache_to_bag_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.cache_to_bag.invoke_arn
}


resource "aws_api_gateway_deployment" "cache_to_bag" {
  depends_on = [
    aws_api_gateway_integration.cache_to_bag_root,
    aws_api_gateway_integration.cache_to_bag_path
  ]

  rest_api_id = aws_api_gateway_rest_api.cache_to_bag.id
  stage_name  = "test_cache_to_bag"
}


resource "aws_lambda_permission" "cache_to_bag" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cache_to_bag.function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.cache_to_bag.execution_arn}/*/*"
}


output "invoke_url" {
  value = aws_api_gateway_deployment.cache_to_bag.invoke_url
}


# ssl & route53 record stuff
resource "aws_acm_certificate" "cert" {
  provider = aws.virginia
  validation_method = "DNS"
  domain_name = "weerred.com"
  subject_alternative_names = ["*.weerred.com"]
  tags = {
    Name = "cache_to_bag_api_cert"
    Domain = "weerred.com"
  }
  lifecycle {
    create_before_destroy = true
  }
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


# domains
data "aws_route53_zone" "zone" {
  provider = aws.virginia
  zone_id = "Z22V5I5R2Z8871"
}


resource "aws_api_gateway_domain_name" "crisp" {
  certificate_arn = aws_acm_certificate_validation.cert_validation.certificate_arn
  domain_name     = replace("crisp.${data.aws_route53_zone.zone.name}", "/[.]$/", "")
}


resource "aws_api_gateway_base_path_mapping" "base_path_mapping" {
  api_id      = aws_api_gateway_rest_api.cache_to_bag.id
  domain_name = aws_api_gateway_domain_name.crisp.domain_name
  stage_name  = "test_cache_to_bag"
}


resource "aws_route53_record" "alias_deployment" {
  name    = "crisp.${data.aws_route53_zone.zone.name}"
  zone_id = data.aws_route53_zone.zone.zone_id
  type    = "A"

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.crisp.cloudfront_domain_name
    zone_id                = aws_api_gateway_domain_name.crisp.cloudfront_zone_id
  }
}


output "api_url" {
  value = aws_api_gateway_domain_name.crisp.cloudfront_domain_name
}
