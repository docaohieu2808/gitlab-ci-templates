#!/usr/bin/env bash
# Run one fixture project through gitlab-ci-local with the templates included locally.
#
#   tests/run-fixture-with-gitlab-ci-local.sh <fixture> <auto-pipeline|component> <pass|fail> [preview]
#
# <fixture>  a directory under tests/fixtures/ (node-good, python-bad, ...)
# mode       auto-pipeline = include /auto-pipeline.yml
#            component     = include templates/auto-detect-build-test-deploy/template.yml with inputs
# expected   pass = the pipeline must succeed, fail = it must fail (proves a failing
#            test turns the pipeline red instead of being swallowed)
# preview    only print the merged, interpolated YAML (no Docker needed)
#
# Requires gitlab-ci-local on PATH (npm i -g gitlab-ci-local) and, unless previewing, Docker.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="${1:?fixture name}"
mode="${2:?auto-pipeline|component}"
expect="${3:?pass|fail}"
action="${4:-run}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -r "$repo/tests/fixtures/$fixture/." "$work/"
cp "$repo/auto-pipeline.yml" "$work/"
mkdir -p "$work/templates"
cp -r "$repo/templates/auto-detect-build-test-deploy" "$work/templates/"

case "$mode" in
  auto-pipeline)
    cat > "$work/.gitlab-ci.yml" <<'EOF'
include:
  - local: /auto-pipeline.yml

variables:
  SAST_ENABLED: "false"
  DEPENDENCY_SCAN_ENABLED: "false"
EOF
    ;;
  component)
    cat > "$work/.gitlab-ci.yml" <<'EOF'
include:
  - local: /templates/auto-detect-build-test-deploy/template.yml
    inputs:
      sast_enabled: "false"
      dependency_scan_enabled: "false"
EOF
    ;;
  *) echo "unknown mode: $mode" >&2; exit 2 ;;
esac

cd "$work"
git init -q -b main
git add -A
git -c user.name=ci -c user.email=ci@example.com commit -q -m "fixture $fixture"

if [ "$action" = "preview" ]; then
  gitlab-ci-local --preview
  exit 0
fi

set +e
gitlab-ci-local 2>&1 | tee "$work/run.log"
status="${PIPESTATUS[0]}"
set -e

if [ "$expect" = "pass" ] && [ "$status" -ne 0 ]; then
  echo "FAIL: $fixture/$mode should have passed but exited $status" >&2
  exit 1
fi
if [ "$expect" = "fail" ] && [ "$status" -eq 0 ]; then
  echo "FAIL: $fixture/$mode should have failed but the pipeline went green" >&2
  exit 1
fi
echo "OK: $fixture/$mode ended as expected ($expect, exit $status)"
