import * as path from 'path';
import { Duration, RemovalPolicy, Stack, StackProps, CfnOutput } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as nodejs from 'aws-cdk-lib/aws-lambda-nodejs';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subs from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cwActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as destinations from 'aws-cdk-lib/aws-lambda-destinations';
import * as logs from 'aws-cdk-lib/aws-logs';

export interface SecureFileIntakeStackProps extends StackProps {
  /** Optional email address for alarm notifications. */
  alertEmail?: string;
}

export class SecureFileIntakeStack extends Stack {
  constructor(scope: Construct, id: string, props: SecureFileIntakeStackProps = {}) {
    super(scope, id, props);

    // ---------- Storage: one locked-down bucket with prefixes ----------
    // inbound/ (partner drop zone) -> processed/ or quarantine/, plus acks/
    const bucket = new s3.Bucket(this, 'IntakeBucket', {
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: true,
      objectOwnership: s3.ObjectOwnership.BUCKET_OWNER_ENFORCED,
      lifecycleRules: [
        { id: 'expire-processed', prefix: 'processed/', expiration: Duration.days(30) },
        { id: 'expire-acks', prefix: 'acks/', expiration: Duration.days(30) },
        { id: 'expire-old-versions', noncurrentVersionExpiration: Duration.days(7) },
      ],
      // Lab settings so `cdk destroy` leaves nothing behind (and nothing billing).
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // ---------- Failure handling ----------
    const dlq = new sqs.Queue(this, 'ValidatorDLQ', {
      retentionPeriod: Duration.days(14),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
      enforceSSL: true,
    });

    // ---------- Validator Lambda (TypeScript, bundled with esbuild) ----------
    const validator = new nodejs.NodejsFunction(this, 'Validator', {
      entry: path.join(__dirname, '..', 'lambda', 'handler.ts'),
      handler: 'handler',
      runtime: lambda.Runtime.NODEJS_22_X,
      architecture: lambda.Architecture.ARM_64,
      memorySize: 256,
      timeout: Duration.seconds(60),
      retryAttempts: 2,
      onFailure: new destinations.SqsDestination(dlq),
      logGroup: new logs.LogGroup(this, 'ValidatorLogs', {
        retention: logs.RetentionDays.TWO_WEEKS,
        removalPolicy: RemovalPolicy.DESTROY,
      }),
      bundling: { minify: true, sourceMap: true, externalModules: ['@aws-sdk/*'] },
    });

    // Least privilege: read/delete only inbound/, write only to the output prefixes.
    bucket.grantRead(validator, 'inbound/*');
    bucket.grantDelete(validator, 'inbound/*');
    bucket.grantPut(validator, 'processed/*');
    bucket.grantPut(validator, 'quarantine/*');
    bucket.grantPut(validator, 'acks/*');

    bucket.addEventNotification(s3.EventType.OBJECT_CREATED, new s3n.LambdaDestination(validator), { prefix: 'inbound/' });

    // ---------- Alerting ----------
    const alerts = new sns.Topic(this, 'IntakeAlerts', { displayName: 'Secure File Intake alerts' });
    if (props.alertEmail) alerts.addSubscription(new subs.EmailSubscription(props.alertEmail));
    const notify = new cwActions.SnsAction(alerts);

    const alarms: cloudwatch.Alarm[] = [
      new cloudwatch.Alarm(this, 'ValidatorErrors', {
        alarmDescription: 'Validator Lambda threw an error (file may be stuck in inbound/)',
        metric: validator.metricErrors({ period: Duration.minutes(5) }),
        threshold: 1,
        evaluationPeriods: 1,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      }),
      new cloudwatch.Alarm(this, 'FilesRejected', {
        alarmDescription: 'A partner file failed validation and was quarantined',
        metric: new cloudwatch.Metric({
          namespace: 'SecureFileIntake',
          metricName: 'FilesRejected',
          statistic: 'Sum',
          period: Duration.minutes(5),
        }),
        threshold: 1,
        evaluationPeriods: 1,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      }),
      new cloudwatch.Alarm(this, 'DeadLetters', {
        alarmDescription: 'Events exhausted retries and landed in the DLQ',
        metric: dlq.metricApproximateNumberOfMessagesVisible({ period: Duration.minutes(5) }),
        threshold: 1,
        evaluationPeriods: 1,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      }),
    ];
    alarms.forEach((a) => a.addAlarmAction(notify));

    // ---------- Dashboard ----------
    new cloudwatch.Dashboard(this, 'IntakeDashboard', {
      dashboardName: 'SecureFileIntake',
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Files accepted vs rejected',
            left: ['FilesAccepted', 'FilesRejected'].map(
              (m) => new cloudwatch.Metric({ namespace: 'SecureFileIntake', metricName: m, statistic: 'Sum', period: Duration.minutes(5) }),
            ),
          }),
          new cloudwatch.GraphWidget({
            title: 'Validator errors and duration',
            left: [validator.metricErrors()],
            right: [validator.metricDuration()],
          }),
        ],
        [new cloudwatch.AlarmStatusWidget({ title: 'Alarms', alarms })],
      ],
    });

    new CfnOutput(this, 'BucketName', { value: bucket.bucketName });
    new CfnOutput(this, 'AlertTopicArn', { value: alerts.topicArn });
  }
}
