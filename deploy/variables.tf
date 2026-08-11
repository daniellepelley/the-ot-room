variable "domain" {
  description = "The apex domain."
  type        = string
  default     = "theotroom.co.uk"
}

variable "region" {
  description = "Region for the two origin S3 buckets (cosmetic behind CloudFront; the ACM cert is always us-east-1)."
  type        = string
  default     = "eu-west-2"
}

variable "live_bucket_name" {
  description = "Globally-unique name for the production origin bucket."
  type        = string
  default     = "the-ot-room-live"
}

variable "test_bucket_name" {
  description = "Globally-unique name for the test/staging origin bucket."
  type        = string
  default     = "the-ot-room-test"
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 (NA+EU) is the cheapest and fine for a UK site; use PriceClass_All for global edge coverage."
  type        = string
  default     = "PriceClass_100"
}
