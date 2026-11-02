#!/usr/bin/env node
import { App, Tags } from 'aws-cdk-lib';
import { SecureFileIntakeStack } from '../lib/secure-file-intake-stack';

const app = new App();

new SecureFileIntakeStack(app, 'SecureFileIntake', {
  // Pass with: cdk deploy -c alertEmail=you@example.com
  alertEmail: app.node.tryGetContext('alertEmail'),
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION ?? 'us-east-1',
  },
});

Tags.of(app).add('project', 'secure-file-intake');
Tags.of(app).add('owner', 'brad-brooks');
