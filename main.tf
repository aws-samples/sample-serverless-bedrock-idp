provider "aws" {
  region = "us-east-1" # Change to your preferred region
}

# Variables
variable "bucket_name" {
  type        = string
  description = "Name for the S3 bucket (must be globally unique)"
}

variable "model_id" {
  type        = string
  description = "Model ID from Bedrock"
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
  validation {
    condition     = contains([
      "ai21.jamba-1-5-large-v1:0",
      "ai21.jamba-1-5-mini-v1:0",
      "amazon.nova-canvas-v1:0",
      "amazon.nova-lite-v1:0",
      "amazon.nova-micro-v1:0",
      "amazon.nova-premier-v1:0",
      "amazon.nova-pro-v1:0",
      "anthropic.claude-3-haiku-20240307-v1:0",
      "anthropic.claude-3-opus-20240229-v1:0",
      "anthropic.claude-3-sonnet-20240229-v1:0",
      "anthropic.claude-3-5-haiku-20241022-v1:0",
      "anthropic.claude-3-5-sonnet-20241022-v2:0",
      "anthropic.claude-3-5-sonnet-20240620-v1:0",
      "anthropic.claude-3-7-sonnet-20250219-v1:0",
      "deepseek.r1-v1:0",
      "luma.ray-v2:0",
      "meta.llama3-8b-instruct-v1:0",
      "meta.llama3-70b-instruct-v1:0",
      "meta.llama3-1-8b-instruct-v1:0",
      "meta.llama3-1-70b-instruct-v1:0",
      "meta.llama3-1-405b-instruct-v1:0",
      "meta.llama3-2-1b-instruct-v1:0",
      "meta.llama3-2-3b-instruct-v1:0",
      "meta.llama3-2-11b-instruct-v1:0",
      "meta.llama3-2-90b-instruct-v1:0",
      "meta.llama3-3-70b-instruct-v1:0",
      "meta.llama4-maverick-17b-instruct-v1:0",
      "meta.llama4-scout-17b-instruct-v1:0",
      "mistral.mistral-7b-instruct-v0:2",
      "mistral.mistral-large-2402-v1:0",
      "mistral.mistral-large-2407-v1:0",
      "mistral.mistral-small-2402-v1:0",
      "mistral.mixtral-8x7b-instruct-v0:1",
      "mistral.pixtral-large-2502-v1:0",
      "stability.sd3-5-large-v1:0",
      "stability.stable-image-core-v1:1",
      "stability.stable-image-ultra-v1:1"
    ], var.model_id)
    error_message = "Invalid model ID. Please choose from the allowed values."
  }
}

# S3 Bucket
resource "aws_s3_bucket" "document_bucket" {
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_versioning" "document_bucket_versioning" {
  bucket = aws_s3_bucket.document_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "document_bucket_encryption" {
  bucket = aws_s3_bucket.document_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "document_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.document_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SQS Queue
resource "aws_sqs_queue" "extracted_data_queue" {
  name                    = "bedrock-idp-extracted-data-tf"
  kms_master_key_id       = "alias/aws/sqs"
  visibility_timeout_seconds = 60
}

# DynamoDB Table
resource "aws_dynamodb_table" "birth_certificates_table" {
  name           = "BirthCertificates"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "Id"

  attribute {
    name = "Id"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
  }
}

# IAM Role for Bedrock Invoker Lambda
resource "aws_iam_role" "invoke_bedrock_role" {
  name = "invoke_bedrock_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.invoke_bedrock_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "invoke_bedrock_policy" {
  name        = "invoke-bedrock-claude3-policy"
  description = "Policy for invoking Bedrock Claude 3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.document_bucket.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.extracted_data_queue.arn
      },
      {
        Effect   = "Allow"
        Action   = "dynamodb:PutItem"
        Resource = aws_dynamodb_table.birth_certificates_table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "invoke_bedrock_policy_attachment" {
  role       = aws_iam_role.invoke_bedrock_role.name
  policy_arn = aws_iam_policy.invoke_bedrock_policy.arn
}

# IAM Role for DynamoDB Inserter Lambda
resource "aws_iam_role" "insert_dynamodb_role" {
  name = "insert_dynamodb_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution_dynamodb" {
  role       = aws_iam_role.insert_dynamodb_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "insert_dynamodb_policy" {
  name        = "insert-dynamodb-policy"
  description = "Policy for inserting data into DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "dynamodb:PutItem"
        Resource = aws_dynamodb_table.birth_certificates_table.arn
      },
      {
        Effect   = "Allow"
        Action   = [
          "sqs:DeleteMessage",
          "sqs:ReceiveMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.extracted_data_queue.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "insert_dynamodb_policy_attachment" {
  role       = aws_iam_role.insert_dynamodb_role.name
  policy_arn = aws_iam_policy.insert_dynamodb_policy.arn
}

data "archive_file" "lambda_bedrock_invoker" {
  type        = "zip"
  source_dir = "./lambda/bedrock_invoker/"
  output_path = "./lambda/bedrock_invoker.zip"
}

# Lambda Functions
resource "aws_lambda_function" "invoke_bedrock_function" {
  function_name    = "invoke_bedrock_claude3_tf"
  filename         = "./lambda/bedrock_invoker.zip"
  source_code_hash = data.archive_file.lambda_bedrock_invoker.output_base64sha256
  handler          = "invoke_bedrock_claude3.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.invoke_bedrock_role.arn
  timeout          = 120

  environment {
    variables = {
      QUEUE_URL      = aws_sqs_queue.extracted_data_queue.url
      MODEL_ID       = var.model_id
      DYNAMODB_TABLE = aws_dynamodb_table.birth_certificates_table.name
    }
  }
}

data "archive_file" "lambda_dynamodb_inserter" {
  type        = "zip"
  source_dir = "./lambda/dynamodb_inserter/"
  output_path = "./lambda/dynamodb_inserter.zip"
}

resource "aws_lambda_function" "insert_dynamodb_function" {
  function_name    = "insert_into_dynamodb_tf"
  filename         = "./lambda/dynamodb_inserter.zip"
  source_code_hash = data.archive_file.lambda_dynamodb_inserter.output_base64sha256
  handler          = "insert_into_dynamodb.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.insert_dynamodb_role.arn
  timeout          = 60

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.birth_certificates_table.name
    }
  }
}

# S3 Event Notification
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.document_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.invoke_bedrock_function.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "birth_certificates/images/"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

# Lambda Permission for S3
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.invoke_bedrock_function.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.document_bucket.arn
}

# SQS Event Source Mapping
resource "aws_lambda_event_source_mapping" "sqs_event_source_mapping" {
  event_source_arn = aws_sqs_queue.extracted_data_queue.arn
  function_name    = aws_lambda_function.insert_dynamodb_function.function_name
  enabled          = true
}

# Data source for current region
data "aws_region" "current" {}

# Outputs
output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.document_bucket.id
}

output "queue_url" {
  description = "URL of the SQS queue"
  value       = aws_sqs_queue.extracted_data_queue.url
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.birth_certificates_table.name
}