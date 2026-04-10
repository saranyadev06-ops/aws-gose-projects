# ============================================================
# Project 4: CloudWatch Dashboard + Composite Alarm
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
  description = "Email for composite alarm notifications"
  type        = string
}

# ------------------------------------------------------------
# We need an EC2 instance and Lambda to monitor
# Reuse Project 1 EC2 and Project 2 Lambda resource names
# ------------------------------------------------------------
variable "ec2_instance_id" {
  description = "EC2 instance ID to monitor (from Project 1 output)"
  type        = string
}

variable "lambda_function_name" {
  description = "Lambda function name to monitor"
  default     = "gose-ec2-stopper"
}

# ------------------------------------------------------------
# SNS Topic for composite alarm
# ------------------------------------------------------------
resource "aws_sns_topic" "dashboard_alerts" {
  name = "gose-dashboard-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.dashboard_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ------------------------------------------------------------
# Individual Alarms (needed for composite alarm)
# ------------------------------------------------------------

# Alarm 1: EC2 CPU > 80%
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  alarm_name          = "gose-dashboard-ec2-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EC2 CPU exceeded 80%"

  dimensions = {
    InstanceId = var.ec2_instance_id
  }
}

# Alarm 2: Lambda errors > 0
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "gose-dashboard-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Lambda reported errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_function_name
  }
}

# ------------------------------------------------------------
# Composite Alarm: fires when BOTH alarms are in ALARM state
# This is the advanced pattern - reduces false positives
# ------------------------------------------------------------
resource "aws_cloudwatch_composite_alarm" "critical_alert" {
  alarm_name        = "gose-dashboard-critical-composite"
  alarm_description = "Fires when BOTH EC2 CPU is high AND Lambda has errors simultaneously"

  alarm_rule = "ALARM(${aws_cloudwatch_metric_alarm.ec2_cpu_high.alarm_name}) AND ALARM(${aws_cloudwatch_metric_alarm.lambda_errors.alarm_name})"

  alarm_actions = [aws_sns_topic.dashboard_alerts.arn]

  depends_on = [
    aws_cloudwatch_metric_alarm.ec2_cpu_high,
    aws_cloudwatch_metric_alarm.lambda_errors
  ]
}

# ------------------------------------------------------------
# CloudWatch Dashboard
# ------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "gose_ops" {
  dashboard_name = "GOSE-Operations-Dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# GOSE Operations Dashboard | EC2 + Lambda Monitoring"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "EC2 CPU Utilization"
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "CPUUtilization",
              "InstanceId", var.ec2_instance_id,
              { color = "#ff7f0e", label = "CPU %" }
            ]
          ]
          annotations = {
            horizontal = [{
              value = 80
              label = "Critical threshold"
              color = "#d62728"
            }]
          }
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "EC2 Status Check Failed"
          view   = "timeSeries"
          stat   = "Maximum"
          period = 60
          region = var.aws_region
          annotations = { horizontal = [] }
          metrics = [
            ["AWS/EC2", "StatusCheckFailed",
              "InstanceId", var.ec2_instance_id,
              { color = "#d62728", label = "Status Failures" }
            ]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Invocations"
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          region = var.aws_region
          annotations = { horizontal = [] }
          metrics = [
            ["AWS/Lambda", "Invocations",
              "FunctionName", var.lambda_function_name,
              { color = "#1f77b4", label = "Invocations" }
            ]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Errors"
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          region = var.aws_region
          annotations = { horizontal = [] }
          metrics = [
            ["AWS/Lambda", "Errors",
              "FunctionName", var.lambda_function_name,
              { color = "#d62728", label = "Errors" }
            ]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Duration (ms)"
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          region = var.aws_region
          annotations = { horizontal = [] }
          metrics = [
            ["AWS/Lambda", "Duration",
              "FunctionName", var.lambda_function_name,
              { color = "#2ca02c", label = "Avg Duration ms" }
            ]
          ]
        }
      },
      {
        type   = "alarm"
        x      = 0
        y      = 13
        width  = 24
        height = 4
        properties = {
          title = "Alarm Status"
          alarms = [
            "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:gose-dashboard-ec2-cpu-high",
            "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:gose-dashboard-lambda-errors",
            "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:gose-dashboard-critical-composite"
          ]
        }
      }
    ]
  })

  
}

# Get current AWS account ID for alarm ARNs
data "aws_caller_identity" "current" {}

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------
output "dashboard_url" {
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.gose_ops.dashboard_name}"
  description = "Direct URL to the CloudWatch dashboard"
}

output "composite_alarm_name" {
  value = aws_cloudwatch_composite_alarm.critical_alert.alarm_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.dashboard_alerts.arn
}