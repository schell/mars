provider "aws" {
  region = var.region
}


provider "aws" {
  alias = "virginia"
  region = "us-east-1"
}


# ROLES & POLICIES

resource "aws_iam_role" "mars_subdomain_gateway_rust_lambda" {
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


resource "aws_iam_policy" "mars_subdomain_gateway_rust_lambda" {
  name        = "iam_policy_for_${var.api_name}"
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


resource "aws_iam_role_policy_attachment" "mars_subdomain_gateway_rust_lambda" {
  role       = aws_iam_role.mars_subdomain_gateway_rust_lambda.name
  policy_arn = aws_iam_policy.mars_subdomain_gateway_rust_lambda.arn
}


# The lambda itself
resource "aws_lambda_function" "mars_subdomain_gateway_rust_lambda" {
  filename      = var.lambda_bin_zipfile
  handler       = "cache-to-bag"
  function_name = var.lambda_function_name
  runtime       = "provided"
  timeout       = 30
  memory_size   = 1024
  role          = aws_iam_role.mars_subdomain_gateway_rust_lambda.arn
  publish       = true

  source_code_hash = filebase64sha256(var.lambda_bin_zipfile)

  environment {
    variables = {
      RUST_BACKTRACE = "1"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.mars_subdomain_gateway_rust_lambda
  ]
}


# GATEWAY API STUFF
resource "aws_api_gateway_rest_api" "mars_subdomain_gateway_rust_lambda" {
  name        = var.api_name
  description = "${var.display_name}'s API Gateway"
}


resource "aws_api_gateway_resource" "mars_subdomain_gateway_rust_lambda" {
  rest_api_id = aws_api_gateway_rest_api.mars_subdomain_gateway_rust_lambda.id
  parent_id   = aws_api_gateway_rest_api.mars_subdomain_gateway_rust_lambda.root_resource_id
  path_part   = "{proxy+}"
}


resource "aws_api_gateway_method" "mars_subdomain_gateway_rust_lambda_root" {
  rest_api_id   = aws_api_gateway_rest_api.mars_subdomain_gateway_rust_lambda.id
  resource_id   = aws_api_gateway_rest_api.mars_subdomain_gateway_rust_lambda.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}


resource "aws_api_gateway_method" "mars_subdomain_gateway_rust_lambda_path" {
  rest_api_id   = aws_api_gateway_rest_api.mars_subdomain_gateway_rust_lambda.id
  resource_id   = aws_api_gateway_resource.mars_subdomain_gateway_rust_lambda.id
  http_method   = "ANY"
  authorization = "NONE"
}


resource "aws_api_gateway_integration" "mars_subdomain_gateway_rust_lambda_path" {
  rest_api_id = aws_api_gateway_rest_api.mars_subdomain_gateway_rust_lambda.id
  resource_id = aws_api_gateway_method.mars_subdomain_gateway_rust_lambda_path.resource_id
  http_method = aws_api_gateway_method.mars_subdomain_gateway_rust_lambda_path.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.mars_subdomain_gateway_rust_lambda.invoke_arn
}


resource "aws_api_gateway_integration" "mars_subdomain_gateway_rust_lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.mars_subdomain_gateway_rust_lambda.id
  resource_id = aws_api_gateway_method.mars_subdomain_gateway_rust_lambda_root.resource_id
  http_method = aws_api_gateway_method.mars_subdomain_gateway_rust_lambda_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.mars_subdomain_gateway_rust_lambda.invoke_arn
}


resource "aws_api_gateway_deployment" "mars_subdomain_gateway_rust_lambda" {
  depends_on = [
    aws_api_gateway_integration.mars_subdomain_gateway_rust_lambda_root,
    aws_api_gateway_integration.mars_subdomain_gateway_rust_lambda_path
  ]

  rest_api_id = aws_api_gateway_rest_api.mars_subdomain_gateway_rust_lambda.id
  stage_name  = "test_${var.api_name}"
}


resource "aws_lambda_permission" "mars_subdomain_gateway_rust_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mars_subdomain_gateway_rust_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.mars_subdomain_gateway_rust_lambda.execution_arn}/*/*"
}


data "aws_route53_zone" "zone" {
  provider = aws.virginia
  zone_id = var.zone_id
}


locals {
  domain_name = replace(data.aws_route53_zone.zone.name, "/[.]$/", "")
  sub_domain_name = replace("${var.subdomain}.${data.aws_route53_zone.zone.name}", "/[.]$/", "")
}

# ssl & route53 record stuff
# domains
resource "aws_api_gateway_domain_name" "subdomain" {
  certificate_arn = var.certificate_arn #aws_acm_certificate_validation.cert_validation.certificate_arn
  domain_name     = local.sub_domain_name
}


resource "aws_api_gateway_base_path_mapping" "base_path_mapping" {
  api_id      = aws_api_gateway_rest_api.mars_subdomain_gateway_rust_lambda.id
  domain_name = aws_api_gateway_domain_name.subdomain.domain_name
  stage_name  = "test_mars_subdomain_gateway_rust_lambda"
}


resource "aws_route53_record" "subdomain" {
  name    = "${var.subdomain}.${data.aws_route53_zone.zone.name}"
  zone_id = data.aws_route53_zone.zone.zone_id
  type    = "A"

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.subdomain.cloudfront_domain_name
    zone_id                = aws_api_gateway_domain_name.subdomain.cloudfront_zone_id
  }
}
