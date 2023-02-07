import boto3
import os
import logging
import json

backup_s3_bucket = os.environ["backup_s3_bucket"]
dr_s3_bucket = os.environ["dr_s3_bucket"]
kms_key_id  = os.environ["KmsKeyId"]

def lambda_handler (event, context):
    logger = logging.getLogger()
    logging.getLogger("boto3").setLevel(logging.WARNING)
    logger.debug('Incoming Event') 
    logger.debug(event)
    s3 = boto3.resource('s3')
    client = boto3.client('s3')
    bucket = s3.Bucket(backup_s3_bucket)
    dr_bucket = dr_s3_bucket


    print(dr_bucket)
    print(bucket)
    object_exists = list(bucket.objects.filter(Prefix='snapshot'))
    if len(object_exists) > 0:
        for obj in object_exists:
            bucket_key = obj.key
            source_dict = {
                'Bucket': bucket,
                'Key': bucket_key
            }
            print(f"{'copying snapshot' + bucket_key}")

            response = client.copy_object(
                Bucket = dr_bucket,
                Key    = bucket_key,
                CopySource = source_dict,
                SSECustomerKey = kms_key_id,
                BucketKeyEnabled = True
                )

            # delete snapshot from source bucket
            s3.Object(bucket, bucket_key).delete()

            logger.info("Status: " + response['Status'])
            return json.dumps(response)
    
    else: print(f"{'no new snapshots to copy from S3 bucket' +bucket}")
