resource "aws_cloudformation_stack" "main" {
  name = var.name

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Resources = {
      S3Bucket = {
        Type = "AWS::S3::Bucket"
        Properties = {
          BucketName = "sadcloud-s3-${var.name}"
          PublicAccessBlockConfiguration = {
            BlockPublicAcls       = false
            BlockPublicPolicy     = false
            IgnorePublicAcls      = false
            RestrictPublicBuckets = false
          }
          OwnershipControls = {
            Rules = [
              {
                ObjectOwnership = "ObjectWriter"
              }
            ]
          }
        }
      }
    }
  })

  iam_role_arn = aws_iam_role.main[0].arn
  count        = var.stack_with_role ? 1 : 0

  depends_on = [
    aws_iam_role.main,
    aws_iam_role_policy.main
  ]
}

resource "aws_cloudformation_stack" "secret" {
  name = "sadcloud-secret-stack"

  template_body = file("${path.root}/static/Secret_Output.yaml")
  count         = var.stack_with_secret_output ? 1 : 0
}

resource "aws_iam_role" "main" {
  name  = var.name
  count = var.stack_with_role ? 1 : 0

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudformation.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "main" {
  name  = var.name
  role  = aws_iam_role.main[0].id
  count = var.stack_with_role ? 1 : 0

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:*"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
