# AWS GOSE Practice Projects
**Saranya Devi Raja | AWS Systems Engineer Interview Prep**

Hands-on AWS projects aligned to the AWS Global Operations Support 
Engineering (GOSE) Systems Engineer role. Built using Terraform, 
Python, AWS CDK, and CloudWatch.

---

## Projects

| # | Project | Services | Description |
|---|---------|----------|-------------|
| 1 | [EC2 + IAM + CloudWatch](./project1-terraform-ec2-cloudwatch) | EC2, IAM, CloudWatch, SNS, Terraform | Provision EC2 with IAM role, security group, and CPU/status alarms via Terraform IaC |
| 2 | [Lambda + EventBridge](./project2-lambda-eventbridge) | Lambda, EventBridge, IAM, CloudWatch | Python Lambda that auto-stops idle dev EC2 instances on a daily cron schedule |
| 3 | [CDK Stack](./project3-cdk) | CDK, CloudFormation, Lambda | Redeploy Project 2 using AWS CDK in Python — synthesizes to CloudFormation |
| 4 | [CloudWatch Dashboard](./project4-cloudwatch-dashboard) | CloudWatch, Composite Alarms, SNS | Operations dashboard monitoring EC2 + Lambda with composite alarm |

---

## Key Concepts Demonstrated

- Terraform IaC — version controlled, repeatable infrastructure
- AWS Lambda automation with EventBridge scheduling
- IAM least privilege — scoped permissions per service
- CDK → CloudFormation synthesis
- CloudWatch composite alarms — reduce false positives
- SNS alerting for operational events

---

## Tech Stack

Terraform • Python • AWS CDK • EC2 • Lambda • EventBridge • 
CloudWatch • IAM • SNS • CloudFormation
