# init-terraform

## Overview

Initializes Terraform in a caller-supplied directory using a partial-backend-config file (architecture D1 — state backend abstraction at the configuration boundary; pattern P1 — file-driven backend selection). Pairs with the two committed backend-config files: `config.minio.tfbackend` (local docker-compose MinIO; default) and `config.s3.tfbackend` (AWS S3). Wraps a single `terraform init -reconfigure -input=false -upgrade -backend-config=<path>` invocation.

## Inputs

| Name | Description | Required | Default |
|---|---|---|---|
| `terraform-dir` | Absolute path to the Terraform root module directory to initialize. Use `${{ github.workspace }}/terraform/<domain>` from a workflow, or `${{ github.action_path }}/terraform` from a nested composite action. | yes | — |
| `backend-config-path` | Basename (resolved relative to `terraform-dir`) or absolute path of the partial-backend-config file. Set to `config.s3.tfbackend` for AWS S3; default selects local MinIO. | no | `config.minio.tfbackend` |

## Outputs

| Name | Description |
|---|---|

_None._

## Side Effects

- Writes `<terraform-dir>/.terraform/` (provider plugins, modules, state-config cache).
- Writes `<terraform-dir>/.terraform.lock.hcl` (provider version lockfile; gitignored repo-wide).
- Reads/writes the configured state backend (MinIO `tfstate` bucket locally, or the AWS S3 bucket per `config.s3.tfbackend`, depending on `backend-config-path`).
- Does **not** export environment variables via `$GITHUB_ENV` and does **not** write outside `<terraform-dir>/.terraform*`.

## Example Usage

MinIO (local default — no extra wiring needed):

```yaml
- uses: hashicorp/setup-terraform@v3
  with:
    terraform_version: latest
- uses: ./.github/actions/init-terraform
  with:
    terraform-dir: ${{ github.workspace }}/terraform/konnect-teams
```

AWS S3 (alternative — caller supplies AWS credentials via env and dynamic overrides):

```yaml
- uses: hashicorp/setup-terraform@v3
  with:
    terraform_version: latest
- uses: ./.github/actions/init-terraform
  with:
    terraform-dir: ${{ github.workspace }}/terraform/konnect-teams
    backend-config-path: config.s3.tfbackend
# Per pattern P1, callers add -backend-config="bucket=…" via TF_BACKEND_CONFIG plumbing in Story 2.3.
```

## Failure Modes

- **`terraform: command not found`** — caller did not run `hashicorp/setup-terraform@v3` first. Resolution: add the setup step before `uses: ./.github/actions/init-terraform`.
- **`terraform init` exit non-zero, "Failed to get existing workspaces"** — local MinIO unreachable (docker-compose not running, or `tfstate` bucket missing). Resolution: `docker compose up -d minio minio-create-bucket vault` and verify `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9000/tfstate`. `200` or `403` means MinIO is reachable and the `tfstate` bucket exists; `404` means MinIO is reachable but the bucket is missing (re-run `docker compose up -d minio-create-bucket`); a connection error / non-HTTP response means MinIO itself is not reachable.
- **`terraform init` exit non-zero, "Error inspecting states in the s3 backend"** — wrong `backend-config-path` value (path does not exist, or pointing at the AWS file without AWS credentials in env). Resolution: confirm `<terraform-dir>/<backend-config-path>` exists and matches the intended backend.
- **`terraform init` exit non-zero with provider-resolution errors** — gitignored `.terraform.lock.hcl` was deleted but `-upgrade` failed (typically a flaky registry). Resolution: re-run; the action is idempotent.
