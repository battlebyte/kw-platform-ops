---
project_name: 'kw-platform-ops'
user_name: 'Jordi'
date: '2026-05-06'
sections_completed: ['technology_stack', 'language_rules', 'framework_rules', 'testing_rules', 'quality_rules', 'workflow_rules', 'anti_patterns']
status: 'complete'
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

**Platform-engineering repo — no application runtime.** This repo defines GitHub Actions, Terraform, Helm, and shell scripts that platform operators run to manage the Kong-managed API platform ("Kong Air"). No application code lives here aside from a small Flask onboarding UI.

**GitHub Actions / Workflows**
- Reusable composite actions live in `.github/actions/` (`deploy-dp`, `provision-konnect-resources`, `publish-api-configuration`, `setup-k8s-tools`).
- Platform-run workflows live in `.github/workflows/` (`deploy-dp.yaml`, `developer-portal.yaml`, `onboard-konnect-teams.yaml`, `test-sync-api-configuration.yaml`).
- Pinned third-party actions: `actions/checkout@v4`, `hashicorp/setup-terraform@v3` (terraform_version: `latest`), `aws-actions/configure-aws-credentials@v4`, `unfor19/install-aws-cli-action@v1`, `azure/setup-helm@v4`, `azure/setup-kubectl@v4`.
- Local execution via `act` (`pantsel/gh-runner:latest`); secrets in `act.secrets` (gitignored).

**Terraform**
- Working directory: `terraform/konnect-teams/` (S3 backend, partial backend config in `config.s3.tfbackend`).
- Provider pin: `kong/konnect = 3.15.0`. AWS provider region hardcoded to `eu-central-1` with `skip_credentials_validation/skip_metadata_api_check/skip_requesting_account_id = true`.
- Vault provider used for system-account token storage (commented in `providers.tf`; configured via `VAULT_ADDR`/`VAULT_TOKEN` env vars).

**Konnect**
- Authentication via `KONNECT_SERVER_URL` (var) + `KONNECT_TOKEN` (secret). Default region: `eu` (`https://eu.api.konghq.com`).
- decK CLI pinned to `v1.51.0` in `publish-api-configuration`.
- Spectral (`@stoplight/spectral-cli` + `@stoplight/spectral-owasp-ruleset@^2.0`) for OpenAPI linting.

**Kubernetes / Helm**
- Kong Helm repo: `https://charts.konghq.com`; chart used: `kong/kong`.
- Default Kong Gateway image tag: `3.11.0.2`; default Helm chart version: `2.45.0`.
- `k8s/values.yaml` is the shared values file for DP deployments.

**HashiCorp Vault**
- Default address pattern: `https://vault.kong-cx.com` (Makefile) or `http://localhost:8300` (action default for local).
- KV mounts per-team (e.g., `flight-operations-kv`); system-account secrets at `system-accounts/sa-<team-name>`.

**Other tooling**
- `yq` (mikefarah) for YAML validation — installed on demand by actions.
- `k6` for load testing (`scripts/load-test-flights.js`).
- Python Flask app: `webapp/onboard_team_app.py`.
- Helm chart `charts/kong-config-exporter` (custom).
- Local stack: `docker-compose.yaml` for Vault + runner.

**Source-of-truth YAML**
- `teams/*.yaml` — Konnect teams (validated and consumed by `terraform/konnect-teams`).
- `konnect/developer-portal/config.yaml` — developer portal resources.
- `konnect/dashboards/` — dashboard configs.
- `portal/*.yaml` — triggers `developer-portal.yaml` workflow on push.

---

## Critical Implementation Rules

### Language-Specific Rules

**Bash (in composite actions and scripts)**
- Always declare `shell: bash` on every step in composite actions — required for cross-runner consistency.
- Use `set -euo pipefail` in `scripts/*.sh` and any non-trivial action step (see `provision-konnect-resources` install-yq step for the pattern).
- Detect OS before downloading binaries: branch on `uname -s` (`Linux*`/`Darwin*`) — actions are run on ubuntu-latest in CI but also via `act` and locally on macOS.
- Never `echo` secrets into logs. When piping into `$GITHUB_ENV`, do not print the value first; use the variable name only on subsequent lines.
- Sanitize Konnect/team names before use: `tr '[:upper:]' '[:lower:]' | sed 's/[ _]/-/g'` is the established pattern (see `deploy-dp/action.yml`).

**Terraform / HCL**
- Pin provider versions explicitly in the `terraform { required_providers { ... } }` block — `kong/konnect` is currently pinned to `3.15.0`. Do not use `~>` or unpinned constraints for the Konnect provider; the schema changes between minor versions.
- Use **partial backend configuration**: keep static keys in `config.s3.tfbackend` and pass dynamic keys (`bucket`, `key`, `region`) via `-backend-config=...` at `init` time. Never commit a fully-resolved `backend "s3"` block.
- The standard apply pipeline is `init -upgrade` → `plan -out=tfplan` → `apply -auto-approve tfplan`. Always plan to a file and apply that file — do not `apply -auto-approve` without a saved plan.
- YAML-driven resources: read team/portal definitions via `fileset(...)` + `yamldecode(file(...))` (see `terraform/konnect-teams/main.tf`). Always run `yq` validation **before** Terraform sees the YAML.
- Sanitize names for resource IDs and S3 bucket names: `replace(lower(name), " ", "-")` is the canonical pattern.

**YAML (source-of-truth files)**
- Every resource YAML must have a top-level `name` (lowercase alphanumeric + hyphens only — enforced by `onboard-konnect-teams.yaml` validation).
- `entitlements` must be a list and each value must be one of `konnect.control_plane` or `konnect.api`. Adding a new entitlement requires updating the validator in `.github/workflows/onboard-konnect-teams.yaml` (and any equivalent `validate-config.sh` scripts) — do not silently extend the schema.
- OpenAPI specs consumed by `publish-api-configuration` must declare `info.title`, `info.x-business-unit`, and `info.x-team-name`; optional `x-kong-namespace` at root level.

**Python (Flask onboarding webapp)**
- The Flask app at `webapp/onboard_team_app.py` is a thin operator UI; keep business logic in shell scripts / Terraform — do not migrate Konnect logic into Python.

### Framework-Specific Rules

**GitHub Actions — composite actions**
- Reusable actions live under `.github/actions/<name>/action.yml` (or `action.yaml`). Use `runs.using: composite` — do not introduce JavaScript or Docker actions without a strong reason.
- Inputs must declare `description` and `required` for every input; provide sensible `default` for optional inputs (e.g., `aws-region: 'eu-central-1'`, `konnect-region: 'eu'`).
- Reference action-bundled files with `${{ github.action_path }}` (never `github.workspace`) — required because composite actions are checked out into a different path.
- Never read repo files via relative paths in a composite action; the working directory is the **caller's** workspace.
- Pass secrets as inputs explicitly (do not rely on `secrets` inheritance). Workflows wire `${{ secrets.X }}` → action input; the action then re-exports to `$GITHUB_ENV` if downstream steps need env-style access.

**GitHub Actions — workflows (operator-run)**
- Triggers: every platform workflow exposes both `workflow_dispatch` (manual) and a path-filtered `push` on `main` (e.g., `teams/*.yaml`, `portal/*.yaml`). Keep both — manual is for ops, push is for GitOps-style sync.
- Provide `workflow_dispatch.inputs` with descriptions and defaults that match the dev/staging environment, so an operator can run with zero edits.
- Centralize repeated env (`KONNECT_SERVER_URL`, `VAULT_ADDR`, `AWS_S3_BUCKET`, `TERRAFORM_DIR`, `TF_VAR_resources_path`) at the **job** level — do not duplicate per step.
- Use `vars.*` for non-sensitive configuration (URLs, regions, bucket names) and `secrets.*` for credentials. Distinguish them deliberately.
- Each Terraform-touching workflow must call `scripts/create-s3-bucket.sh <bucket>` before `terraform init` to ensure backend storage exists.

**Terraform modules**
- Modules live under `terraform/konnect-teams/modules/<name>` (`system-account`, `vault`). Use one module per logical concern; pass IDs and names from the root module — modules should not re-read the source YAML.
- Prefer `for_each` over `count` when iterating over teams/portals — entries are keyed by name and renames must not destroy unrelated resources.
- Outputs are consumed across modules (e.g., `module.system-account[each.value.name].system_account_token` → `module.vault`); avoid breaking output names without coordinated edits.

**Helm**
- The Kong DP chart is `kong/kong` (not `kong/kong-gateway`). The Helm chart version (`helm-chart-version` input) is independent of the Kong Gateway image tag (`kong-image-tag`); both are passed in explicitly — do not hardcode either.
- Override image and clustering endpoints with `--set` flags for clarity; reserve `values.yaml` for stable configuration.
- Clustering endpoints are stripped of `https://` before being passed to `--set env.cluster_control_plane=...:443` (see `deploy-dp/action.yml`). Do not pass full URLs — they will silently break the chart.

**Konnect provider (Terraform)**
- Provider authentication reads `KONNECT_SERVER_URL` and `KONNECT_TOKEN` from the environment (provider block can be commented). Do not hardcode tokens in `.tf` files.
- Resource attribute schemas changed between provider versions; when bumping `kong/konnect`, regenerate state expectations and verify with `plan` before merging.

### Testing & Validation Rules

**This repo has no application unit-test framework.** Validation happens at three layers: YAML schema checks, Terraform plan diffs, and end-to-end workflow runs via `act`.

**YAML validation (pre-Terraform)**
- The validator in `.github/workflows/onboard-konnect-teams.yaml` (and `provision-konnect-resources/scripts/validate-config.sh`) is the test gate. New required fields must be added there before they are referenced in Terraform — never trust unvalidated YAML reaching `yamldecode()`.
- Manual local validation: `make test-validator` runs `test/provisioning/validate-config_test.sh`.

**Terraform plan as a test**
- `terraform plan` is the primary correctness check before any apply. PRs touching `terraform/**` should include the relevant plan output (or a CI plan step) — never merge HCL changes that have not been planned against state.
- For destructive changes (renames, removals), require an explicit operator acknowledgement; `for_each` keying by name means a typo can recreate resources.

**Local end-to-end via act**
- The Makefile orchestrates a local stack: `make prepare` → checks deps, sets up `.actrc`, prepares `act.secrets`, brings up Vault + runner via docker-compose, and runs `vault-pki-setup.sh`.
- Use `pantsel/gh-runner:latest` as the runner image; do not assume the default `ghcr.io/catthehacker/ubuntu` images — actions in this repo expect tools installable from this image.
- `act.secrets` must contain `VAULT_TOKEN` and `GITHUB_ORG` at minimum (parsed by Makefile via `grep -o`).

**OpenAPI linting (publish-api-configuration)**
- Spectral lints with the ruleset bundled in `${{ github.action_path }}/spectral/.spectral.yaml`. New rules belong there — do not bypass linting via per-spec ignores.
- Lint failures must block publication; do not add `|| true` or `continue-on-error: true` to the lint step.

**Integration tests**
- `test/apis/` and `test/provisioning/` hold scenario-style scripts. Keep new integration scenarios under these directories using the existing shell-script pattern.
- Load tests use `k6` (`scripts/load-test-flights.js`); keep load-test code separate from functional tests.

### Code Quality & Style Rules

**File and folder organization**
- Keep the operator/team-facing split intact:
  - `.github/workflows/` = platform-operator-run only.
  - `.github/actions/` = consumed by API teams (and by platform workflows). Public input contract — treat input names/types as semver-stable.
- One purpose per directory: `terraform/<domain>/`, `konnect/<resource-type>/`, `teams/<team>.yaml`, `scripts/<helper>.sh`, `charts/<chart-name>/`. Do not mix concerns (e.g., no Terraform inside `scripts/`).
- New action artifacts (rulesets, plugin templates, kong-lint configs, helm value overlays) live **inside the action's own folder** (e.g., `publish-api-configuration/spectral/`, `publish-api-configuration/kong-lint/`, `publish-api-configuration/plugins/`, `publish-api-configuration/patches/`).

**Naming conventions**
- Workflows: kebab-case `.yaml` files (e.g., `onboard-konnect-teams.yaml`).
- Actions: kebab-case directory names; `action.yml` or `action.yaml` (both exist — match the convention of the directory you're editing rather than introducing a third style).
- Action input names: kebab-case (e.g., `kong-image-tag`). Within Bash, reference as `${{ inputs.kong-image-tag }}`.
- GitHub Actions env vars: SCREAMING_SNAKE_CASE (`KONNECT_SERVER_URL`).
- Terraform resources/variables: snake_case (`konnect_team`, `resources_path`).
- Terraform locals for derived names: `sanitized_team_names` pattern — explicit, plural for collections.
- Konnect/team identifiers in YAML: lowercase alphanumeric + hyphens (enforced by validator).
- S3 bucket naming: `kw.konnect.<purpose>[.<team>]` (e.g., `kw.konnect.teams`, `kw.konnect.dev-portal-terraform-state`, `kw.konnect.team.resources.<team>`). Maintain the `kw.konnect.` prefix.

**Action / workflow style**
- Steps must have a `name:` (human-readable) — exception: `uses:`-only steps where the action name is self-describing.
- Use `working-directory:` rather than `cd ... && ...` chains in `run:` blocks.
- Prefer `${{ env.X }}` references in `run:` blocks over re-interpolating `${{ secrets.X }}` mid-script — set env once at job/step level.
- Use heredocs (`kubectl apply -f - <<EOF ... EOF`) for inline manifests rather than templating files.

**Terraform style**
- Comment major pipeline phases with banner comments (see `main.tf`'s `# STEP 1/2/3 ...` blocks). Keep the existing numbered-step style when extending.
- Use `lookup(map, "key", default)` for optional YAML-sourced fields rather than `try(...)` chains where a simple default suffices.
- Group related resources into modules once they exceed ~3 resources or have cross-cutting outputs.

**Documentation**
- Every reusable action gets a `README.md` documenting inputs, outputs, and an example caller workflow. The `provision-konnect-resources` action follows this pattern — match it.
- Default to no inline comments. Add a comment only when the *why* is non-obvious (e.g., the `skip_credentials_validation = true` flags in `providers.tf` warrant a comment because they're surprising).

### Development Workflow Rules

**Branching and merging**
- `main` is the trunk and the trigger for path-filtered workflows (`teams/*.yaml`, `portal/*.yaml`). Pushing to `main` directly applies infrastructure — gate via PR reviews.
- A change under `teams/`, `portal/`, `konnect/`, or `terraform/` is an infrastructure-affecting change. Apply a stricter review than for documentation or `scripts/` edits.

**Commit messages**
- Recent history uses conventional-commit-ish prefixes: `feat:`, `docs:`, plus free-form action-oriented messages. Match the surrounding style — prefer `feat:` / `fix:` / `docs:` / `refactor:` when applicable.
- Reference the affected workflow/action/module in the subject when scope is clear (e.g., `feat(deploy-dp): ...`).

**PR checklist (infrastructure-affecting changes)**
- YAML schema changes: validator script updated **before** the new field is consumed.
- Terraform changes: `terraform plan` output attached or run in CI; destructive diffs explicitly justified.
- New action input or breaking change: bump the action's `README.md` example and update every caller workflow in this repo in the same PR.
- New secret/var requirement: add to `act.secrets` template, the workflow's env block, and the README "Running the workflows" section.

**Local development**
- Always start with `make prepare` on a fresh checkout — it's the documented bootstrap path.
- Never commit `act.secrets`, `.tls/`, or `.tmp/` (cleaned by `make clean`).
- Use `act` to dry-run workflow changes before opening a PR; catches input-wiring mistakes that GitHub-side runs would only surface after merge.

**Deployment / rollout**
- Dataplane rollouts are explicit: operator runs `deploy-dp` workflow with a chosen `helm-chart-version` and `kong-image-tag`. Do not introduce auto-rollouts.
- Konnect resource changes (teams, portals) flow through GitOps push-on-main — no manual `terraform apply` outside the workflows.
- Rollback for Helm: re-run `deploy-dp` with the previous chart version + image tag. There is no separate rollback action; bump back through the same input contract.

**External system coordination**
- Konnect tokens are environment-scoped (vars/secrets per environment). When adding a new Konnect-targeting workflow, declare which `KONNECT_SERVER_URL` env it expects.
- Vault path conventions are stable contracts: `system-accounts/sa-<team-name>` and per-team KV mounts (e.g., `flight-operations-kv`). Renaming a Vault path is a breaking change for downstream DPs.

### Critical Don't-Miss Rules

**Anti-patterns to avoid**
- ❌ Hardcoding `KONNECT_TOKEN`, `VAULT_TOKEN`, or AWS credentials anywhere — even in defaults, examples, or comments. Always read from `secrets.*`.
- ❌ Echoing secrets to logs (`echo "TOKEN=$TOKEN"`) — sensitive values must reach `$GITHUB_ENV` directly without log emission.
- ❌ Using `relative` paths in composite-action `run:` steps that target the action's own files. Always use `${{ github.action_path }}/...`.
- ❌ Adding `continue-on-error: true` or `|| true` to validators, linters, or `terraform plan/apply` steps. These are quality gates — failures must surface.
- ❌ `terraform apply` without a saved plan file. Always `plan -out=tfplan` first, then `apply tfplan`.
- ❌ Renaming a `teams/<team>.yaml` file's top-level `name` without coordinating destruction — `for_each` keys by name; renames are destroy/create.
- ❌ Pinning provider/action versions with `latest`, `~>`, or unbounded ranges for the Konnect provider. The current pin is `kong/konnect = 3.15.0` — keep it exact.
- ❌ Mixing operator-only workflows into `.github/actions/`, or pushing reusable team-facing logic into `.github/workflows/`. The split is a security boundary.
- ❌ Bypassing the YAML validator by pointing Terraform at a new YAML directory. Any new YAML source must have a validation gate first.

**Edge cases agents must handle**
- Names containing spaces or uppercase (e.g., free-form team names from upstream): always pass through `replace(lower(name), " ", "-")` (Terraform) or `tr '[:upper:]' '[:lower:]' | tr ' ' '-'` (Bash) before using as an identifier.
- Optional Konnect inputs (`konnect-server-url`, `konnect-region`, `konnect-api-version`): preserve defaults (`https://eu.api.konghq.com`, `eu`, `v2`) — these are tied to the EU control plane.
- Helm clustering endpoints: strip `https://` (`sed 's|https://||'`) and append `:443` before passing to `--set env.cluster_control_plane=...`.
- Missing optional YAML fields: use `lookup(map, "key", default)` — never assume presence. Labels default to `{ "generated_by" = "terraform" }`.
- AWS endpoint override (`AWS_ENDPOINT_URL`) is for local-stack/MinIO testing only; ensure it is empty or unset in production runs.

**Security must-dos**
- Use `vars.*` for non-sensitive config, `secrets.*` for credentials. A `KONNECT_TOKEN` is **never** a `var`.
- Vault tokens are short-lived; do not persist them outside `$GITHUB_ENV` for the job's duration.
- S3 backend buckets must be encrypted and access-controlled (created via `scripts/create-s3-bucket.sh`); never bypass that script when introducing a new state bucket.
- Konnect system-account tokens (`module.system-account[*].system_account_token`) flow into Vault via `module.vault` — never expose them as Terraform outputs.
- Validate every YAML before any infrastructure mutation (this prevents typos in `entitlements` from silently granting wrong access).

**Performance / operational gotchas**
- `terraform init -upgrade` re-resolves providers every run — fine for CI, slow for local. Use `init` (no `-upgrade`) for iterative local work.
- The `unfor19/install-aws-cli-action` is a no-op on macOS via `act`; on Linux runners (and self-hosted) install AWS CLI defensively (see `deploy-dp` action's install block).
- decK `DECK_CONFIG_API_SPEC` is URI-encoded (`jq -sRr @uri`) — do not double-encode.
- Helm `--set` flags override `values.yaml` keys silently; when both are present, prefer `--values` for stability and `--set` only for runtime-injected values (image tag, chart version, endpoints).

---

## Usage Guidelines

**For AI Agents:**
- Read this file before implementing any code in this repo.
- Follow ALL rules exactly as documented; when in doubt, prefer the more restrictive option.
- Update this file when new patterns emerge or when conventions change.

**For Humans:**
- Keep this file lean and focused on agent needs — remove rules that become obvious over time.
- Update when the technology stack changes (Konnect provider bumps, Kong chart bumps, action version pins).
- Review quarterly; prune stale entries.

Last Updated: 2026-05-09

