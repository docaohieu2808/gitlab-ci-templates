# gitlab-ci-templates

Reusable GitLab CI/CD building blocks, from single jobs up to a CI/CD Catalog component. It is the GitLab counterpart of [reusable-workflows](https://github.com/docaohieu2808/reusable-workflows): the same "detect the language, then lint, build, test, scan, deploy" idea, written with `include:`, `rules:exists`, parent-child pipelines and `spec:inputs`.

```
(parallel to the GitHub Actions track)
L1 jobs/  ->  L2 auto-pipeline.yml  ->  L3 child-pipelines/  ->  L4 dynamic/  ->  L5 CI/CD component
```

## Level map

| Level | What | Files | What it teaches |
|-------|------|-------|-----------------|
| L1 | Job fragments | `jobs/*.yml` | `extends`, hidden jobs, `rules:exists`, `!reference`, one image per language, `entrypoint: [""]` |
| L2 | One-line zero-config pipeline | `auto-pipeline.yml` (generated from `jobs/`) | `include:project` with a pinned `ref`, stages, variables, a single deploy path |
| L3 | Parent-child pipeline | `child-pipelines/deploy-pipeline.yml`, `examples/parent-pipeline-triggers-deploy-child.gitlab-ci.yml` | `trigger:include`, `strategy: depend`, variable forwarding |
| L4 | Dynamic child pipeline | `dynamic/generate-pipeline-from-monorepo-service-detection.yml` | generate YAML at run time, `trigger:include:artifact`, changed-service detection |
| L5 | CI/CD Catalog component | `templates/auto-detect-build-test-deploy/template.yml` (generated from `jobs/`) | `spec:inputs`, `---`, `$[[ inputs.x ]]`, semver release tags |

## What the pipeline does

Stages: `lint`, `build`, `test`, `docker-build`, `security-scan`, `deploy`.

| Stage | Jobs |
|-------|------|
| lint, build, test | one trio per language, present only if its manifest exists: Node.js (npm, pnpm, yarn), Python (pip, PEP 517), Java (Maven, Gradle), Go, PHP (Composer), Rust, .NET. Each runs in its own image. A failing test fails the job. |
| docker-build | `docker-build-and-push` (branches and tags, when a `Dockerfile` exists) |
| security-scan | Semgrep (SAST), Gitleaks (secrets), Trivy (dependencies of every language), and Trivy on the image pushed by `docker-build-and-push` (the scan `needs` that job, so the image always exists) |
| deploy | one job per `DEPLOY_TARGET`: `docker-compose` or `rsync` over SSH, `s3` (+ CloudFront invalidation), `k8s`, `helm`. Default branch only, `resource_group: production`, and exactly one deploy path. |

Defaults (see `jobs/variables.yml`): Node 24, Python 3.14, Go 1.27, Java 25, PHP through `composer:2`, Rust through `rust:1-alpine`, .NET 10, Docker 29, Trivy 0.76.1, Gitleaks 8.30.1, Semgrep 1.182.0, kubectl image `alpine/k8s:1.37.1`, Helm 4.3.1, AWS CLI 2.38.5. They were checked against endoflife.date and the registries on 2026-10-26; Dependabot does not update GitLab YAML, so the weekly CI run is what notices a tag that disappears.

## How to use it

Replace `your-group/gitlab-ci-templates` with the project that hosts this repository and always pin a released tag.

1. L2, zero config: [`examples/zero-config-single-include.gitlab-ci.yml`](examples/zero-config-single-include.gitlab-ci.yml)

   ```yaml
   include:
     - project: 'your-group/gitlab-ci-templates'
       ref: 1.0.0
       file: '/auto-pipeline.yml'
   ```

   Overrides (versions, scan switches, deploy target, replacing one job's command): [`examples/override-versions-and-deploy-target.gitlab-ci.yml`](examples/override-versions-and-deploy-target.gitlab-ci.yml).
2. L1, pick fragments: include `jobs/stages.yml`, `jobs/variables.yml` and the fragments you want (`language-build-test-lint.yml`, `security-scans.yml`, `docker-build-and-push.yml`, `deploy-targets.yml`). The container scan lives in `docker-build-and-push.yml`, next to the job whose image it scans.
3. L3: [`examples/parent-pipeline-triggers-deploy-child.gitlab-ci.yml`](examples/parent-pipeline-triggers-deploy-child.gitlab-ci.yml)
4. L4: [`examples/use-the-dynamic-monorepo-pipeline.gitlab-ci.yml`](examples/use-the-dynamic-monorepo-pipeline.gitlab-ci.yml). One top-level directory per service. Default-branch and tag pipelines run every service; other pipelines run only the services whose files changed.
5. L5, component (GitLab 17.0+, tested against the syntax of 19.x): [`examples/use-the-catalog-component.gitlab-ci.yml`](examples/use-the-catalog-component.gitlab-ci.yml). Every variable of `jobs/variables.yml` is an input, named in lower case (`node_version`, `deploy_target`, ...), all optional.

### Secrets

Nothing sensitive lives in this repository. Deploy jobs read `DEPLOY_SSH_PRIVATE_KEY`, `DEPLOY_KNOWN_HOSTS` (take it once with `ssh-keyscan -p PORT HOST` and review it; the pipeline never scans for host keys), AWS credentials (or OIDC through `id_tokens`) and `KUBECONFIG` (type "File") from masked, protected CI/CD variables.

## Maintaining this repo

`jobs/` is the single source of truth. `auto-pipeline.yml` and the component are generated from it:

```bash
python3 scripts/build-pipelines-from-fragments.py          # regenerate both files
python3 scripts/build-pipelines-from-fragments.py --check  # CI fails when they are stale
```

Release: push a semantic-version tag without a leading `v` (`git tag 1.0.0 && git push origin 1.0.0`). `.gitlab-ci.yml` of this repository publishes the release with the `glab` image (`release-cli` is in maintenance mode); on a GitLab instance where the project is marked as a catalog resource that release lists the component in the Catalog.

Interpolation: the component uses only `$[[ inputs.name ]]`, which is valid in every GitLab that supports components. GitLab 19.x offers four functions on inputs (`expand_vars`, `truncate`, `posix_escape` since 18.6, `split` since 19.2); none is needed here. `default`, `compact`, `ternary` and `${[[ ... ]]}` are not GitLab syntax.

## How this is tested (honest limits)

There is no GitLab instance behind this repository, so the pipelines are **validated with gitlab-ci-local and GitLab's official CI JSON schema, not on a GitLab server.** What that proves and what it does not:

| Check (GitHub Actions, push, pull request, weekly Monday 03:23 UTC / 10:23 Asia/Saigon, manual) | Proves |
|---|---|
| `yamllint` | style and syntax of every YAML file |
| `build-pipelines-from-fragments.py --check` | the generated files match `jobs/` |
| `tests/validate-against-gitlab-ci-schema.py` | every file, and the interpolated component and merged auto-pipeline as gitlab-ci-local renders them, validate against `ci.json` from `gitlab-org/gitlab` (`app/assets/javascripts/editor/schema/ci.json`, downloaded fresh each run) |
| fixtures `node-good`, `python-good` x (`auto-pipeline`, `component`) | gitlab-ci-local runs the real jobs in their real Docker images and the pipeline goes green: lint, build, test, Gitleaks |
| fixtures `node-bad`, `python-bad` x (`auto-pipeline`, `component`) | a failing unit test turns the pipeline **red**, i.e. no job swallows a test failure |
| `monorepo-good` / `monorepo-bad` | the dynamic generator emits a valid child pipeline per service, selects only changed services on a feature branch, and the generated pipeline passes or fails accordingly |
| child pipeline `validate-inputs` | accepts complete configurations and rejects missing or unknown ones |

Not covered: anything that needs a GitLab server or outside systems. That is `trigger:` (gitlab-ci-local does not follow it, so the generated child pipeline is run directly), the Catalog publication and `release:`, `needs:artifacts` dotenv hand-off across real runners, the Docker-in-Docker build job and the container scan (they need a registry and a privileged runner), Semgrep and Trivy runs (heavy, flaky downloads; the jobs are schema-checked and their images and flags were verified against the tools' documentation), and the deploy jobs (they need hosts, clusters and cloud accounts). Treat those as reviewed, not exercised.

Run it yourself:

```bash
npm ci --prefix tests && export PATH="$PWD/tests/node_modules/.bin:$PATH"   # gitlab-ci-local 4.77.0
tests/run-fixture-with-gitlab-ci-local.sh node-good component pass          # needs Docker
tests/run-fixture-with-gitlab-ci-local.sh node-bad auto-pipeline fail
tests/run-monorepo-fixture-with-gitlab-ci-local.sh monorepo-good pass
pip install -r tests/requirements.txt && yamllint .
```

## What changed from the first version, and what was cut

- The component moved to `templates/<name>/template.yml`, has a `---` after `spec:`, and uses plain `$[[ inputs.x ]]` instead of the non-existent `default`/`compact`/`ternary` functions and the broken `${[[ ]]}` form.
- Build, test and lint run in a per-language image instead of everything in `node`. One job per language replaces the detect jobs whose dotenv outputs overwrote each other.
- `|| echo`, `|| true` and `2>/dev/null` no longer hide test, lint or scan failures.
- The container scan runs after the image is pushed; the double deploy (child trigger plus direct jobs) is gone.
- Semgrep writes a real GitLab SAST report; other scanners no longer claim report types they do not produce. Dependency scanning is one Trivy job instead of per-language tools.
- `kubectl`, Helm, AWS CLI, Trivy, Gitleaks and Semgrep images override the entrypoint and are pinned (no `:latest`); `bitnami/kubectl` (no longer maintained) became `alpine/k8s`; `returntocorp/semgrep` became `semgrep/semgrep`; `release-cli` became `glab`; Docker 24/25/26 became 29; Alpine 3.19 became 3.24.
- Release tags are semantic versions (`1.0.0`).
- Cut because they could not be made to work honestly without accounts to test against, relied on unpinned `npm i -g` CLIs or `curl | sh`, or were not maintained: Vercel, Netlify, FTP, GCS, Firebase, Heroku, ECS, Lambda, Azure, Capistrano, Ansible, Pages and the `custom` escape hatch, plus multi-platform Docker builds (they need a privileged `binfmt` container). The five remaining deploy targets are the ones with a clear, auditable command.

## License

MIT, see `LICENSE`.
