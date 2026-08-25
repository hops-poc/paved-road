output "function_url" {
  description = "Direct Lambda Function URL (the origin CloudFront fronts; used raw by previews)"
  value       = aws_lambda_function_url.this.function_url
}

output "url" {
  description = "The public entrypoint — CloudFront when enabled, else the Function URL"
  value       = var.enable_cloudfront ? "https://${aws_cloudfront_distribution.this[0].domain_name}" : aws_lambda_function_url.this.function_url
}

output "table_name" {
  value = aws_dynamodb_table.this.name
}

output "alias_arn" {
  description = "The live alias — rollback flips this (§5.3)"
  value       = aws_lambda_alias.live.arn
}
