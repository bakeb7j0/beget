# Catalog B — AWS Profiles (long-lived credentials)

**Status:** `placeholder` — BJ fills in rows before wave-2b (#12) executes.

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

## Profiles

<!--
  Fill in concrete rows below. Remove the TODO(BJ) markers when complete.
  When this table has no TODO(BJ) rows, flip Status above to `filled`.
-->

| Profile | VW item | Region default | Purpose |
|---|---|---|---|
| `default` | `aws-default` | TODO(BJ) | TODO(BJ) — personal-account default |

TODO(BJ): add a row per long-lived profile. If there are *no* long-lived
profiles (i.e. you only use SSO), say so here and issue #12 should be
closed as not-applicable rather than implemented.

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
