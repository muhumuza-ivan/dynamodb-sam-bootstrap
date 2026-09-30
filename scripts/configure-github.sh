#!/usr/bin/env bash
# Creates the `development` and `production` GitHub environments on the app
# repo and stores the bootstrap stack outputs as environment variables, which
# the app repo's pipelines read via ${{ vars.* }}.
#
# Requires: gh (authenticated), aws.
# Usage: GITHUB_ORG=<org-or-user> ./scripts/configure-github.sh
set -euo pipefail

: "${GITHUB_ORG:?Set GITHUB_ORG to the GitHub user/org that owns the app repo}"
REGION="${AWS_REGION:-eu-west-1}"
APP_NAME="${APP_NAME:-dynamodb-sam}"
APP_REPO="${APP_REPO:-dynamodb-sam}"
REPO="${GITHUB_ORG}/${APP_REPO}"

output() {
  aws cloudformation describe-stacks --region "$REGION" --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text
}

gh variable set AWS_REGION --repo "$REPO" --body "$REGION"

declare -A GH_ENV=([dev]=development [prod]=production)

for env in dev prod; do
  stack="${APP_NAME}-pipeline-${env}"
  gh_env="${GH_ENV[$env]}"
  echo "==> ${REPO} environment '${gh_env}'"

  gh api --method PUT "repos/${REPO}/environments/${gh_env}" >/dev/null

  gh variable set PIPELINE_EXECUTION_ROLE      --repo "$REPO" --env "$gh_env" --body "$(output "$stack" PipelineExecutionRoleArn)"
  gh variable set CLOUDFORMATION_EXECUTION_ROLE --repo "$REPO" --env "$gh_env" --body "$(output "$stack" CloudFormationExecutionRoleArn)"
  gh variable set ARTIFACTS_BUCKET             --repo "$REPO" --env "$gh_env" --body "$(output "$stack" ArtifactsBucketName)"
done

echo
echo "Done. Optionally add required reviewers to 'production' under"
echo "https://github.com/${REPO}/settings/environments for a manual approval gate."
