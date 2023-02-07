 # Eventbridge to notify of copy completion to central backup account

 resource "aws_iam_role" "eventsBridgeRole" {
    provider          = aws.sandbox
    name = "iam-role-eventbridge"
    assume_role_policy = data.aws_iam_policy_document.event_bridge_assume_role_policy.json
    managed_policy_arns = [aws_iam_policy.EventBridgePolicy.arn]

   
 }

 data "aws_iam_policy_document" "event_bridge_assume_role_policy"{
    statement {
        actions = ["sts:AssumeRole"]
        effect  = "Allow"
        principals {
            type = "Service"
            identifiers = ["events.amazonaws.com"]
        }
    }
 }

 data "aws_iam_policy_document" "eventBridgePolicyDocument" {
    statement {
        actions = ["events:PutEvents"]
        effect = "Allow"
        resources = [aws_cloudwatch_event_bus.central_event_bus.arn]
    }
 }

 resource "aws_iam_policy" "EventBridgePolicy" {
    provider          = aws.sandbox
    name = "RDS_eventbridge_policy"
    policy = data.aws_iam_policy_document.eventBridgePolicyDocument.json
 }

resource "aws_cloudwatch_event_rule" "eventbridge_rule" {
    provider          = aws.sandbox
    name = "snapshot_copy_completion"
    description = "Event Rule for RDS snapshot Backup Copy Job Complete Event"
    role_arn = "${aws_iam_role.eventsBridgeRole.arn}"
    event_pattern = <<EOF
          {
            "source": ["aws.backup"],
            "detail-type": ["Copy Job State Change"],
            "detail": {
              "state": ["COMPLETED"],
              "resourceType": ["RDS"],
              "destinationBackupVaultArn": [{
                "prefix": "${aws_backup_vault.central_backup_vault.arn}"
              }]
            }
          }
          EOF
    is_enabled = true
    event_bus_name = "default"
}

resource "aws_cloudwatch_event_target" "eventbridge_target" {
    provider          = aws.sandbox
    rule       = aws_cloudwatch_event_rule.eventbridge_rule.name
    target_id  = "notifyCentralEventBus"
    arn        = aws_cloudwatch_event_bus.central_event_bus.arn  #arn of event bus to receive notification in central bkup acc
    role_arn   = aws_iam_role.eventsBridgeRole.arn
}




## even bus policy on central backup account

data "aws_iam_policy_document" "event_bus_policy_org" {
  statement {
    sid    = "OrganizationAccess"
    effect = "Allow"
    actions = [
      "events:PutEvents"
    ]
    principals {
      type        = "AWS"
      identifiers = ["*"]   # allow all accounts in the organization
    }

    resources = [aws_cloudwatch_event_bus.central_event_bus.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
  }
}




# create event bus on central backup account for receiving copy completion notification

resource "aws_cloudwatch_event_bus" "central_event_bus" {
    provider = aws.backup
    name = "copy_status_events_bus"
}

resource "aws_cloudwatch_event_bus_policy" "eventbus_policy_central" {
    provider = aws.backup
    policy = data.aws_iam_policy_document.event_bus_policy_org.json
    event_bus_name = aws_cloudwatch_event_bus.central_event_bus.name
    depends_on = [aws_cloudwatch_event_bus.central_event_bus]
}


# event rule to trigger Lambda copy to s3 after copy completion status attained

resource "aws_cloudwatch_event_rule" "central_eventbridge_rule" {
    provider          = aws.backup
    name = "snapshot_copy_completion_central"
    description = "Event Rule for RDS snapshot Backup Copy Job Complete Event notification"
    event_pattern = <<EOF
          {
            "source": ["aws.backup"],
            "detail-type": ["Copy Job State Change"],
            "account": [{
              "anything-but": "${data.aws_caller_identity.backup_account.account_id}"
            }],
            "detail": {
              "state": ["COMPLETED"],
              "resourceType": ["RDS"]
            }
          }
          EOF
    is_enabled = true
    event_bus_name = aws_cloudwatch_event_bus.central_event_bus.name
}

resource "aws_cloudwatch_event_target" "taget_lambda" {
    provider    = aws.backup
    rule       = aws_cloudwatch_event_rule.central_eventbridge_rule.name
    event_bus_name = aws_cloudwatch_event_bus.central_event_bus.name
    target_id  = "triggerS3CopyLambda"
    arn        = aws_lambda_function.lambda_copy2s3.arn
    depends_on = [aws_cloudwatch_event_rule.central_eventbridge_rule, aws_lambda_function.lambda_copy2s3]
}


## Events for Copying to DR Region

# Manual snapshop copy to s3 completed

resource "aws_cloudwatch_event_rule" "s3_copy_rule" {
    provider          = aws.backup
    name = "manual_copy_completion"
    description = "Event Rule for Manual snapshot creation to s3"
    event_pattern = <<EOF
          {
            "source": ["aws.s3"],
            "detail-type": ["Object Created"],
            "account": "${data.aws_caller_identity.backup_account.account_id}",
            "resources": ["${aws_s3_bucket.snapshots_bucket.arn}"]
            "reason": "PutObject"
            "detail": {
                "bucket": {
                  "name": "${aws_s3_bucket.snapshots_bucket.name}"
                  }
            }
          }
          EOF
    is_enabled = true
    event_bus_name = aws_cloudwatch_event_bus.central_event_bus.name
}