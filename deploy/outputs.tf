output "nameservers" {
  description = "Set these as theotroom.co.uk's nameservers at GoDaddy (one-time). DNS only resolves once this is done."
  value       = aws_route53_zone.this.name_servers
}

output "live_bucket" {
  description = "Production origin bucket — set as the repo variable WEBSITE_LIVE_BUCKET."
  value       = aws_s3_bucket.live.bucket
}

output "test_bucket" {
  description = "Test origin bucket — set as the repo variable WEBSITE_TEST_BUCKET (the auto-deploy target)."
  value       = aws_s3_bucket.test.bucket
}

output "live_distribution_id" {
  description = "Production CloudFront distribution — set as the repo variable WEBSITE_LIVE_DISTRIBUTION_ID (invalidated on promote)."
  value       = aws_cloudfront_distribution.live.id
}

output "test_distribution_id" {
  description = "Test CloudFront distribution — set as the repo variable WEBSITE_TEST_DISTRIBUTION_ID (invalidated on each test deploy)."
  value       = aws_cloudfront_distribution.test.id
}

output "live_url" {
  value = "https://${var.domain}"
}

output "test_url" {
  value = "https://test.${var.domain}"
}
