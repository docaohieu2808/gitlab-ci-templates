#!/usr/bin/env bash
# Two-step test of the dynamic monorepo pipeline with gitlab-ci-local:
#   1. run the generator job of dynamic/...yml against a monorepo fixture
#   2. run the generated child pipeline (gitlab-ci-local cannot follow `trigger:`)
#
#   tests/run-monorepo-fixture-with-gitlab-ci-local.sh <monorepo-good|monorepo-bad> <pass|fail>
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="${1:?fixture name}"
expect="${2:?pass|fail}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -r "$repo/tests/fixtures/$fixture/." "$work/"
mkdir -p "$work/dynamic"
cp "$repo/dynamic/generate-pipeline-from-monorepo-service-detection.yml" "$work/dynamic/"
cat > "$work/.gitlab-ci.yml" <<'YAML'
include:
  - local: /dynamic/generate-pipeline-from-monorepo-service-detection.yml
YAML

cd "$work"
git init -q -b main
git add -A
git -c user.name=ci -c user.email=ci@example.com commit -q -m "fixture $fixture"

echo "== step 0: on a feature branch only the changed service is selected"
git checkout -q -b feature
echo "// touched" >> api/index.js
git -c user.name=ci -c user.email=ci@example.com commit -q -am "touch api"
gitlab-ci-local generate-monorepo-pipeline --variable CI_COMMIT_BEFORE_SHA="$(git rev-parse HEAD~1)"
changed_only=".gitlab-ci-local/artifacts/generate-monorepo-pipeline/generated-pipeline.yml"
grep -q '^ci:api:' "$changed_only"
if grep -q '^ci:worker:' "$changed_only"; then echo "FAIL: unchanged service was selected" >&2; exit 1; fi
git checkout -q main
git checkout -q -- .
rm -rf .gitlab-ci-local

echo "== step 1: generate the child pipeline"
gitlab-ci-local generate-monorepo-pipeline
generated=".gitlab-ci-local/artifacts/generate-monorepo-pipeline/generated-pipeline.yml"
test -s "$generated"
grep -q '^ci:api:' "$generated"
grep -q '^ci:worker:' "$generated"

echo "== step 2: run the generated pipeline"
mkdir "$work/child"
cp -r "$work/api" "$work/worker" "$work/child/"
cp "$generated" "$work/child/.gitlab-ci.yml"
cd "$work/child"
git init -q -b main
git add -A
git -c user.name=ci -c user.email=ci@example.com commit -q -m "child"

set +e
gitlab-ci-local 2>&1 | tee "$work/run.log"
status="${PIPESTATUS[0]}"
set -e

if [ "$expect" = "pass" ] && [ "$status" -ne 0 ]; then
  echo "FAIL: $fixture should have passed but exited $status" >&2; exit 1
fi
if [ "$expect" = "fail" ] && [ "$status" -eq 0 ]; then
  echo "FAIL: $fixture should have failed but the generated pipeline went green" >&2; exit 1
fi
echo "OK: $fixture ended as expected ($expect, exit $status)"
