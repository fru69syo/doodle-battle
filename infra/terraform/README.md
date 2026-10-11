# Terraform (GCP / Firebase infrastructure)

Read [`docs/LEARN_GCP.md`](../../docs/LEARN_GCP.md) first (Japanese, step by step).

```
bootstrap/            once per project, by a human: state bucket, Terraform service accounts, GitHub WIF
envs/dev, envs/prod   the stacks (remote state in gs://<project>-tfstate, prefix envs/<env>)
modules/              project_services, firebase, artifact_registry, service_accounts, github_wif,
                      secrets, realtime_service, cost_guard (budget -> Pub/Sub), monitoring
```

Offline checks (what CI runs, no credentials needed):

```bash
terraform fmt -check -recursive
for d in bootstrap envs/dev envs/prod; do (cd $d && terraform init -backend=false && terraform validate); done
tflint --init --config=$PWD/.tflint.hcl && (cd envs/prod && tflint --config=$PWD/../../.tflint.hcl)
```

Real runs: `terraform init -backend-config="bucket=<project>-tfstate"` then `plan` / `apply`,
locally or through `.github/workflows/infra-apply.yml`.
Not managed here (Firebase CLI owns them): security rules, indexes, TTL policies, Cloud Functions.
