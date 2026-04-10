# ============================================================
# Project 2: Lambda + IAM + EventBridge via Terraform
# GOSE Practice - Saranya Devi Raja
# ============================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "alert_email" {
  description = "Email for Lambda error notifications"
  type        = string
}

# ------------------------------------------------------------
# SNS Topic for Lambda error alerts
# ------------------------------------------------------------
resource "aws_sns_topic" "lambda_errors" {
  name = "gose-lambda-errors"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.lambda_errors.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ------------------------------------------------------------
# IAM Role for Lambda
# Least privilege: only what the function needs
# ------------------------------------------------------------
resource "aws_iam_role" "lambda_role" {
  name = "gose-lambda-ec2-stopper-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Allow Lambda to write logs to CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy: only describe + stop EC2, publish to our SNS topic
resource "aws_iam_role_policy" "lambda_ec2_policy" {
  name = "gose-lambda-ec2-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2StopPermissions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StopInstances"
        ]
        Resource = "*"
      },
      {
        Sid      = "SNSPublishErrors"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.lambda_errors.arn
      }
    ]
  })
}

# ------------------------------------------------------------
# Package Lambda code into zip
# ------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# ------------------------------------------------------------
# Lambda Function
# ------------------------------------------------------------
resource "aws_lambda_function" "ec2_stopper" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "gose-ec2-stopper"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.lambda_errors.arn
    }
  }

  tags = {
    Project     = "GOSE-Practice"
    Environment = "dev"
  }
}

# CloudWatch Log Group for Lambda (explicit retention policy)
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.ec2_stopper.function_name}"
  retention_in_days = 7
}

# ------------------------------------------------------------
# EventBridge Rule: trigger Lambda every day at 8 PM UTC
# ------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "daily_trigger" {
  name                = "gose-ec2-stopper-schedule"
  description         = "Stop dev EC2 instances daily at 8 PM UTC"
  schedule_expression = "cron(0 20 * * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_trigger.name
  target_id = "GoSEEc2Stopper"
  arn       = aws_lambda_function.ec2_stopper.arn
}

# Allow EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_stopper.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_trigger.arn
}

# ------------------------------------------------------------
# CloudWatch Alarm: Lambda errors > 0
# ------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "gose-lambda-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Lambda ec2-stopper reported errors"
  alarm_actions       = [aws_sns_topic.lambda_errors.arn]

  dimensions = {
    FunctionName = aws_lambda_function.ec2_stopper.function_name
  }
}

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------
output "lambda_function_name" {
  value = aws_lambda_function.ec2_stopper.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.ec2_stopper.arn
}

output "eventbridge_rule" {
  value = aws_cloudwatch_event_rule.daily_trigger.name
}

output "log_group" {
  value = aws_cloudwatch_log_group.lambda_logs.name
}
