import { S3Client, GetObjectCommand, CopyObjectCommand, DeleteObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import type { S3Event } from 'aws-lambda';
import { validateCsv } from './validate';

const s3 = new S3Client({});

const INBOUND = 'inbound/';
const PROCESSED = 'processed/';
const QUARANTINE = 'quarantine/';
const ACKS = 'acks/';

/**
 * Emits a CloudWatch Embedded Metric Format log line, so metrics appear in
 * CloudWatch without extra API calls. Never logs file contents (may hold PHI).
 */
function emitMetric(name: 'FilesAccepted' | 'FilesRejected', partner: string) {
  console.log(
    JSON.stringify({
      _aws: {
        Timestamp: Date.now(),
        CloudWatchMetrics: [{ Namespace: 'SecureFileIntake', Dimensions: [[]], Metrics: [{ Name: name, Unit: 'Count' }] }],
      },
      [name]: 1,
      partner,
    }),
  );
}

export async function handler(event: S3Event): Promise<void> {
  for (const record of event.Records) {
    const bucket = record.s3.bucket.name;
    const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, ' '));
    if (!key.startsWith(INBOUND)) continue;

    // inbound/<partner>/<file>  ->  partner name used for routing and metrics
    const relative = key.slice(INBOUND.length);
    const partner = relative.includes('/') ? relative.split('/')[0] : 'unknown';

    const obj = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    const body = (await obj.Body?.transformToString('utf-8')) ?? '';
    const result = validateCsv(body, obj.ContentLength ?? Buffer.byteLength(body));

    const destPrefix = result.valid ? PROCESSED : QUARANTINE;
    const destKey = `${destPrefix}${relative}`;

    await s3.send(
      new CopyObjectCommand({
        Bucket: bucket,
        Key: destKey,
        CopySource: `${bucket}/${encodeURIComponent(key).replace(/%2F/g, '/')}`,
        ServerSideEncryption: 'AES256',
      }),
    );

    // Acknowledgement file the partner (or a downstream job) can pick up,
    // similar to an X12 999 or HL7 ACK: one verdict per received file.
    const ack = {
      file: relative,
      partner,
      status: result.valid ? 'ACCEPTED' : 'REJECTED',
      rowCount: result.rowCount,
      errors: result.errors,
      processedAt: new Date().toISOString(),
    };
    await s3.send(
      new PutObjectCommand({
        Bucket: bucket,
        Key: `${ACKS}${relative}.ack.json`,
        Body: JSON.stringify(ack, null, 2),
        ContentType: 'application/json',
        ServerSideEncryption: 'AES256',
      }),
    );

    await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));

    emitMetric(result.valid ? 'FilesAccepted' : 'FilesRejected', partner);
    console.log(JSON.stringify({ level: 'INFO', msg: 'file processed', file: relative, status: ack.status, rowCount: result.rowCount, errorCount: result.errors.length }));
  }
}
