# The service stack (PRD §5.2): container Lambda behind a Function URL, with
# DynamoDB and CloudFront in front. One module, reused by dev and prod.
# Previews were cut — this org's Resource Control Policy blocks anonymous
# Function URLs account-wide, and CloudFront-per-preview defeats the speed
# rationale previews existed for (hops.ai-demo/docs/DECISIONS.md).

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  name = "${var.name_prefix}-${var.env}"
}

# --- Lambda execution role: logs + its own table, nothing else ---
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "exec" {
  name               = "${local.name}-exec" # bootstrap deploy roles PassRole exactly this name
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy" "exec" {
  name = "logs-and-table"
  role = aws_iam_role.exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query"]
        Resource = aws_dynamodb_table.this.arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days
}

# On-demand table per env (§5.2). App is thin and doesn't read it yet — the
# stack matches the documented architecture; $0 at rest.
resource "aws_dynamodb_table" "this" {
  name         = local.name
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "pk"
  attribute {
    name = "pk"
    type = "S"
  }

  tags = {
    env     = var.env
    Project = var.name_prefix
  }
}

resource "aws_lambda_function" "this" {
  function_name = local.name
  role          = aws_iam_role.exec.arn
  package_type  = "Image"
  image_uri     = var.image_uri
  architectures = ["arm64"] # Graviton — cheaper, in budget
  memory_size   = var.memory
  timeout       = var.timeout
  publish       = true # every image change publishes a version — rollback target (§5.3)

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }

  tags = {
    env     = var.env
    Project = var.name_prefix
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# `live` alias is the stable rollback handle: deploys move it forward, the
# incident demo (session 6) flips it back — no Terraform run against old code.
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version
}

# AuthType AWS_IAM, not NONE: this AWS Organization enforces a Resource Control
# Policy that blocks anonymous Function URLs account-wide (verified — a public
# FURL returns AccessDeniedException regardless of resource policy). CloudFront
# reaches it via OAC SigV4 signing below; the FURL is never publicly callable.
resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  qualifier          = aws_lambda_alias.live.name
  authorization_type = "AWS_IAM"
}

# Only CloudFront (via OAC) may invoke the FURL, and only this distribution.
# Since Oct 2025, Function URL access requires BOTH lambda:InvokeFunctionUrl and
# lambda:InvokeFunction — the URL action alone now 403s. Two statements.
resource "aws_lambda_permission" "furl" {
  count                  = var.enable_cloudfront ? 1 : 0
  statement_id           = "AllowCloudFrontOAC"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.this.function_name
  qualifier              = aws_lambda_alias.live.name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.this[0].arn
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "furl_invoke" {
  count         = var.enable_cloudfront ? 1 : 0
  statement_id  = "AllowCloudFrontInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  qualifier     = aws_lambda_alias.live.name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.this[0].arn
}

# --- CloudFront (persistent envs only) ---
locals {
  furl_host = replace(replace(aws_lambda_function_url.this.function_url, "https://", ""), "/", "")
}

# OAC signs CloudFront's requests to the Lambda Function URL with SigV4, so the
# FURL can require AWS_IAM (RCP-compliant) while the site stays publicly reachable.
resource "aws_cloudfront_origin_access_control" "this" {
  count                             = var.enable_cloudfront ? 1 : 0
  name                              = local.name
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  count   = var.enable_cloudfront ? 1 : 0
  enabled = true
  comment = local.name

  origin {
    domain_name              = local.furl_host
    origin_id                = "lambda"
    origin_access_control_id = aws_cloudfront_origin_access_control.this[0].id
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "lambda"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    # Managed policies: CachingDisabled + AllViewerExceptHostHeader. The latter
    # is required in front of a Lambda Function URL — forwarding Host makes the
    # FURL reject the request. Static-path caching is a later optimization.
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  }

  price_class = var.cloudfront_price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # *.cloudfront.net HTTPS, free
  }

  tags = {
    env     = var.env
    Project = var.name_prefix
  }
}
