# Catalog B — AWS Profiles (long-lived credentials)

**Status:** `filled` (2026-04-20). All 8 profiles below classified long-lived.
`alog-admin` — originally in the sketchbook list — was dropped (not needed).

Materialized form of Dev Spec R-18: profiles in `~/.aws/credentials` that
`chezmoi apply` renders from Vaultwarden items. One row per profile. Agents
implementing #12 read this file; they do not infer or invent entries.

## Scope

Only **long-lived-credential** profiles belong here. Session/SSO profiles
(e.g. `aws-sso-admin`) do not store static `aws_access_key_id` /
`aws_secret_access_key` and are expressed in `~/.aws/config` via
`sso_session` references, not materialized from VW. A separate catalog
(or simply `~/.aws/config` in `dot_aws/`) covers those.

## Schema

| Field | Meaning |
|---|---|
| **Profile name** | The `[<name>]` header in `~/.aws/credentials` (e.g. `default`, `analogic-prod`, `waveeng-billing`). |
| **VW item** | Vaultwarden item name. Convention: `aws-<profile>`. Fields: `accessKeyId`, `secretAccessKey`, optional `sessionToken` (rare for long-lived), optional `region`. |
| **Region default** | Default region for the profile (`us-east-1`, etc.). Goes into `~/.aws/config`, not `credentials`, but listed here for completeness. |
| **Purpose** | One-line description of what the profile is used for. Optional but recommended. |

## Profile inventory (from sketchbook §B)

The AWS CLI profiles beget will materialize via chezmoi, with dispositions
confirmed by BJ. `alog-admin` — originally present in the sketchbook
inventory — has been dropped (not needed).

| Profile | Disposition | Purpose |
|---|---|---|
| `default`         | long-lived | analogic dev access |
| `bedrock`         | long-lived | AI resources in dev |
| `bedrock-sync`    | long-lived | AI resources in dev |
| `aws-admin`       | long-lived | admin account for dev |
| `s3-mgmt-bot`     | long-lived | dev account S3 management automation |
| `test-deploy-bot` | long-lived | test-env deploy automation |
| `dev-deploy-bot`  | long-lived | dev-env deploy automation |
| `prod-deploy-bot` | long-lived | prod-env deploy automation |

All 8 profiles appear in the Long-lived credentials table below. No SSO
profiles in this catalog (none in the current inventory).

## Long-lived credentials

Profiles with long-lived static credentials (materialized by chezmoi from
Vaultwarden). `default` first, then alphabetical — per the rendering order
convention below.

| Profile | VW item | Region default | Purpose |
|---|---|---|---|
| `default`         | `aws-default`         | `us-east-1` | analogic dev access |
| `aws-admin`       | `aws-aws-admin`       | `us-east-1` | admin account for dev |
| `bedrock`         | `aws-bedrock`         | `us-east-1` | AI resources in dev |
| `bedrock-sync`    | `aws-bedrock-sync`    | `us-east-1` | AI resources in dev |
| `dev-deploy-bot`  | `aws-dev-deploy-bot`  | `us-east-1` | dev-env deploy automation |
| `prod-deploy-bot` | `aws-prod-deploy-bot` | `us-east-1` | prod-env deploy automation |
| `s3-mgmt-bot`     | `aws-s3-mgmt-bot`     | `us-east-1` | dev account S3 management automation |
| `test-deploy-bot` | `aws-test-deploy-bot` | `us-east-1` | test-env deploy automation |

**Conventions encoded above:**

- VW item name is `aws-<profile>`, with `username = AccessKeyId`,
  `password = SecretAccessKey` — per sketchbook lines 273-277.
- Region default is `us-east-1` globally (sketchbook line 440:
  `AWS_REGION=us-east-1` is the non-secret default); override per profile in
  `~/.aws/config` if any profile ever needs a different region.

New rows added in the future: match inventory disposition first. Only
profiles dispositioned `long-lived` appear here; SSO profiles live in
`~/.aws/config` only, not this catalog.

## `~/.aws/credentials` rendering order

Convention: `default` first, then alphabetical by profile name. Agents
should follow the order declared in the table above.

## Adding a new profile

1. Append a row above.
2. Create the `aws-<profile>` item in Vaultwarden with the required fields.
3. `credentials.tmpl` rebuilds automatically from the catalog — no per-profile
   template edits needed if the template is a loop over the catalog. If the
   template is one block per profile, add the block.
4. Set region in `dot_aws/config.tmpl` under `[profile <name>]`.

## Out of scope

- SSO / session profiles (see Scope above).
- IAM Identity Center config (`dot_aws/config.tmpl` handles via separate sections).
- MFA-sourced temporary credentials (not materialized via chezmoi; see `newsecret` helper in #13 for rotation flows).
