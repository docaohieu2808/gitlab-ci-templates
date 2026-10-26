#!/usr/bin/env bash
# The child deploy pipeline cannot deploy without a cluster or a host, but its input
# validation job runs anywhere: it must pass for a complete configuration and fail
# for an incomplete or unknown one.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$repo/child-pipelines/deploy-pipeline.yml" "$work/.gitlab-ci.yml"
cd "$work"
git init -q -b main
git add -A
git -c user.name=ci -c user.email=ci@example.com commit -q -m child

expect_pass() { gitlab-ci-local child:validate-inputs "$@" >/dev/null || { echo "FAIL: expected pass: $*" >&2; exit 1; }; }
expect_fail() { if gitlab-ci-local child:validate-inputs "$@" >/dev/null 2>&1; then echo "FAIL: expected failure: $*" >&2; exit 1; fi; }

expect_pass --variable DEPLOY_TARGET=k8s --variable DEPLOY_IMAGE=registry.example.com/app:1.0.0 --variable K8S_DEPLOYMENT=app
expect_pass --variable DEPLOY_TARGET=helm --variable DEPLOY_IMAGE=registry.example.com/app:1.0.0 --variable HELM_RELEASE=app
expect_fail --variable DEPLOY_TARGET=k8s --variable DEPLOY_IMAGE=registry.example.com/app:1.0.0
expect_fail --variable DEPLOY_TARGET=nonsense
expect_fail
echo "OK: child validate-inputs behaves as expected"
