# GitLab CI Templates — Zero-Config Auto Pipeline

A self-contained GitLab CI template that auto-detects language, builds, tests, scans, and deploys any project. One `include:` line is all you need. Supports **22 deploy targets**.

## How it works

```
.gitlab-ci.yml (include auto-pipeline.yml)
        ↓
detect:language    — inspect repo files, output DETECTED_LANGUAGE
        ↓
build:app          — run language-specific build command
        ↓
test:app + lint    — run tests and linter in parallel
        ↓
security-scan      — SAST + dependency scan + secret detection + container scan
        ↓
docker:build-push  — build image, push to $CI_REGISTRY (if DEPLOY_TARGET set)
        ↓
deploy:<target>    — activate job matching $DEPLOY_TARGET value
```

All jobs are inlined in `auto-pipeline.yml` — no nested `include: project:` chains that break on private runners.

---

## Levels

| Level | What you get |
|-------|-------------|
| **L1** | One `include:` line. Auto-detect language, build, test, lint, security scan. |
| **L2** | Set `DEPLOY_TARGET` + `DEPLOY_HOST` CI/CD variables in GitLab UI. Auto-deploy on push. |
| **L3** | Override `BUILD_CMD`, `TEST_CMD`, language versions, Docker registry via CI/CD variables. |
| **L4** | Use individual job templates from `jobs/` directory to compose custom pipelines. |
| **MAX** | Use `dynamic/` and `child-pipelines/` for monorepo service-detection with per-service pipelines. |

---

## Prerequisites

- GitLab CI (SaaS or self-hosted, any runner type)
- For Docker builds: runner with Docker-in-Docker or `docker` executor
- For SSH deploy targets: `DEPLOY_KEY` CI/CD variable (SSH private key, masked)
- For AWS targets: `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` CI/CD variables

---

## Installation

No installation needed. Reference the template via `include:` in your project.

---

## Quick Start

### Zero config (L1) — detect + build + test only

```yaml
# .gitlab-ci.yml
include:
  - project: 'cicd-auto-pipeline/gitlab-ci-templates'
    ref: master
    file: '/auto-pipeline.yml'
```

### With deploy (L2) — set variables in GitLab CI/CD settings

```yaml
# .gitlab-ci.yml
include:
  - project: 'cicd-auto-pipeline/gitlab-ci-templates'
    ref: master
    file: '/auto-pipeline.yml'

variables:
  DEPLOY_TARGET: ssh-build
  DEPLOY_HOST: app.example.com
  DEPLOY_USER: deploy
  DEPLOY_PATH: /opt/myapp
  # DEPLOY_KEY: set in GitLab CI/CD Variables (masked, SSH private key)
```

### Override build/test commands (L3)

```yaml
include:
  - project: 'cicd-auto-pipeline/gitlab-ci-templates'
    ref: master
    file: '/auto-pipeline.yml'

variables:
  DEPLOY_TARGET: s3-cloudfront
  S3_BUCKET: my-frontend-bucket
  CLOUDFRONT_DISTRIBUTION_ID: EXXXXXXXXXX
  BUILD_CMD: npm run build:prod
  NODE_VERSION: "20"
```

---

## Deploy Targets

Set `DEPLOY_TARGET` to one of:

| Value | Description |
|-------|-------------|
| `ssh-build` | SSH → git pull → build on server → atomic swap → restart service |
| `ssh-deploy` | rsync artifacts → restart service via SSH |
| `docker-compose` | SSH → docker compose pull & up |
| `rsync` | Plain rsync to remote path |
| `s3` | AWS S3 sync |
| `s3-cloudfront` | AWS S3 sync + CloudFront invalidation |
| `k8s` | `kubectl set image` on existing deployment |
| `k8s-manifest` | `kubectl apply` manifest files |
| `helm` | `helm upgrade --install` |
| `vercel` | Vercel CLI deploy |
| `netlify` | Netlify CLI deploy |
| `ftp` | lftp FTP/FTPS upload |
| `gcs` | Google Cloud Storage gsutil rsync |
| `firebase` | Firebase Hosting deploy |
| `heroku` | Heroku container push & release |
| `ecs` | AWS ECS force new deployment |
| `lambda` | AWS Lambda function update |
| `azure-webapp` | Azure CLI `az webapp deploy` |
| `capistrano` | `cap <stage> deploy` |
| `ansible` | `ansible-playbook` |
| `pages` | GitLab Pages (artifacts to `public/`) |
| `custom` | Run `$CUSTOM_DEPLOY_CMD` |

---

## Configuration Reference

Set these as CI/CD variables in GitLab (project or group level):

### Core

| Variable | Default | Description |
|----------|---------|-------------|
| `DEPLOY_TARGET` | `""` | Deploy target (see table above). Empty = skip deploy. |
| `BUILD_CMD` | auto | Override auto-detected build command |
| `TEST_CMD` | auto | Override auto-detected test command |
| `LINT_CMD` | auto | Override auto-detected lint command |

### Language versions

| Variable | Default |
|----------|---------|
| `NODE_VERSION` | `20` |
| `JAVA_VERSION` | `17` |
| `GO_VERSION` | `1.22` |
| `PYTHON_VERSION` | `3.12` |
| `PHP_VERSION` | `8.3` |
| `RUST_VERSION` | `stable` |
| `DOTNET_VERSION` | `8.0` |

### Docker

| Variable | Default | Description |
|----------|---------|-------------|
| `DOCKER_IMAGE` | auto | Image name (defaults to `$CI_REGISTRY_IMAGE`) |
| `DOCKER_TAG` | `$CI_COMMIT_SHORT_SHA` | Image tag |
| `DOCKER_REGISTRY` | `$CI_REGISTRY` | Registry host |
| `DOCKER_REGISTRY_USER` | `$CI_REGISTRY_USER` | Registry user |
| `DOCKER_REGISTRY_PASSWORD` | `$CI_REGISTRY_PASSWORD` | Registry password |
| `DOCKERFILE_PATH` | `Dockerfile` | Path to Dockerfile |
| `DOCKER_PLATFORMS` | `linux/amd64` | Target platforms |

### SSH deploy

| Variable | Description |
|----------|-------------|
| `DEPLOY_KEY` | SSH private key (masked CI/CD variable) |
| `DEPLOY_HOST` | SSH hostname/IP |
| `DEPLOY_USER` | SSH user (default: `deploy`) |
| `DEPLOY_PATH` | Remote app directory (default: `/opt/app`) |
| `DEPLOY_PORT` | SSH port (default: `22`) |

### Security

| Variable | Default | Description |
|----------|---------|-------------|
| `SECURITY_SCAN_ENABLED` | `true` | Master switch |
| `SAST_ENABLED` | `true` | Static analysis |
| `DEPENDENCY_SCAN_ENABLED` | `true` | Dependency vulnerabilities |
| `SECRET_DETECTION_ENABLED` | `true` | Leaked secrets |
| `CONTAINER_SCAN_ENABLED` | `true` | Container image scan |

---

## Repository Structure

```
gitlab-ci-templates/
├── auto-pipeline.yml                          # Zero-config entry point (all-in-one)
├── jobs/
│   ├── detect-language-and-build-tool.yml
│   ├── build-per-detected-language.yml
│   ├── test-and-lint-per-detected-language.yml
│   ├── docker-build-tag-and-push-to-registry.yml
│   ├── security-sast-dependency-secret-container-scan.yml
│   └── deploy-all-targets-ssh-k8s-helm-s3-vercel-netlify-etc.yml
├── child-pipelines/
│   └── deploy-pipeline.yml
├── dynamic/
│   └── generate-pipeline-from-monorepo-service-detection.yml
├── templates/
│   └── auto-detect-build-test-deploy/
│       └── gitlab-cicd-catalog-component-auto-detect-build-test-deploy.yml
└── examples/
```
