import { App } from 'aws-cdk-lib';
import { Match, Template } from 'aws-cdk-lib/assertions';
import { SecureFileIntakeStack } from '../lib/secure-file-intake-stack';

// Infrastructure tests: assert security and reliability guarantees on the
// synthesized CloudFormation, so a careless change fails CI before deploy.
const template = Template.fromStack(new SecureFileIntakeStack(new App(), 'Test', { alertEmail: 'alerts@example.com' }));

describe('SecureFileIntakeStack', () => {
  test('bucket is encrypted, versioned, and blocks all public access', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketEncryption: Match.objectLike({
        ServerSideEncryptionConfiguration: [Match.objectLike({ ServerSideEncryptionByDefault: { SSEAlgorithm: 'AES256' } })],
      }),
      VersioningConfiguration: { Status: 'Enabled' },
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true,
      },
    });
  });

  test('bucket policy denies non-TLS requests', () => {
    template.hasResourceProperties('AWS::S3::BucketPolicy', {
      PolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({ Effect: 'Deny', Condition: { Bool: { 'aws:SecureTransport': 'false' } } }),
        ]),
      }),
    });
  });

  test('validator runs on Node 22 with a failure destination', () => {
    template.hasResourceProperties('AWS::Lambda::Function', { Runtime: 'nodejs22.x', Handler: 'index.handler' });
    template.hasResourceProperties('AWS::Lambda::EventInvokeConfig', {
      MaximumRetryAttempts: 2,
      DestinationConfig: { OnFailure: { Destination: Match.anyValue() } },
    });
  });

  test('three alarms notify the SNS topic', () => {
    template.resourceCountIs('AWS::CloudWatch::Alarm', 3);
    template.hasResourceProperties('AWS::SNS::Subscription', { Protocol: 'email', Endpoint: 'alerts@example.com' });
  });

  test('validator can only delete from inbound/', () => {
    const policies = template.findResources('AWS::IAM::Policy');
    const deleteStatements = Object.values(policies)
      .flatMap((p: any) => p.Properties.PolicyDocument.Statement)
      .filter((s: any) => ([] as string[]).concat(s.Action).some((a) => a.startsWith('s3:DeleteObject')));
    expect(deleteStatements.length).toBeGreaterThan(0);
    expect(JSON.stringify(deleteStatements)).toContain('/inbound/*');
    expect(JSON.stringify(deleteStatements)).not.toContain('/processed/*');
  });
});
