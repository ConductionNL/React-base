# Changelog

All notable changes to this repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **2026-05-01** — Initial openspec change `bootstrap-react-platform`. Proposal/design/tasks for mirroring the Nextcloud-base GitOps shape onto the WOO PWA: ApplicationSet + layered Helm values (`common.yaml` → `env/*.yaml` → `tenants/tenant-*.yaml`), vendored `woo-website` chart, AppProject sync-window governance. Replaces the `mcc create-react` per-tenant manifest generator. Tenant files become 2 lines (`name`, `environment`) for the common case; namespace pairs with the Nextcloud co-tenant (`<org>-<env>`); image tag pinned to semver in `common.yaml` (no more `latest`); branding migration sources truth from live cluster state. No code or values scaffolded yet — planning docs only. Files: `openspec/changes/bootstrap-react-platform/{.openspec.yaml,proposal.md,design.md,tasks.md}`.
- **2026-05-01** — Document external dependencies in `bootstrap-react-platform`: DNS handled by `cluster-infra/external-dns` (Cloudflare, `policy: sync`, zones `commonground.nu`/`openwoo.app`/`opencatalogi.nl`) — tenant adds/removes auto-create/auto-reap DNS records. TLS via cert-manager + HTTP-01. Recorded in `design.md` (new "External dependencies" subsection), `proposal.md` (Removed from Scope), and `tasks.md` (task 7.1 will surface this in `docs/ADDING-TENANT.md`).
