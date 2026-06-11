# gitlab-ci-templates

**Tier:** GitLab CI advanced (L5-6) — tương đương reusable-workflows nhưng cho GitLab.

**Vị trí trong learning path:**
```
(song song với GitHub Actions track)
gitlab-ci-templates: jobs/ → auto-pipeline.yml → dynamic child pipelines → CI/CD Catalog component
```

## Mục đích

Zero-config CI/CD pipeline cho GitLab: auto-detect ngôn ngữ → build → test → scan → deploy. 3 cách dùng từ đơn giản đến phức tạp:

| Entry point | Dùng khi |
|-------------|---------|
| `auto-pipeline.yml` | Dự án đơn, muốn full pipeline 1 file include |
| `jobs/` | Chọn từng job riêng lẻ (modular) |
| `templates/gitlab-cicd-catalog-component-*.yml` | GitLab 17+ CI/CD Catalog — share pipeline component qua registry |

## Cách dùng

### 1. Auto-pipeline (zero-config)

```yaml
# .gitlab-ci.yml trong project repo của bạn
include:
  - project: 'docaohieu2808/gitlab-ci-templates'
    ref: main
    file: 'auto-pipeline.yml'
```

### 2. Chọn jobs riêng lẻ

```yaml
include:
  - project: 'docaohieu2808/gitlab-ci-templates'
    ref: main
    file: 'jobs/docker-build-tag-and-push-to-registry.yml'
  - project: 'docaohieu2808/gitlab-ci-templates'
    ref: main
    file: 'jobs/deploy-via-ssh.yml'
```

### 3. Dynamic child pipeline (monorepo)

```yaml
# Trigger detect + generate child pipeline per changed service
include:
  - project: 'docaohieu2808/gitlab-ci-templates'
    ref: main
    file: 'dynamic/generate-pipeline-from-monorepo-service-detection.yml'
```

### 4. CI/CD Catalog component (GitLab 17+)

```yaml
include:
  - component: git.example.com/docaohieu2808/gitlab-ci-templates/auto-detect-build-test-deploy@main
```

> Catalog component chỉ chạy khi repo được mirror sang `git.example.com` (self-hosted GitLab).

## Cấu trúc

```
auto-pipeline.yml          # Self-contained full pipeline (1590 dòng)
jobs/                      # Modular jobs — include từng cái
  docker-build-*.yml
  deploy-via-ssh.yml
  ...
dynamic/                   # Dynamic child pipeline cho monorepo
child-pipelines/           # Child pipeline templates
templates/                 # CI/CD Catalog component
examples/                  # Ví dụ .gitlab-ci.yml cho từng use case
```

## Demo points (interview)

- `rules: exists:` thay vì `only/except` deprecated — modern GitLab CI syntax
- Dynamic child pipeline: monorepo detect → generate per-service pipeline → run in parallel
- CI/CD Catalog (GitLab 17+) — tương đương GitHub Marketplace action
- So sánh trực tiếp với reusable-workflows: cùng concept "zero-config auto-detect", khác cú pháp `include:` vs `workflow_call`
- `dotenv` artifacts để pass detected language giữa jobs — GitLab-specific pattern
