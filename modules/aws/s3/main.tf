# Main bucket
resource "aws_s3_bucket" "main" {
  bucket_prefix = var.name
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "main" {
  bucket = aws_s3_bucket.main.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "main" {
  bucket     = aws_s3_bucket.main.id
  acl        = "private"
  depends_on = [aws_s3_bucket_ownership_controls.main]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

  count = var.no_default_encryption ? 0 : 1
}

resource "aws_s3_bucket_logging" "main" {
  bucket = aws_s3_bucket.main.id

  target_bucket = aws_s3_bucket.logging[0].id
  target_prefix = var.name

  count = var.no_logging ? 0 : 1
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = var.no_versioning ? "Disabled" : "Enabled"
  }
}

resource "aws_s3_bucket_website_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  index_document {
    suffix = "index.html"
  }

  count = var.website_enabled ? 1 : 0
}

# Logging bucket
resource "aws_s3_bucket" "logging" {
  bucket_prefix = "${var.name}-logging"
  force_destroy = true

  count = var.no_logging ? 0 : 1
}

resource "aws_s3_bucket_ownership_controls" "logging" {
  bucket = aws_s3_bucket.logging[0].id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
  count = var.no_logging ? 0 : 1
}

resource "aws_s3_bucket_acl" "logging" {
  bucket     = aws_s3_bucket.logging[0].id
  acl        = var.bucket_acl
  depends_on = [aws_s3_bucket_ownership_controls.logging]
  count      = var.no_logging ? 0 : 1
}

# Force SSL only access policy
resource "aws_s3_bucket_policy" "force_ssl_only_access" {
  bucket = aws_s3_bucket.main.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ForceSSLOnlyAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.main.arn,
          "${aws_s3_bucket.main.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  count = var.allow_cleartext ? 1 : 0
}

# Get-only bucket
resource "aws_s3_bucket" "getonly" {
  bucket_prefix = "${var.name}-getonly"
  force_destroy = true

  count = var.s3_getobject_only ? 1 : 0
}

resource "aws_s3_bucket_public_access_block" "getonly" {
  bucket = aws_s3_bucket.getonly[0].id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

  count = var.s3_getobject_only ? 1 : 0
}

resource "aws_s3_bucket_policy" "getonly" {
  bucket = aws_s3_bucket.getonly[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          aws_s3_bucket.getonly[0].arn,
          "${aws_s3_bucket.getonly[0].arn}/*",
        ]
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.getonly]
  count      = var.s3_getobject_only ? 1 : 0
}

# Public bucket
resource "aws_s3_bucket" "public" {
  bucket_prefix = "${var.name}-public"
  force_destroy = true

  count = var.s3_public ? 1 : 0
}

resource "aws_s3_bucket_public_access_block" "public" {
  bucket = aws_s3_bucket.public[0].id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

  count = var.s3_public ? 1 : 0
}

resource "aws_s3_bucket_policy" "public" {
  bucket = aws_s3_bucket.public[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadWriteObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.public[0].arn,
          "${aws_s3_bucket.public[0].arn}/*",
        ]
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.public]
  count      = var.s3_public ? 1 : 0
}
