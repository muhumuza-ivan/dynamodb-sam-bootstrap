#!/usr/bin/env bash
# Provisions the SAM pipeline bootstrap resources (OIDC provider + per-env
# artifact buckets and IAM roles). Safe to re-run.
#
# Usage: GITHUB_ORG=<org-or-user> ./scripts/deploy.sh
set -euo pipefail

: "${GITHUB_ORG:?Set GITHUB_ORG to the GitHub user/org that owns the app repo}"
REGION="${AWS_REGION:-eu-west-1}"
APP_NAME="${APP_NAME:-dynamodb-sam}"
APP_REPO="${APP_REPO:-dynamodb-sam}"
OIDC_STACK="github-actions-oidc-provider"

cd "$(dirname "$0")/.."

stack_exists() {
  aws cloudformation describe-stacks --stack-name "$1" --region "$REGION" >/dev/null 2>&1
}

echo "==> OIDC provider stack"
oidc_params=()
if ! stack_exists "$OIDC_STACK"; then
  # First run: only create the provider if the account doesn't already have one.
  # On later runs the previous parameter value is kept, so a provider owned by
  # this stack is never accidentally deleted.
  existing=$(aws iam list-open-id-connect-providers \
    --query "OpenIDConnectProviderList[?ends_with(Arn, 'token.actions.githubusercontent.com')].Arn" \
    --output text)
  if [[ -n "$existing" ]]; then
    echo "    Existing provider found ($existing); not creating a new one."
    oidc_params=(--parameter-overrides CreateOidcProvider=false)
  else
    oidc_params=(--parameter-overrides CreateOidcProvider=true)
  fi
fi
aws cloudformation deploy \
  --region "$REGION" \
  --stack-name "$OIDC_STACK" \
  --template-file templates/github-oidc-provider.yaml \
  --no-fail-on-empty-changeset \
  "${oidc_params[@]}"

declare -A GH_ENV=([dev]=development [prod]=production)

for env in dev prod; do
  stack="${APP_NAME}-pipeline-${env}"
  echo "==> ${stack}"
  aws cloudformation deploy \
    --region "$REGION" \
    --stack-name "$stack" \
    --template-file templates/pipeline-environment.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --tags Application="$APP_NAME" Environment="$env" ManagedBy=dynamodb-sam-bootstrap \
    --parameter-overrides \
      AppName="$APP_NAME" \
      Environment="$env" \
      GitHubOrg="$GITHUB_ORG" \
      GitHubRepo="$APP_REPO" \
      GitHubEnvironmentName="${GH_ENV[$env]}"

  aws cloudformation describe-stacks --region "$REGION" --stack-name "$stack" \
    --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table
done
