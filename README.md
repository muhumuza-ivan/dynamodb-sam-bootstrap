# dynamodb-sam-bootstrap

Infrastructure as code for the one-time resources the
[`dynamodb-sam`](../dynamodb-sam) SAM pipelines depend on. Kept in its own
repo so application deploys can never modify their own permissions.

| Stack | Template | Creates |
|---|---|---|
| `github-actions-oidc-provider` | `templates/github-oidc-provider.yaml` | GitHub Actions OIDC identity provider (skipped if the account already has one) |
| `dynamodb-sam-pipeline-dev` | `templates/pipeline-environment.yaml` | Dev artifact bucket, dev pipeline execution role, dev CloudFormation execution role |
| `dynamodb-sam-pipeline-prod` | `templates/pipeline-environment.yaml` | Same, for prod |

## What it creates for each environment

- **Artifact bucket** `dynamodb-sam-artifacts-<env>-<account>-<region>`: versioned, encrypted, public access blocked, TLS required, artifacts expire after 30 days, and the bucket is kept if the stack is deleted.
- **Pipeline execution role** `dynamodb-sam-<env>-pipeline-exec-role`: GitHub Actions assumes it through OIDC. Only jobs running in the matching GitHub environment (`development` or `production`) of the app repo can assume it. It can use only its own environment's bucket and the `dynamodb-sam-<env>` stack.
- **CloudFormation execution role** `dynamodb-sam-<env>-cfn-exec-role`: passed to `sam deploy --role-arn`. It can manage only DynamoDB tables named `dynamodb-sam-<env>-*`.

## Usage

Prerequisites: AWS CLI v2 with admin-level credentials for the target account,
and `gh` if you want the GitHub environments configured for you. On Windows,
run the scripts in Git Bash.

```bash
export GITHUB_ORG=<your-github-user-or-org>
export AWS_REGION=eu-west-1          # optional, default eu-west-1

./scripts/deploy.sh                  # provision / update AWS resources
./scripts/configure-github.sh        # create GH environments + variables on the app repo
```

Both scripts are idempotent. `APP_NAME` and `APP_REPO` both default to `dynamodb-sam`.

## Teardown

```bash
aws cloudformation delete-stack --stack-name dynamodb-sam-pipeline-dev
aws cloudformation delete-stack --stack-name dynamodb-sam-pipeline-prod
aws cloudformation delete-stack --stack-name github-actions-oidc-provider
# Buckets are retained; empty (all versions) and delete them manually if desired.
```
