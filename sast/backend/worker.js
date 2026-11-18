// ScanFlow worker.
// Pulls scan jobs from SQS, downloads the uploaded zip from S3, runs the
// provided SAST scanner (scanDirectory from scanner.js), saves the report to S3,
// and keeps the job's status up to date in DynamoDB.

import {
  SQSClient,
  ReceiveMessageCommand,
  DeleteMessageCommand,
  ChangeMessageVisibilityCommand,
} from '@aws-sdk/client-sqs';
import { S3Client, GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import AdmZip from 'adm-zip';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { scanDirectory } from './scanner.js';

// Settings come from environment variables (set by Terraform in the ECS task definition).
const { QUEUE_URL, UPLOADS_BUCKET, REPORTS_BUCKET, JOBS_TABLE } = process.env;
const MAX_ATTEMPTS = 3; // must match maxReceiveCount on the queue's redrive policy

for (const [name, value] of Object.entries({ QUEUE_URL, UPLOADS_BUCKET, REPORTS_BUCKET, JOBS_TABLE })) {
  if (!value) {
    console.error(`Missing environment variable ${name}`);
    process.exit(1);
  }
}

const sqs = new SQSClient({});
const s3 = new S3Client({});
const db = DynamoDBDocumentClient.from(new DynamoDBClient({}));

// One JSON line per log entry, so CloudWatch Logs Insights can search by field.
function log(msg, extra = {}) {
  console.log(JSON.stringify({ time: new Date().toISOString(), msg, ...extra }));
}

// Uploads must look like uploads/{jobId}/project.zip
function jobIdFromKey(key) {
  const parts = key.split('/');
  if (parts.length !== 3 || parts[0] !== 'uploads' || parts[2] !== 'project.zip') return null;
  if (!/^[A-Za-z0-9_-]+$/.test(parts[1])) return null;
  return parts[1];
}

// Update the job's row in DynamoDB. UpdateCommand creates the row if it doesn't exist yet.
async function setStatus(jobId, status, fields = {}) {
  const updates = { status, updatedAt: new Date().toISOString(), ...fields };
  const names = {};
  const values = {};
  const sets = [];
  for (const [field, value] of Object.entries(updates)) {
    names[`#${field}`] = field;
    values[`:${field}`] = value;
    sets.push(`#${field} = :${field}`);
  }
  await db.send(new UpdateCommand({
    TableName: JOBS_TABLE,
    Key: { jobId },
    UpdateExpression: `SET ${sets.join(', ')}`,
    ExpressionAttributeNames: names,
    ExpressionAttributeValues: values,
  }));
}

// Unzip safely: refuse any entry that would land outside our scan folder ("zip slip").
function extractZip(buffer, dir) {
  const zip = new AdmZip(buffer); // throws if the file is not a valid zip
  for (const entry of zip.getEntries()) {
    const target = path.resolve(dir, entry.entryName);
    if (!target.startsWith(dir + path.sep)) {
      throw new Error(`Unsafe path in zip: ${entry.entryName}`);
    }
  }
  zip.extractAllTo(dir, true);
}

// Same counting logic as the /scan/directory route in server.js,
// plus trimming the temporary folder from every file path.
function buildReport(jobId, dir, results) {
  const files = {};
  for (const [file, vulnerabilities] of Object.entries(results)) {
    const relative = path.relative(dir, file);
    files[relative] = vulnerabilities.map((v) => ({ ...v, file: relative }));
  }
  const all = Object.values(files).flat();
  const summary = {
    filesScanned: Object.keys(files).length,
    totalVulnerabilities: all.length,
    high: all.filter((v) => v.severity === 'HIGH').length,
    medium: all.filter((v) => v.severity === 'MEDIUM').length,
    low: all.filter((v) => v.severity === 'LOW').length,
  };
  return { jobId, scannedAt: new Date().toISOString(), summary, results: files };
}

async function processUpload(key) {
  const jobId = jobIdFromKey(key);
  if (!jobId) {
    log('Skipping upload with unexpected key', { key });
    return;
  }

  // Safe to run twice: if this job already finished, do nothing.
  const existing = await db.send(new GetCommand({ TableName: JOBS_TABLE, Key: { jobId } }));
  if (existing.Item?.status === 'COMPLETED') {
    log('Job already completed, skipping', { jobId });
    return;
  }

  const start = Date.now();
  await setStatus(jobId, 'RUNNING', { uploadKey: key, startedAt: new Date().toISOString() });
  log('Scan started', { jobId, key });

  const dir = path.resolve(os.tmpdir(), `scan-${jobId}`);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });

  try {
    const object = await s3.send(new GetObjectCommand({ Bucket: UPLOADS_BUCKET, Key: key }));
    const buffer = Buffer.from(await object.Body.transformToByteArray());
    extractZip(buffer, dir);

    const report = buildReport(jobId, dir, scanDirectory(dir));
    const reportKey = `reports/${jobId}/report.json`;
    await s3.send(new PutObjectCommand({
      Bucket: REPORTS_BUCKET,
      Key: reportKey,
      Body: JSON.stringify(report, null, 2),
      ContentType: 'application/json',
    }));

    const durationMs = Date.now() - start;
    await setStatus(jobId, 'COMPLETED', {
      reportKey,
      summary: report.summary,
      durationMs,
      completedAt: new Date().toISOString(),
    });
    log('Scan completed', { jobId, ...report.summary, durationMs });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

async function deleteMessage(message) {
  await sqs.send(new DeleteMessageCommand({ QueueUrl: QUEUE_URL, ReceiptHandle: message.ReceiptHandle }));
}

async function handleMessage(message) {
  const attempt = Number(message.Attributes?.ApproximateReceiveCount ?? 1);
  let keys = [];

  try {
    const body = JSON.parse(message.Body);

    // S3 sends this once when the notification is set up. There is no file to scan.
    if (body.Event === 's3:TestEvent') {
      log('Ignoring S3 test event');
      await deleteMessage(message);
      return;
    }

    // S3 encodes keys in the event (spaces become +), so decode them.
    keys = (body.Records ?? []).map((r) => decodeURIComponent(r.s3.object.key.replace(/\+/g, ' ')));
    for (const key of keys) {
      await processUpload(key);
    }
    await deleteMessage(message);
  } catch (err) {
    log('Scan failed', { attempt, keys, error: err.message });

    if (attempt >= MAX_ATTEMPTS) {
      for (const key of keys) {
        const jobId = jobIdFromKey(key);
        if (jobId) await setStatus(jobId, 'FAILED', { error: err.message, attempts: attempt });
      }
      log('Giving up after max attempts, SQS will move the message to the dead-letter queue', { keys });
    }

    // Make the message visible again right away, so the retry (or the move to the DLQ)
    // happens in seconds instead of waiting for the 15 minute visibility timeout.
    await sqs.send(new ChangeMessageVisibilityCommand({
      QueueUrl: QUEUE_URL,
      ReceiptHandle: message.ReceiptHandle,
      VisibilityTimeout: 0,
    }));
  }
}

async function main() {
  log('Worker started', { queue: QUEUE_URL });
  while (true) {
    try {
      const response = await sqs.send(new ReceiveMessageCommand({
        QueueUrl: QUEUE_URL,
        MaxNumberOfMessages: 1,
        WaitTimeSeconds: 20, // long polling: wait up to 20s for a message
        MessageSystemAttributeNames: ['ApproximateReceiveCount'],
      }));
      for (const message of response.Messages ?? []) {
        await handleMessage(message);
      }
    } catch (err) {
      log('Error while polling the queue', { error: err.message });
      await new Promise((resolve) => setTimeout(resolve, 5000));
    }
  }
}

main();
