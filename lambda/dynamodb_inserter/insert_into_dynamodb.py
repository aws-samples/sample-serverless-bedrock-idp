import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
table_name = os.environ['TABLE_NAME']    

def lambda_handler(event, context):
    data = json.loads(event['Records'][0]['body'])['content'][0]['text']
    event_id = event['Records'][0]['messageId']
    data = json.loads(data)

    birth_certificates_table = dynamodb.Table(table_name)
    
    applicant_details = data.get('applicantDetails', {})
    mailing_address = data.get('mailingAddress', {})
    relation_to_applicant = data.get('relationToApplicant', [])
    birth_certificate_details = data.get('BirthCertificateDetails', {})
    fees = data.get('fees', {})

    try:
        birth_certificates_table.put_item(Item={
            'Id': event_id,
            'applicantName': applicant_details.get('applicantName', ''),
            'dayPhoneNumber': applicant_details.get('dayPhoneNumber', ''),
            'address': applicant_details.get('address', ''),
            'city': applicant_details.get('city', ''),
            'state': applicant_details.get('state', ''),
            'zipCode': applicant_details.get('zipCode', ''),
            'email': applicant_details.get('email', ''),
            'mailingAddressApplicantName': mailing_address.get('mailingAddressApplicantName', ''),
            'mailingAddress': mailing_address.get('mailingAddress', ''),
            'mailingAddressCity': mailing_address.get('mailingAddressCity', ''),
            'mailingAddressState': mailing_address.get('mailingAddressState', ''),
            'mailingAddressZipCode': mailing_address.get('mailingAddressZipCode', ''),
            'relationToApplicant': ', '.join(relation_to_applicant),
            'purposeOfRequest': data.get('purposeOfRequest', ''),
            'nameOnBirthCertificate': birth_certificate_details.get('nameOnBirthCertificate', ''),
            'dateOfBirth': birth_certificate_details.get('dateOfBirth', ''),
            'sex': birth_certificate_details.get('sex', ''),
            'cityOfBirth': birth_certificate_details.get('cityOfBirth', ''),
            'countyOfBirth': birth_certificate_details.get('countyOfBirth', ''),
            'mothersMaidenName': birth_certificate_details.get('mothersMaidenName', ''),
            'fathersName': birth_certificate_details.get('fathersName', ''),
            'mothersPlaceOfBirth': birth_certificate_details.get('mothersPlaceOfBirth', ''),
            'fathersPlaceOfBirth': birth_certificate_details.get('fathersPlaceOfBirth', ''),
            'parentsMarriedAtBirth': birth_certificate_details.get('parentsMarriedAtBirth', ''),
            'numberOfChildrenBornInSCToMother': birth_certificate_details.get('numberOfChildrenBornInSCToMother', ''),
            'diffNameAtBirth': birth_certificate_details.get('diffNameAtBirth', ''),
            'searchFee': fees.get('searchFee', ''),
            'eachAdditionalCopy': fees.get('eachAdditionalCopy', ''),
            'expediteFee': fees.get('expediteFee', ''),
            'totalFees': fees.get('totalFees', '')
        })
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps(f'Error: {str(e)}')}
            
    return {'statusCode': 200, 'body': json.dumps('Data inserted/updated in DynamoDB successfully!')}
