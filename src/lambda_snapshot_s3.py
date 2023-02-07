import json
import boto3
import os
import logging
from datetime import datetime
CMK_ARN = os.environ["KmsKeyId"]
BUCKET_NAME = os.environ["S3BucketName"]
IAM_ROLE = os.environ["IamRoleArn"]
now = datetime.now()
currentTime = now.strftime("%d-%m-%Y-%H-%M-%S")



def handler(event, context):
    logger = logging.getLogger()
    logging.getLogger("boto3").setLevel(logging.WARNING)
    logging.getLogger("botocore").setLevel(logging.WARNING)
    logger.debug('Incoming Event') 
    logger.debug(event)
    client = boto3.client('rds')
    snapshot_recovery_point = event['detail']['destinationRecoveryPointArn']
    response = client.start_export_task(
        ExportTaskIdentifier="snapshotCopy"+ currentTime,
        SourceArn=snapshot_recovery_point,
        S3BucketName=BUCKET_NAME,
        IamRoleArn=IAM_ROLE,
        KmsKeyId=CMK_ARN,
)
    logger.info('AWS Backup Copy Status: ' + response['Status'])   
    return json.dumps(response, default=str)




