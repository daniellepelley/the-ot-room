#!/usr/bin/env bash
#
# Provision The OT Room hosting WITHOUT Terraform, using only the AWS CLI.
# Designed to be run in AWS CloudShell (browser terminal — AWS CLI + jq already installed,
# credentials already loaded). Run it from the repo root so it can read deploy/site-router.js.
#
# It builds the same stack as deploy/*.tf:
#   Route 53 hosted zone, an ACM cert (us-east-1), two private S3 buckets, an Origin Access Control,
#   the router CloudFront function, two CloudFront distributions, the bucket policies, and the DNS
#   records for the apex, www and test.
#
# Because DNS has to move to Route 53 before the certificate can validate, it runs in TWO passes:
#
#     ./deploy/cloudshell-provision.sh zone     # pass 1: create the zone, print the nameservers
#     ---- then point GoDaddy at those nameservers and wait for propagation ----
#     ./deploy/cloudshell-provision.sh rest     # pass 2: everything else
#
# Re-running is mostly safe: existing resources are detected and reused rather than duplicated.

set -euo pipefail

# ---- settings (edit here if you change names/region) ----------------------------------------------
DOMAIN="theotroom.co.uk"
WWW="www.${DOMAIN}"
TEST_HOST="test.${DOMAIN}"
REGION="eu-west-2"                 # where the two origin buckets live
TEST_BUCKET="the-ot-room-test"
LIVE_BUCKET="the-ot-room-live"
PRICE_CLASS="PriceClass_100"       # NA + EU; use PriceClass_All for global edge coverage
OAC_NAME="the-ot-room-oac"
FUNC_NAME="the-ot-room-router"
CACHE_OPTIMIZED="658327ea-f89d-4fab-a63d-7e88639e58f6"   # AWS managed: CachingOptimized
CACHE_DISABLED="4135ea2d-6df8-44a3-9df3-4b5a84be39ad"    # AWS managed: CachingDisabled
CF_ALIAS_ZONE="Z2FDTNDATAQYW2"                            # fixed hosted-zone id for all CloudFront aliases
# ---------------------------------------------------------------------------------------------------

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

zone_id() {
  aws route53 list-hosted-zones-by-name --dns-name "${DOMAIN}." \
    --query "HostedZones[?Name=='${DOMAIN}.'].Id | [0]" --output text 2>/dev/null | sed 's#/hostedzone/##'
}

cert_arn() {
  aws acm list-certificates --region us-east-1 \
    --query "CertificateSummaryList[?DomainName=='${DOMAIN}'].CertificateArn | [0]" --output text 2>/dev/null
}

dist_id_for_alias() {  # $1 = an alias on the distribution
  aws cloudfront list-distributions \
    --query "DistributionList.Items[?contains(Aliases.Items, '$1')].Id | [0]" --output text 2>/dev/null
}

# ===================================================================================================
# PASS 1 — the hosted zone
# ===================================================================================================
if [ "${1:-}" = "zone" ]; then
  ZID="$(zone_id || true)"
  if [ -z "${ZID}" ] || [ "${ZID}" = "None" ]; then
    echo "Creating the Route 53 hosted zone for ${DOMAIN} ..."
    aws route53 create-hosted-zone --name "${DOMAIN}" --caller-reference "ot-room-$(date +%s)" >/dev/null
    ZID="$(zone_id)"
  else
    echo "Hosted zone already exists (${ZID})."
  fi

  echo
  echo "================ NEXT: point GoDaddy at these four nameservers ================"
  aws route53 get-hosted-zone --id "${ZID}" --query 'DelegationSet.NameServers' --output table
  echo "==============================================================================="
  echo "In GoDaddy: theotroom.co.uk -> DNS -> Nameservers -> Change -> 'I'll use my own'"
  echo "Enter the four above, turn OFF DNSSEC if it's on, and save."
  echo "Check with:  dig NS ${DOMAIN} +short"
  echo "When those return the awsdns servers, run:  ./deploy/cloudshell-provision.sh rest"
  exit 0
fi

# ===================================================================================================
# PASS 2 — everything else
# ===================================================================================================
if [ "${1:-}" != "rest" ]; then
  echo "Usage: $0 zone   (pass 1)   |   $0 rest   (pass 2, after GoDaddy is pointed at Route 53)"
  exit 1
fi

ZID="$(zone_id || true)"
if [ -z "${ZID}" ] || [ "${ZID}" = "None" ]; then
  echo "No hosted zone found — run '$0 zone' first."; exit 1
fi
echo "Using hosted zone ${ZID}."

# ---- 1. ACM certificate (us-east-1, DNS-validated) ------------------------------------------------
CARN="$(cert_arn || true)"
if [ -z "${CARN}" ] || [ "${CARN}" = "None" ]; then
  echo "Requesting the ACM certificate (us-east-1) ..."
  CARN="$(aws acm request-certificate --region us-east-1 \
    --domain-name "${DOMAIN}" \
    --subject-alternative-names "${WWW}" "${TEST_HOST}" \
    --validation-method DNS \
    --query CertificateArn --output text)"
  sleep 5   # give ACM a moment to populate the validation records
else
  echo "Reusing existing certificate ${CARN}."
fi

echo "Writing the DNS validation records into Route 53 ..."
aws acm describe-certificate --region us-east-1 --certificate-arn "${CARN}" \
  --query 'Certificate.DomainValidationOptions[].ResourceRecord' --output json > /tmp/val.json
jq '{Changes: (unique_by(.Name) | map({Action:"UPSERT", ResourceRecordSet:{Name:.Name, Type:.Type, TTL:60, ResourceRecords:[{Value:.Value}]}}))}' \
  /tmp/val.json > /tmp/val-change.json
aws route53 change-resource-record-sets --hosted-zone-id "${ZID}" --change-batch file:///tmp/val-change.json >/dev/null

echo "Waiting for the certificate to validate (needs GoDaddy delegation to be live; up to ~10 min) ..."
if ! aws acm wait certificate-validated --region us-east-1 --certificate-arn "${CARN}"; then
  echo "::: Still not validated. This almost always means the GoDaddy nameserver switch hasn't"
  echo "::: propagated yet. Check 'dig NS ${DOMAIN} +short', wait, then re-run '$0 rest'."
  exit 1
fi
echo "Certificate validated."

# ---- 2. S3 buckets (private) ----------------------------------------------------------------------
for B in "${TEST_BUCKET}" "${LIVE_BUCKET}"; do
  if aws s3api head-bucket --bucket "${B}" 2>/dev/null; then
    echo "Bucket ${B} already exists."
  else
    echo "Creating bucket ${B} ..."
    aws s3api create-bucket --bucket "${B}" --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}" >/dev/null
  fi
  aws s3api put-public-access-block --bucket "${B}" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
done

# ---- 3. Origin Access Control ---------------------------------------------------------------------
OAC_ID="$(aws cloudfront list-origin-access-controls \
  --query "OriginAccessControlList.Items[?Name=='${OAC_NAME}'].Id | [0]" --output text 2>/dev/null || true)"
if [ -z "${OAC_ID}" ] || [ "${OAC_ID}" = "None" ]; then
  echo "Creating the Origin Access Control ..."
  OAC_ID="$(aws cloudfront create-origin-access-control --origin-access-control-config \
    "Name=${OAC_NAME},SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3" \
    --query 'OriginAccessControl.Id' --output text)"
else
  echo "Reusing Origin Access Control ${OAC_ID}."
fi

# ---- 4. Router CloudFront function ----------------------------------------------------------------
if aws cloudfront describe-function --name "${FUNC_NAME}" >/dev/null 2>&1; then
  echo "Function ${FUNC_NAME} already exists."
else
  echo "Creating the router function ..."
  aws cloudfront create-function --name "${FUNC_NAME}" \
    --function-config "Comment=apex->www redirect + index rewrite,Runtime=cloudfront-js-2.0" \
    --function-code fileb://deploy/site-router.js >/dev/null
fi
# publish the latest code
FETAG="$(aws cloudfront describe-function --name "${FUNC_NAME}" --query ETag --output text)"
aws cloudfront publish-function --name "${FUNC_NAME}" --if-match "${FETAG}" >/dev/null || true
FUNC_ARN="arn:aws:cloudfront::${ACCOUNT_ID}:function/${FUNC_NAME}"

# ---- 5. CloudFront distributions ------------------------------------------------------------------
# Writes a distribution-config JSON and creates the distribution if one with that alias doesn't exist.
make_distribution() {
  local comment="$1" origin_id="$2" bucket="$3" cache_policy="$4" err_ttl="$5" aliases_json="$6" alias_count="$7"
  local domain="${bucket}.s3.${REGION}.amazonaws.com"
  cat > /tmp/dist.json <<JSON
{
  "CallerReference": "${origin_id}-$(date +%s)",
  "Comment": "${comment}",
  "Enabled": true,
  "HttpVersion": "http2and3",
  "IsIPV6Enabled": true,
  "PriceClass": "${PRICE_CLASS}",
  "DefaultRootObject": "index.html",
  "Aliases": { "Quantity": ${alias_count}, "Items": ${aliases_json} },
  "Origins": { "Quantity": 1, "Items": [ {
    "Id": "${origin_id}",
    "DomainName": "${domain}",
    "OriginAccessControlId": "${OAC_ID}",
    "S3OriginConfig": { "OriginAccessIdentity": "" },
    "CustomHeaders": { "Quantity": 0 },
    "OriginShield": { "Enabled": false }
  } ] },
  "DefaultCacheBehavior": {
    "TargetOriginId": "${origin_id}",
    "ViewerProtocolPolicy": "redirect-to-https",
    "Compress": true,
    "CachePolicyId": "${cache_policy}",
    "AllowedMethods": { "Quantity": 3, "Items": ["GET","HEAD","OPTIONS"],
      "CachedMethods": { "Quantity": 2, "Items": ["GET","HEAD"] } },
    "FunctionAssociations": { "Quantity": 1, "Items": [
      { "EventType": "viewer-request", "FunctionARN": "${FUNC_ARN}" } ] },
    "LambdaFunctionAssociations": { "Quantity": 0 }
  },
  "CustomErrorResponses": { "Quantity": 1, "Items": [
    { "ErrorCode": 403, "ResponseCode": "404", "ResponsePagePath": "/404.html", "ErrorCachingMinTTL": ${err_ttl} } ] },
  "ViewerCertificate": {
    "ACMCertificateArn": "${CARN}",
    "SSLSupportMethod": "sni-only",
    "MinimumProtocolVersion": "TLSv1.2_2021"
  },
  "Restrictions": { "GeoRestriction": { "RestrictionType": "none", "Quantity": 0 } }
}
JSON
  aws cloudfront create-distribution --distribution-config file:///tmp/dist.json \
    --query 'Distribution.Id' --output text
}

LIVE_DIST="$(dist_id_for_alias "${DOMAIN}" || true)"
if [ -z "${LIVE_DIST}" ] || [ "${LIVE_DIST}" = "None" ]; then
  echo "Creating the production distribution (${DOMAIN} + ${WWW}) ..."
  LIVE_DIST="$(make_distribution "theotroom.co.uk (production)" "live-s3" "${LIVE_BUCKET}" \
    "${CACHE_OPTIMIZED}" 60 "[\"${DOMAIN}\",\"${WWW}\"]" 2)"
else
  echo "Production distribution already exists (${LIVE_DIST})."
fi

TEST_DIST="$(dist_id_for_alias "${TEST_HOST}" || true)"
if [ -z "${TEST_DIST}" ] || [ "${TEST_DIST}" = "None" ]; then
  echo "Creating the test distribution (${TEST_HOST}) ..."
  TEST_DIST="$(make_distribution "test.theotroom.co.uk (staging)" "test-s3" "${TEST_BUCKET}" \
    "${CACHE_DISABLED}" 0 "[\"${TEST_HOST}\"]" 1)"
else
  echo "Test distribution already exists (${TEST_DIST})."
fi

LIVE_DOMAIN="$(aws cloudfront get-distribution --id "${LIVE_DIST}" --query 'Distribution.DomainName' --output text)"
TEST_DOMAIN="$(aws cloudfront get-distribution --id "${TEST_DIST}" --query 'Distribution.DomainName' --output text)"

# ---- 6. Bucket policies (let each distribution read its bucket via OAC) ----------------------------
put_bucket_policy() {
  local bucket="$1" dist="$2"
  cat > /tmp/policy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [ {
    "Sid": "AllowCloudFrontOAC",
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::${bucket}/*",
    "Condition": { "StringEquals": {
      "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${dist}" } }
  } ]
}
JSON
  aws s3api put-bucket-policy --bucket "${bucket}" --policy file:///tmp/policy.json
}
echo "Attaching bucket policies ..."
put_bucket_policy "${LIVE_BUCKET}" "${LIVE_DIST}"
put_bucket_policy "${TEST_BUCKET}" "${TEST_DIST}"

# ---- 7. DNS records (alias A + AAAA) --------------------------------------------------------------
alias_record() {  # $1 name  $2 A|AAAA  $3 dist domain
  cat <<JSON
{ "Action": "UPSERT", "ResourceRecordSet": {
    "Name": "$1", "Type": "$2",
    "AliasTarget": { "HostedZoneId": "${CF_ALIAS_ZONE}", "DNSName": "$3", "EvaluateTargetHealth": false } } }
JSON
}
echo "Creating the DNS records ..."
cat > /tmp/dns.json <<JSON
{ "Changes": [
  $(alias_record "${DOMAIN}"    "A"    "${LIVE_DOMAIN}"),
  $(alias_record "${DOMAIN}"    "AAAA" "${LIVE_DOMAIN}"),
  $(alias_record "${WWW}"       "A"    "${LIVE_DOMAIN}"),
  $(alias_record "${WWW}"       "AAAA" "${LIVE_DOMAIN}"),
  $(alias_record "${TEST_HOST}" "A"    "${TEST_DOMAIN}"),
  $(alias_record "${TEST_HOST}" "AAAA" "${TEST_DOMAIN}")
] }
JSON
aws route53 change-resource-record-sets --hosted-zone-id "${ZID}" --change-batch file:///tmp/dns.json >/dev/null

# ---- Done: print the values you need for GitHub ---------------------------------------------------
cat <<SUMMARY

============================ DONE — values for the GitHub setup ============================
  WEBSITE_TEST_BUCKET            = ${TEST_BUCKET}
  WEBSITE_LIVE_BUCKET            = ${LIVE_BUCKET}
  WEBSITE_TEST_DISTRIBUTION_ID   = ${TEST_DIST}
  WEBSITE_LIVE_DISTRIBUTION_ID   = ${LIVE_DIST}
  WEBSITE_AWS_REGION             = ${REGION}

  Production : https://${WWW}   (apex ${DOMAIN} redirects here)
  Test       : https://${TEST_HOST}
===========================================================================================
The distributions take a few minutes to finish deploying. The buckets are empty, so the sites
return 404 until the first GitHub deploy runs.
SUMMARY
