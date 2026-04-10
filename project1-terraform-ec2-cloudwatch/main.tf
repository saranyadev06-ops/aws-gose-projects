# ============================================================
# Project 1: EC2 + IAM + CloudWatch Alarms via Terraform
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

# ------------------------------------------------------------
# Variables
# ------------------------------------------------------------
variable "aws_region" {
  default = "us-east-1"
}

variable "my_ip" {
  description = "72.83.231.33/32"
  type        = string
}

variable "alert_email" {
  description = "saranyadev06@gmail.com"
  type        = string
}

# ------------------------------------------------------------
# Data: Latest Amazon Linux 2 AMI
# ------------------------------------------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# ------------------------------------------------------------
# IAM Role + Instance Profile (SSM access - no key pair needed)
# ------------------------------------------------------------
resource "aws_iam_role" "ec2_ssm_role" {
  name = "gose-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Project     = "GOSE-Practice"
    Environment = "dev"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "gose-ec2-instance-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

# ------------------------------------------------------------
# Security Group
# ------------------------------------------------------------
resource "aws_security_group" "gose_sg" {
  name        = "gose-practice-sg"
  description = "Allow SSH from my IP only"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "SSH from my IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Project     = "GOSE-Practice"
    Environment = "dev"
  }
}

# ------------------------------------------------------------
# EC2 Instance
# ------------------------------------------------------------
resource "aws_instance" "gose_ec2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.gose_sg.id]

  # Install stress tool on launch for CloudWatch alarm testing
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install epel -y
    yum install -y stress
  EOF

  tags = {
    Name        = "gose-practice-ec2"
    Project     = "GOSE-Practice"
    Environment = "dev"
  }
}

# ------------------------------------------------------------
# SNS Topic for Alarm Notifications
# ------------------------------------------------------------
resource "aws_sns_topic" "alarm_topic" {
  name = "gose-cloudwatch-alarms"

  tags = {
    Project     = "GOSE-Practice"
    Environment = "dev"
  }
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alarm_topic.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ------------------------------------------------------------
# CloudWatch Alarm: CPU > 70% for 2 consecutive periods
# ------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "gose-ec2-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "EC2 CPU utilization exceeded 70% for 2 consecutive minutes"
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]
  ok_actions          = [aws_sns_topic.alarm_topic.arn]

  dimensions = {
    InstanceId = aws_instance.gose_ec2.id
  }

  tags = {
    Project     = "GOSE-Practice"
    Environment = "dev"
  }
}

# ------------------------------------------------------------
# CloudWatch Alarm: Instance Status Check Failed
# ------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "gose-ec2-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "EC2 instance status check failed"
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]

  dimensions = {
    InstanceId = aws_instance.gose_ec2.id
  }

  tags = {
    Project     = "GOSE-Practice"
    Environment = "dev"
  }
}

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------
output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.gose_ec2.id
}

output "instance_public_ip" {
  description = "EC2 Public IP"
  value       = aws_instance.gose_ec2.public_ip
}

output "sns_topic_arn" {
  description = "SNS Topic ARN for alarms"
  value       = aws_sns_topic.alarm_topic.arn
}

output "cloudwatch_alarm_name" {
  description = "CloudWatch CPU alarm name"
  value       = aws_cloudwatch_metric_alarm.cpu_high.alarm_name
}
