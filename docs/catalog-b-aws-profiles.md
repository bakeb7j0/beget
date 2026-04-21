# Catalog B — AWS Profiles (long-lived credentials)

**Status:** `placeholder` — profile inventory backfilled 2026-04-20 from
`~/sysadmin/unresolved-issues/beget-sketchbook.md` §B. 8 of 9 profiles still
need BJ's long-lived-vs-SSO disposition before wave-2b (#12) can execute.

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

All AWS CLI profiles currently declared in malory's `~/.aws/config`. Each
needs a disposition before it can be promoted into the long-lived-credentials
table below. Fields BJ still needs to fill: **Disposition**, and for
long-lived profiles, **Purpose** (one line).

| Profile | Disposition | Purpose |
|---|---|---|
| `default`         | TODO(BJ) long-lived or SSO? | TODO(BJ) — personal-account default |
| `bedrock`         | TODO(BJ) long-lived or SSO? | TODO(BJ) |
| `bedrock-sync`    | TODO(BJ) long-lived or SSO? | TODO(BJ) |
| `alog-admin`      | **SSO** — not materialized by chezmoi; lives in `~/.aws/config` only | Analogic admin access via IAM Identity Center (sso-session paired) |
| `aws-admin`       | TODO(BJ) long-lived or SSO? | TODO(BJ) |
| `s3-mgmt-bot`     | TODO(BJ) long-lived or SSO? | TODO(BJ) — S3 management automation |
| `test-deploy-bot` | TODO(BJ) long-lived or SSO? | TODO(BJ) — test-env deploy automation |
| `dev-deploy-bot`  | TODO(BJ) long-lived or SSO? | TODO(BJ) — dev-env deploy automation |
| `prod-deploy-bot` | TODO(BJ) long-lived or SSO? | TODO(BJ) — prod-env deploy automation |

Once each profile is classified, move long-lived ones into the
**Long-lived credentials** table below and strike them from the
inventory row count. The `alog-admin` SSO row stays here for
completeness (explicitly out of scope for this catalog — see Scope above).

## Long-lived credentials

Profiles with long-lived static credentials (materialized by chezmoi from
Vaultwarden). Populated from the inventory above as BJ classifies each
profile. Until the inventory has 0 TODO rows, **Status** at the top of this
file remains `placeholder` and agents implementing #12 should refuse to
execute.

| Profile | VW item | Region default | Purpose |
|---|---|---|---|
| _(empty — awaiting BJ dispositions in inventory above)_ | — | — | — |

**Conventions (to apply when populating rows):**

- VW item name is `aws-<profile>` (e.g. `aws-default`, `aws-s3-mgmt-bot`),
  with `username = AccessKeyId`, `password = SecretAccessKey` — per sketchbook
  lines 273-277.
- Region default is `us-east-1` unless the profile needs otherwise
  (sketchbook line 440: `AWS_REGION=us-east-1` is the non-secret global
  default); override per profile in `~/.aws/config` if needed.

No row is added to this table until its disposition in the inventory above
flips from `TODO(BJ)` to `long-lived`. SSO profiles never appear here.

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
