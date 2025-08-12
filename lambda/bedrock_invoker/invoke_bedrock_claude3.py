import base64
import json
import boto3
import os

s3 = boto3.client('s3')
sqs = boto3.client('sqs')
bedrock = boto3.client('bedrock-runtime', region_name='us-east-1')
QUEUE_URL = os.environ['QUEUE_URL']
MODEL_ID = os.environ['MODEL_ID'] #"anthropic.claude-3-sonnet-20240229-v1:0"

def lambda_handler(event, context):
    bucket_name = event['Records'][0]['s3']['bucket']['name']
    object_key = event['Records'][0]['s3']['object']['key']

    if object_key.endswith(('.jpeg', '.JPEG')):
        try:
            image_data = s3.get_object(Bucket=bucket_name, Key=object_key)['Body'].read()
            base64_image = base64.b64encode(image_data).decode('utf-8')
            
            prompt = """
            This image shows a birth certificate application form. 
            Please precisely copy all the relevant information from the form.
            Leave the field blank if there is no information in corresponding field.
            If the image is not a birth certificate application form, simply return an empty JSON object. 
            If the application form is not filled, leave the fees attributes blank. 
            Translate any non-English text to English. 
            Organize and return the extracted data in a JSON format with the following keys:
            {
                "applicantDetails":{
                    "applicantName": "",
                    "dayPhoneNumber": "",
                    "address": "",
                    "city": "",
                    "state": "",
                    "zipCode": "",
                    "email":""
                },
                "mailingAddress":{
                    "mailingAddressApplicantName": "",
                    "mailingAddress": "",
                    "mailingAddressCity": "",
                    "mailingAddressState": "",
                    "mailingAddressZipCode": ""
                },
                "relationToApplicant":[""],
                "purposeOfRequest": "",
                
                "BirthCertificateDetails":
                {
                    "nameOnBirthCertificate": "",
                    "dateOfBirth": "",
                    "sex": "",
                    "cityOfBirth": "",
                    "countyOfBirth": "",
                    "mothersMaidenName": "",
                    "fathersName": "",
                    "mothersPlaceOfBirth": "",
                    "fathersPlaceOfBirth": "",
                    "parentsMarriedAtBirth": "",
                    "numberOfChildrenBornInSCToMother": "",
                    "diffNameAtBirth":""
                },
                "fees":{
                    "searchFee": "",
                    "eachAdditionalCopy": "",
                    "expediteFee": "",
                    "totalFees": ""
                } 
              }
            """ 

            response = invoke_claude_3_multimodal(prompt, base64_image)
            print(response)
            
            if response['content'][0]['text'] != "{}":
                send_message_to_sqs(response)
            else:
                print(f"Bedrock model invocation failed. Please verify that the uploaded image is a birth certificate application form.")
        except Exception as e:
            print(f"Error: {str(e)}")
    else:
        print(f"Skipping non-JPG file: {object_key}")

def invoke_claude_3_multimodal(prompt, base64_image_data):
    request_body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 2048,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": prompt,
                    },
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/png",
                            "data": base64_image_data,
                        },
                    },
                ],
            }
        ],
    }

    try:
        response = bedrock.invoke_model(modelId=MODEL_ID, body=json.dumps(request_body))
        return json.loads(response['body'].read())
    except bedrock.exceptions.ClientError as err:
        print(f"Couldn't invoke Claude 3 Sonnet. Here's why: {err.response['Error']['Code']}: {err.response['Error']['Message']}")
        raise

def send_message_to_sqs(message_body):
    try:
        sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(message_body))
    except sqs.exceptions.ClientError as e:
        print(f"Error sending message to SQS: {e.response['Error']['Code']}: {e.response['Error']['Message']}")
