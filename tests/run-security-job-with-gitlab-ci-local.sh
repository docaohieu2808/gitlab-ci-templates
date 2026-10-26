#!/usr/bin/env bash
# Run ONE security job of the templates against a fixture with gitlab-ci-local and check that it
# passes or fails for the right reason.
#
#   tests/run-security-job-with-gitlab-ci-local.sh <fixture> <job> <pass|fail> [--inject-secret]
#
# <job>             secret-detection:gitleaks | dependency-scan:trivy
# --inject-secret   commits a fake AWS access key, generated here at run time, into the fixture copy.
#                   The key is never stored in this repository (so no scanner or push protection
#                   trips on the repo itself) and is never printed.
#
# A "fail" case only counts when the job itself is reported as FAIL *and* the scanner's own finding
# marker is in the log, so a Docker pull error or a crash cannot turn a negative test green.
# Requires gitlab-ci-local on PATH (npm i -g gitlab-ci-local) and Docker.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="${1:?fixture name}"
job="${2:?job name}"
expect="${3:?pass|fail}"
inject="${4:-}"

case "$job" in
  secret-detection:gitleaks) finding='leaks found: [1-9]' ;;
  dependency-scan:trivy)     finding='CVE-[0-9]{4}-[0-9]+' ;;
  *) echo "unknown job: $job" >&2; exit 2 ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -r "$repo/tests/fixtures/$fixture/." "$work/"
cp "$repo/auto-pipeline.yml" "$work/"
cat > "$work/.gitlab-ci.yml" <<'YAML'
include:
  - local: /auto-pipeline.yml

variables:
  SAST_ENABLED: "false"
YAML

if [ "$inject" = "--inject-secret" ]; then
  # AKIA + 16 characters of the base32 alphabet is the shape Gitleaks' aws-access-token rule matches.
  key="AKIA$(python3 -I -c 'import secrets; print("".join(secrets.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567") for _ in range(16)))')"
  mkdir -p "$work/config"
  printf 'AWS_ACCESS_KEY_ID=%s\n' "$key" > "$work/config/deploy.env"
  unset key
fi

cd "$work"
git init -q -b main
git add -A
git -c user.name=ci -c user.email=ci@example.com commit -q -m "fixture $fixture"

set +e
gitlab-ci-local "$job" 2>&1 | sed -u 's/\x1b\[[0-9;]*[A-Za-z]//g' | tee "$work/run.log"
status="${PIPESTATUS[0]}"
set -e

if [ "$expect" = "pass" ]; then
  if [ "$status" -ne 0 ]; then
    echo "FAIL: $job on $fixture should have passed but exited $status" >&2; exit 1
  fi
  if grep -Eq "$finding" "$work/run.log"; then
    echo "FAIL: $job on $fixture passed although the log shows a finding" >&2; exit 1
  fi
else
  if [ "$status" -eq 0 ]; then
    echo "FAIL: $job on $fixture should have failed but went green" >&2; exit 1
  fi
  if ! grep -Eq "FAIL[[:space:]]+${job}" "$work/run.log"; then
    echo "FAIL: $job on $fixture exited $status but not as a failed job (infrastructure error?)" >&2; exit 1
  fi
  if ! grep -Eq "$finding" "$work/run.log"; then
    echo "FAIL: $job on $fixture failed without the scanner reporting a finding ($finding)" >&2; exit 1
  fi
fi
echo "OK: $job on $fixture${inject:+ $inject} ended as expected ($expect, exit $status)"
