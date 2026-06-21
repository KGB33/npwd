# NPWD Infrastructure / CI/CD / Hosting Story — Design

**Date:** 2026-06-21
**Status:** Approved (brainstorm), pending implementation plan

## Goal

Close the gaps found in the infra/CI/CD/hosting review by making the Nix flake the single
source of truth for the toolchain, the test/lint orchestration, and the deployable artifact.
After this work there is one reproducible path from `git clone` to a runnable production
server, and CI verifies that path on every push.

## Problems being fixed

From the review, in priority order:

1. **Toolchain declared twice and drifting.** `flake.nix` pins the dev toolchain via nixpkgs;
   `.github/workflows/test.yml` independently re-declares Erlang/Gleam/Node/SurrealDB versions
   via `setup-beam`/`setup-node`/`docker run`. The two are already inconsistent (CI pins
   exact versions the flake leaves floating). This is the root cause of the known
   `gleam format` skew.
2. **No deployable artifact.** The flake exposes only `devShells.default`. There is no
   `packages.default`. The client bundle (`client.js` — the entire frontend) is git-ignored
   and produced by a manual `cp` documented in README §1; nothing builds it reproducibly.
3. **Boot is half fail-fast.** `env.load` panics on bad config, but `db.apply_schema` and
   `seed_admin` swallow their `Result`, so a broken DB/schema lets the server start and serve
   a broken app.
4. **Hand-rolled SurrealDB readiness probe in CI** with a fall-through bug (the 30-iteration
   poll loop never `exit 1`s on timeout; tests run anyway against a DB that never came up).
5. **No CI dependency caching** — every run recompiles all hex deps across three packages.
6. **CI duplication** — three near-identical per-package steps.
7. **Minors:** no canonical env contract (`.env.example`); `master` branch trigger is dead;
   no deployment/TLS documentation.

## Scope

**In scope:** flake outputs (`packages.default`, `packages.client`, `checks.*`); CI rewrite;
fail-fast boot; `.env.example`; README deployment note.

**Explicitly out of scope** (to prevent creep): NixOS module, systemd unit, SurrealDB
provisioning, secrets tooling (agenix/sops), TLS/reverse-proxy config, any change to the
session-cookie `Secure` handling (security-review scope), and the description-position
concurrency fix. The user will wire systemd, SurrealDB, TLS, and secrets in their own host
config and run the built package with env vars.

## Decisions (from brainstorm)

- **Hosting target:** self-hosted NixOS host + systemd, wired by the user outside this repo.
  This repo provides only `packages.default`.
- **nixpkgs pin:** keep `nixos-unstable`; rely on `flake.lock` for reproducibility. CI runs
  through the flake, so CI and dev share the locked pin. This directly fixes the drift.
- **CI verifies the artifact:** CI runs `nix flake check` (fmt + lint + tests) **and**
  `nix build .#default`.
- **Lint layer:** Gleam has no separate linter; "lint" = `gleam format --check` plus
  `gleam check --warnings-as-errors` (type-check without codegen, warnings fatal).

## Architecture

The flake is the single source of truth. Outputs:

```
flake.nix
├── devShells.default   (unchanged — keeps the dev shellHook env vars)
├── packages.client     (intermediate: the built client.js bundle)
├── packages.default    (the deployable artifact — server shipment + client.js)
└── checks.<system>     (fmt + check + tests, per package)
```

### Offline-deps mechanism (the crux)

`nix flake check` and `nix build` run in a sandbox with **no network**, but `gleam build`
fetches hex deps. `manifest.toml` already pins exact versions with sha256 hashes for all
three packages, so offline builds are deterministic. Use
[`arnarg/nix-gleam`](https://github.com/arnarg/nix-gleam)'s `buildGleamApplication`, which
reads `manifest.toml` and produces an offline deps derivation — the canonical helper, rather
than a hand-rolled fixed-output derivation (FOD).

The Linux Nix sandbox exposes loopback (`127.0.0.1`), so the server test check can start an
in-memory SurrealDB inside the sandbox and connect to it.

### Spike gate (first plan task)

`nix-gleam` is normally used on single-package, Erlang-target apps. This repo stresses it:

1. **Monorepo path dep** — `server` and `client` both `path`-depend on `shared`. The build
   `src` must carry all needed package sources and resolve local `shared` (not hex).
2. **Client JS bundle** — the client is `gleam run -m lustre/dev build` (compile to JS +
   bundle via bun), outside `nix-gleam`'s Erlang-shipment scope.

The first plan task is a spike: confirm `buildGleamApplication` builds `server` (with `shared`
as a path dep) into an erlang-shipment offline.

- **If it works:** use `nix-gleam` for the server; a thin custom derivation (reusing its deps
  output) for the client bundle.
- **If it fights the monorepo:** fall back to a hand-rolled FOD (same `manifest.toml` hashes,
  more nix code), keeping the rest of the design identical.

The **client bundle is a custom derivation either way** (gleam + bun + offline deps →
`client.js`); the spike only decides the server build mechanism and proves offline deps
resolve.

## Components

### `packages.client`

A derivation with `gleam` + `bun` + the offline client deps. Runs the lustre bundle and
emits a single `client.js`:

```
gleam run -m lustre/dev build --outdir=$out   →   $out/client.js
```

Reproducible replacement for README §1's manual `cp`. `client.js` stays git-ignored; nothing
hand-copies it.

### `packages.default` (the deployable artifact)

1. Build the `server` Erlang shipment (`gleam export erlang-shipment`, via `nix-gleam` or the
   FOD fallback).
2. Post-install: inject `packages.client`'s `client.js` into the shipment's `priv/static/`.
3. Result: a self-contained shipment with an `entrypoint.sh`. Running it needs only the env
   vars from `env.gleam`'s fail-fast contract — exactly what the user's systemd unit provides.
   No client step, no `cp`.

### `checks.<system>`

One check per package, each doing **fmt + check + test**:

| check    | runs                                                                  | systems     |
|----------|-----------------------------------------------------------------------|-------------|
| `shared` | `gleam format --check` + `gleam check --warnings-as-errors` + `gleam test` | all    |
| `client` | `gleam format --check` + `gleam check --warnings-as-errors` + `gleam test` | all    |
| `server` | `gleam format --check` + `gleam check --warnings-as-errors` + `gleam test` | linux only |

The `server` check starts an in-memory SurrealDB on `127.0.0.1:8001` inside the sandbox, waits
for readiness with a **bounded loop that `exit 1`s on timeout** (fixes the review's
fall-through bug, relocated to where it belongs), runs the suite, and the sandbox tears the DB
down. Linux-only because the macOS sandbox does not give the same loopback guarantee; darwin
devs run `gleam test` in the dev shell, and CI is Linux, so coverage is unaffected.

`gleam check --warnings-as-errors` runs before the test step so type errors and compiler
warnings fail the check fast, without waiting on codegen or the DB.

### CI (`.github/workflows/`)

The entire workflow collapses to:

```yaml
name: ci
on:
  push: { branches: [main] }
  pull_request:
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: DeterminateSystems/nix-installer-action@main
      - uses: DeterminateSystems/magic-nix-cache-action@main
      - run: nix flake check -L
      - run: nix build .#default -L
```

Deleted by this change: `setup-beam`, `setup-node`, all four version pins, the `docker run` +
poll loop, the three duplicated per-package steps, and the `master` branch trigger.
`magic-nix-cache` provides the dependency/build caching that `actions/cache` was missing. One
source of truth — the flake — for toolchain, tests, lint, and the artifact, verified on every
push.

### Boot fail-fast (`server.gleam`)

Make the boot sequence atomically fail-fast, mirroring `env.load`:

```gleam
case db.apply_schema(config) {
  Ok(_) -> Nil
  Error(e) -> panic as ("schema apply failed: " <> db.error_to_string(e))
}
seed_admin(config)
```

- `apply_schema` failure → panic with a clear message instead of `let _ =`.
- `seed_admin`: keep the current "only seed when the user table is empty and creds are
  present" logic, but when a seed **is** attempted on an empty DB and `create_user` fails,
  panic rather than silently continuing. The "no creds provided" case stays a no-op (admin
  seeds on a later run).
- Add a small `db.error_to_string(DbError) -> String` helper for the panic messages, living in
  `db.gleam` next to `DbError` (error formatting stays in the canonical layer).

~15 lines plus one helper. No structural change — just closing the fail-open gap.

### Minors

- **`.env.example`** at repo root — the canonical contract listing exactly the vars
  `env.load` requires (`SURREAL_HOST`, `SURREAL_PORT`, `SURREAL_NAMESPACE`, `SURREAL_DATABASE`,
  `SURREAL_USER`, `SURREAL_PASSWORD`, `SECRET_KEY_BASE`, `PORT`) plus optional first-run
  `ADMIN_EMAIL`/`ADMIN_PASSWORD`, each with a one-line comment. README points at it instead of
  restating vars. The dev `shellHook` stays as-is (dev values).
- **README "Deployment" section** — brief: `nix build` → run the shipment's `entrypoint.sh`
  with env from the host's secrets; note the server serves **plain HTTP on `$PORT`** and
  expects a TLS-terminating reverse proxy (and that the cookie `Secure` flag depends on the
  proxy passing `X-Forwarded-Proto`). Documentation only.

## Error handling

- **Config/boot:** fail-fast via panic with a descriptive message (env, schema, seed). The
  process exits non-zero so systemd restarts/reports.
- **CI/checks:** any fmt diff, compiler warning, failed test, or failed `nix build` fails the
  job. The SurrealDB readiness loop in the `server` check `exit 1`s on timeout.
- **Build:** offline-deps determinism comes from `manifest.toml` hashes; a deps/lock mismatch
  fails the build hermetically.

## Testing & verification

- Existing Gleam test suites run unchanged, now driven through `checks.*`.
- `nix flake check` is green on Linux (all three package checks) and on macOS (shared + client;
  server check is linux-gated).
- `nix build .#default` produces a shipment whose `priv/static/` contains `client.js`.
- Manual smoke: run the built `entrypoint.sh` with a populated env against a local SurrealDB;
  confirm it serves the app on `$PORT` and applies the schema, and that a deliberately bad
  `SURREAL_*`/schema makes boot fail fast (non-zero exit).

## Risks

- **`nix-gleam` vs the monorepo/bundle** — mitigated by the spike gate and the FOD fallback.
- **lustre/bun offline bundle** — if `lustre_dev_tools` fetches anything at build time beyond
  the vendored gleam deps, the client derivation needs that input vendored too; surfaced
  during the spike / client-derivation task.
- **Sandbox loopback for the server check** — assumed available on the Linux Nix sandbox; if a
  CI runner disables it, the fallback is to run the server check outside the sandbox in CI
  (still through the flake). Linux-gating already isolates this risk from darwin dev.
