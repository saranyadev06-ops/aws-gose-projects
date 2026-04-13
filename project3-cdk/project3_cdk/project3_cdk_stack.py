from aws_cdk import (
    Stack,
    Duration,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_logs as logs,
    CfnOutput,
)
from constructs import Construct

class Project3CdkStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # ── SNS Topic for error alerts ──────────────────────────────
        error_topic = sns.Topic(
            self, "GoseLambdaErrors",
            topic_name="gose-cdk-lambda-errors"
        )

        error_topic.add_subscription(
            subscriptions.EmailSubscription("saranyadev06@gmail.com")
        )

        # ── IAM Role for Lambda ─────────────────────────────────────
        lambda_role = iam.Role(
            self, "GoseLambdaRole",
            role_name="gose-cdk-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Least privilege: only describe + stop EC2, publish to SNS
        lambda_role.add_to_policy(iam.PolicyStatement(
            sid="EC2StopPermissions",
            effect=iam.Effect.ALLOW,
            actions=[
                "ec2:DescribeInstances",
                "ec2:StopInstances"
            ],
            resources=["*"]
        ))

        lambda_role.add_to_policy(iam.PolicyStatement(
            sid="SNSPublishErrors",
            effect=iam.Effect.ALLOW,
            actions=["sns:Publish"],
            resources=[error_topic.topic_arn]
        ))

        # ── Lambda Function ─────────────────────────────────────────
        ec2_stopper = lambda_.Function(
            self, "GoseEc2Stopper",
            function_name="gose-cdk-ec2-stopper",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="lambda_function.lambda_handler",
            code=lambda_.Code.from_asset("lambda"),
            role=lambda_role,
            timeout=Duration.seconds(60),
            environment={
                "SNS_TOPIC_ARN": error_topic.topic_arn
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # ── EventBridge Rule: daily at 8 PM UTC ────────────────────
        rule = events.Rule(
            self, "DailyTrigger",
            rule_name="gose-cdk-ec2-stopper-schedule",
            description="Stop dev EC2 instances daily at 8 PM UTC",
            schedule=events.Schedule.cron(
                minute="0",
                hour="20",
            )
        )

        # ONE LINE connects EventBridge to Lambda
        # CDK handles aws_cloudwatch_event_target + aws_lambda_permission automatically
        rule.add_target(targets.LambdaFunction(ec2_stopper))

        # ── CloudWatch Alarm: Lambda errors > 0 ───────────────────
        error_alarm = cloudwatch.Alarm(
            self, "LambdaErrorAlarm",
            alarm_name="gose-cdk-lambda-errors",
            alarm_description="CDK Lambda ec2-stopper reported errors",
            metric=ec2_stopper.metric_errors(
                period=Duration.minutes(5)
            ),
            threshold=0,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        error_alarm.add_alarm_action(
            cw_actions.SnsAction(error_topic)
        )

        # ── Outputs ────────────────────────────────────────────────
        CfnOutput(self, "LambdaFunctionName",
            value=ec2_stopper.function_name,
            description="Lambda function name"
        )
        CfnOutput(self, "EventBridgeRule",
            value=rule.rule_name,
            description="EventBridge rule name"
        )
        CfnOutput(self, "SnsTopicArn",
            value=error_topic.topic_arn,
            description="SNS topic ARN"
        )