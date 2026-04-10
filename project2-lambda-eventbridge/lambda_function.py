"""
Project 2: Lambda - Automated EC2 Instance Stopper
GOSE Practice - Saranya Devi Raja

Triggered by EventBridge on a schedule.
Stops all running EC2 instances tagged Environment=dev.
Logs results to CloudWatch Logs.
Publishes errors to SNS.
"""

import boto3
import json
import logging
import os
from datetime import datetime

# Configure logging - outputs to CloudWatch Logs automatically
logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")


def lambda_handler(event, context):
    """
    Main Lambda handler.
    Lists running EC2 instances tagged Environment=dev and stops them.
    """
    logger.info("Lambda triggered at %s", datetime.utcnow().isoformat())
    logger.info("Event: %s", json.dumps(event))

    stopped = []
    errors = []

    try:
        # Find all running EC2 instances tagged Environment=dev
        response = ec2.describe_instances(
            Filters=[
                {"Name": "instance-state-name", "Values": ["running"]},
                {"Name": "tag:Environment",      "Values": ["dev"]},
            ]
        )

        # Collect instance IDs
        instance_ids = []
        for reservation in response["Reservations"]:
            for instance in reservation["Instances"]:
                instance_ids.append(instance["InstanceId"])

        if not instance_ids:
            logger.info("No running dev instances found. Nothing to stop.")
            return build_response(200, "No instances to stop", stopped, errors)

        logger.info("Found %d running dev instance(s): %s", len(instance_ids), instance_ids)

        # Stop the instances
        stop_response = ec2.stop_instances(InstanceIds=instance_ids)

        for item in stop_response["StoppingInstances"]:
            instance_id    = item["InstanceId"]
            previous_state = item["PreviousState"]["Name"]
            current_state  = item["CurrentState"]["Name"]

            logger.info(
                "Instance %s: %s -> %s",
                instance_id, previous_state, current_state
            )
            stopped.append({
                "instance_id":     instance_id,
                "previous_state":  previous_state,
                "current_state":   current_state,
            })

    except Exception as e:
        error_msg = f"Error stopping instances: {str(e)}"
        logger.error(error_msg)
        errors.append(error_msg)

        # Publish error to SNS so the team is alerted
        if SNS_TOPIC_ARN:
            try:
                sns.publish(
                    TopicArn=SNS_TOPIC_ARN,
                    Subject="GOSE Lambda Error - EC2 Stopper Failed",
                    Message=f"Lambda execution failed.\n\nError: {error_msg}\n\nContext: {context.function_name}",
                )
                logger.info("Error notification published to SNS")
            except Exception as sns_error:
                logger.error("Failed to publish SNS notification: %s", str(sns_error))

        return build_response(500, "Error during execution", stopped, errors)

    return build_response(200, "Execution complete", stopped, errors)


def build_response(status_code, message, stopped, errors):
    """Build a structured response for CloudWatch Logs visibility."""
    result = {
        "statusCode":       status_code,
        "message":          message,
        "instancesStopped": len(stopped),
        "details":          stopped,
        "errors":           errors,
        "timestamp":        datetime.utcnow().isoformat(),
    }
    logger.info("Result: %s", json.dumps(result, indent=2))
    return result
