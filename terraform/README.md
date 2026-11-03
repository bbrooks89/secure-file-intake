# Secure File Intake — Terraform edition

The same pipeline as the CDK stack in the repo root, rebuilt in Terraform from three reusable modules. Both versions deploy the same Lambda code (`lambda/handler.ts`), so you can compare the two infrastructure-as-code approaches side by side.

## Layout

```
terraform/
├── main.tf                 Root composition: wires the three modules together
├── variables.tf            Region, name prefix, alert email, retention map
├── outputs.tf
├── versions.tf             Terraform and provider versions, default tags
├── backend.tf.example      Optional S3 remote state with native locking
├── modules/
│   ├── secure_bucket/      Private, encrypted, versioned, TLS-only S3 + lifecycle rules
│   ├── validator_lambda/   Lambda, least-privilege IAM, dead-letter queue, retries
│   └── alerting/           SNS topic, three CloudWatch alarms, dashboard
└── tests/                  `terraform test` suites with a mocked AWS provider
```

## Design notes

- **Reusable modules with validation.** Each module has typed inputs with validation rules (for example, retention must be at least 1 day, Lambda retries must be 0–2, output prefixes must end in `/`).
- **Generated configuration.** Lifecycle rules are built with a `dynamic` block from a `retention_days` map, and the IAM write scope is built with a `for` expression from the list of output prefixes, so adding a prefix updates both automatically.
- **Least privilege.** The function can read and delete only `inbound/*` and write only to `processed/*`, `quarantine/*`, and `acks/*`. The exact scopes are exposed as module outputs and checked by tests.
- **Tested without touching AWS.** The tests use `mock_provider`, so `terraform test` runs in seconds with no credentials and no cost. They check encryption, public access, versioning, lifecycle rules, retry settings, IAM scope, and input validation.
- **Coexists with the CDK stack.** Every resource name starts with `name_prefix` (default `sfi-tf`). Both stacks emit the same `SecureFileIntake` custom metrics, so deploy one at a time for clean alarm testing.
- **Remote state ready.** Local state by default; `backend.tf.example` shows S3 state with native locking for team use.

## Run the tests (no AWS needed)

Requires Terraform 1.7 or newer.

```bash
cd terraform
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform test
```

## Deploy

```bash
npm run build:lambda          # from the repo root: bundles the Lambda into terraform/build/
cd terraform
terraform init
terraform plan  -var="alert_email=you@example.com"
terraform apply -var="alert_email=you@example.com"
```

Confirm the SNS subscription email, then test with the sample files using the `bucket_name` output, exactly as in the main README.

**Clean up:**

```bash
terraform destroy -var="alert_email=you@example.com"
```

## CI

The `Terraform fmt, validate, test` job in `.github/workflows/ci-cd.yml` runs on every push: it bundles the Lambda, checks formatting, validates the configuration, and runs the test suites.
