#!/bin/bash
set -euo pipefail

BUCKET_NAME="${1:?Usage: create-state-bucket.sh <bucket-name> [minio|aws]}"
BACKEND="${2:-${BUCKET_BACKEND:-minio}}"

case "$BACKEND" in
  minio)
    ENDPOINT_URL="${AWS_ENDPOINT_URL_S3:-${AWS_ENDPOINT_URL:-http://localhost:9000}}"
    if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
      echo "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set for MinIO mode."
      exit 1
    fi
    if aws s3 ls "s3://${BUCKET_NAME}" --endpoint-url "$ENDPOINT_URL" &>/dev/null; then
      echo "Bucket ${BUCKET_NAME} already exists."
      exit 0
    fi
    aws s3 mb "s3://${BUCKET_NAME}" --endpoint-url "$ENDPOINT_URL"
    echo "Bucket ${BUCKET_NAME} created successfully."
    ;;
  aws)
    unset AWS_ENDPOINT_URL AWS_ENDPOINT_URL_S3
    if [ -z "${AWS_REGION:-}" ] || [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
      echo "AWS_REGION, AWS_ACCESS_KEY_ID, and AWS_SECRET_ACCESS_KEY must be set for AWS mode."
      exit 1
    fi
    if aws s3 ls "s3://${BUCKET_NAME}" --region "$AWS_REGION" &>/dev/null; then
      echo "Bucket ${BUCKET_NAME} already exists."
      exit 0
    fi
    aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
    echo "Bucket ${BUCKET_NAME} created successfully."
    ;;
  *)
    echo "Unknown backend: ${BACKEND}. Expected 'minio' or 'aws'."
    exit 1
    ;;
esac
