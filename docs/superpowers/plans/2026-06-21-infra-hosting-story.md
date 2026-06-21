# Infrastructure / CI/CD / Hosting Story Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Nix flake the single source of truth for the toolchain, test/lint orchestration, and a reproducible deployable artifact, with CI verifying that artifact on every push, and close the fail-open boot gap.

**Architecture:** The flake gains `packages.default` (server erlang-shipment with the client bundle baked into `priv/static/`), `packages.client` (the bundle), and `checks.<system>` (fmt + `gleam check` + tests, server check starts an in-sandbox SurrealDB). CI collapses to `nix flake check` + `nix build`. Offline hex deps come from `manifest.toml` hashes via `arnarg/nix-gleam`, with a hand-rolled fixed-output-derivation (FOD) fallback gated behind a spike. A small Gleam change makes boot atomically fail-fast.

**Tech Stack:** Nix (flake-parts), `arnarg/nix-gleam`, Gleam (Erlang target for server, JavaScript target for client), lustre/bun bundler, SurrealDB, GitHub Actions, DeterminateSystems nix-installer + magic-nix-cache.

## Global Constraints

- Commit directly to `main`. No worktree, no feature branch.
- Every commit uses `--no-gpg-sign`.
- Commit message footer (both lines, verbatim):
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r`
- Run `gleam format` only on `.gleam` files you create or edit. Do NOT mass-reformat (the repo has a known gleam-format skew on untouched files).
- nixpkgs stays on `nixos-unstable`; reproducibility comes from `flake.lock`. Run `nix flake lock` (never `nix flake update`) when adding an input, so only the new input is locked.
- The deployable artifact serves plain HTTP on `$PORT` and reads all config from env vars per `server/src/server/env.gleam` (fail-fast). No secrets, NixOS module, systemd unit, SurrealDB provisioning, or TLS config belong in this repo.
- Source of truth for the required env contract is `server/src/server/env.gleam`: `SURREAL_HOST`, `SURREAL_PORT`, `SURREAL_NAMESPACE`, `SURREAL_DATABASE`, `SURREAL_USER`, `SURREAL_PASSWORD`, `SECRET_KEY_BASE`, `PORT` (all required); `ADMIN_EMAIL`, `ADMIN_PASSWORD` (optional, first-run seed only).

---

## Task 1: Atomic fail-fast boot

**Files:**
- Modify: `server/src/server/db.gleam` (add `import gleam/int`; add public `error_to_string`)
- Modify: `server/src/server.gleam` (fail-fast `apply_schema`; fail-fast `seed_admin`)
- Test: `server/test/db_error_test.gleam` (create)

**Interfaces:**
- Consumes: existing `db.DbError` variants — `TransportError`, `ResponseError(status: Int, body: String)`, `QueryError(detail: String)`, `ResultDecodeError`, `NoResult`, `NotFound`, `SchemaError`, `InvalidInput`.
- Produces: `pub fn db.error_to_string(error: DbError) -> String` — a human-readable, non-empty message for every variant, used in boot panic messages.

- [ ] **Step 1: Write the failing test**

Create `server/test/db_error_test.gleam`:

```gleam
import server/db

pub fn query_error_includes_detail_test() {
  assert db.error_to_string(db.QueryError("boom")) == "query error: boom"
}

pub fn response_error_includes_status_and_body_test() {
  assert db.error_to_string(db.ResponseError(500, "nope"))
    == "unexpected HTTP 500: nope"
}

pub fn transport_error_is_described_test() {
  assert db.error_to_string(db.TransportError)
    == "transport error: could not reach SurrealDB"
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `gleam test` (from `server/`)
Expected: FAIL to compile — `db.error_to_string` does not exist.

- [ ] **Step 3: Add `error_to_string`**

In `server/src/server/db.gleam`, add `import gleam/int` to the import block (it is not currently imported; keep imports alphabetically grouped near `gleam/httpc`/`gleam/json`). Then add this public function immediately after the `DbError` type (after line 37):

```gleam
pub fn error_to_string(error: DbError) -> String {
  case error {
    TransportError -> "transport error: could not reach SurrealDB"
    ResponseError(status, body) ->
      "unexpected HTTP " <> int.to_string(status) <> ": " <> body
    QueryError(detail) -> "query error: " <> detail
    ResultDecodeError -> "could not decode SurrealDB response"
    NoResult -> "query returned no result"
    NotFound -> "record not found"
    SchemaError -> "schema error"
    InvalidInput -> "invalid input"
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `gleam test` (from `server/`)
Expected: the three `db_error_test` tests PASS; all existing tests still PASS.

- [ ] **Step 5: Make boot fail-fast**

In `server/src/server.gleam`, replace the body of `main` from the `let config = loaded.config` line through the `seed_admin(config)` call:

```gleam
  let config = loaded.config
  let _ = db.apply_schema(config)
  seed_admin(config)
```

with:

```gleam
  let config = loaded.config
  case db.apply_schema(config) {
    Ok(_) -> Nil
    Error(e) -> panic as { "schema apply failed: " <> db.error_to_string(e) }
  }
  seed_admin(config)
```

Then replace the whole `seed_admin` function:

```gleam
fn seed_admin(config: db.Config) -> Nil {
  case
    db.count_users(config),
    envoy.get("ADMIN_EMAIL"),
    envoy.get("ADMIN_PASSWORD")
  {
    Ok(0), Ok(email), Ok(password) -> {
      let _ = db.create_user(config, email, passwords.hash(password), True)
      Nil
    }
    _, _, _ -> Nil
  }
}
```

with:

```gleam
fn seed_admin(config: db.Config) -> Nil {
  case db.count_users(config) {
    Ok(0) ->
      case envoy.get("ADMIN_EMAIL"), envoy.get("ADMIN_PASSWORD") {
        Ok(email), Ok(password) ->
          case db.create_user(config, email, passwords.hash(password), True) {
            Ok(_) -> Nil
            Error(e) ->
              panic as { "admin seed failed: " <> db.error_to_string(e) }
          }
        _, _ -> Nil
      }
    Ok(_) -> Nil
    Error(e) -> panic as { "user count failed: " <> db.error_to_string(e) }
  }
}
```

- [ ] **Step 6: Verify build and full suite are green**

Run: `gleam build && gleam test` (from `server/`)
Expected: build succeeds, all tests PASS. (The panic paths are not unit-tested — `panic` aborts the runner; they are exercised by the real boot path. `error_to_string`, the testable unit, is covered by Step 1.)

- [ ] **Step 7: Format and commit**

```bash
cd server && gleam format src/server/db.gleam src/server.gleam test/db_error_test.gleam && cd ..
git add server/src/server/db.gleam server/src/server.gleam server/test/db_error_test.gleam
git commit --no-gpg-sign -m "fix(server): fail fast when schema apply or admin seed fails

env.load already panics on bad config, but apply_schema and seed_admin
swallowed their Result, letting the server boot and serve a broken app.
Panic with a descriptive message instead, via a new db.error_to_string.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

---

## Task 2: Canonical env contract (`.env.example`) + README pointer

**Files:**
- Create: `.env.example`
- Modify: `README.md` (point §3 at `.env.example` instead of restating vars inline)

**Interfaces:**
- Consumes: the env contract from `server/src/server/env.gleam` (see Global Constraints).
- Produces: `.env.example` at repo root, referenced by README and (later) the Deployment section in Task 8.

- [ ] **Step 1: Create `.env.example`**

Create `.env.example` at the repo root:

```sh
# NPWD server configuration. All variables below are required at startup
# (server/src/server/env.gleam fails fast if any is missing or empty).
# Copy to .env and fill in, or export these in your process manager.

# SurrealDB connection (server talks to SurrealDB over HTTP)
SURREAL_HOST=127.0.0.1
SURREAL_PORT=8000
SURREAL_NAMESPACE=npwd
SURREAL_DATABASE=npwd
SURREAL_USER=root
SURREAL_PASSWORD=changeme

# Signing key for the session cookie. Generate a long random value, e.g.
#   gleam run -m wisp -- gen-secret   (or: openssl rand -base64 64)
SECRET_KEY_BASE=change-me-to-a-long-random-secret

# HTTP listen port for the server
PORT=3000

# Optional: only used on first boot, when the user table is empty, to seed
# one admin. Omit on subsequent runs.
# ADMIN_EMAIL=you@example.com
# ADMIN_PASSWORD=changeme
```

- [ ] **Step 2: Point the README at it**

In `README.md`, in the "### 3. Start the server" section, replace the existing run snippet:

```sh
cd server
ADMIN_EMAIL=you@example.com ADMIN_PASSWORD=changeme gleam run
```

with:

```sh
cd server
# Config is read from the environment; the Nix dev shell exports dev values.
# See `.env.example` at the repo root for the full contract. To seed the
# first admin, also export ADMIN_EMAIL and ADMIN_PASSWORD on the first run:
ADMIN_EMAIL=you@example.com ADMIN_PASSWORD=changeme gleam run
```

- [ ] **Step 3: Verify**

Run: `cat .env.example` and confirm all eight required vars from the Global Constraints contract are present plus the two optional admin vars.
Expected: the file lists exactly that set.

- [ ] **Step 4: Commit**

```bash
git add .env.example README.md
git commit --no-gpg-sign -m "docs: add .env.example as the canonical config contract

server/src/server/env.gleam is the source of truth for required env vars;
.env.example documents that contract for deployment and onboarding.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

---

## Task 3: Spike — offline Gleam build mechanism via `nix-gleam`

**Goal of this task:** pick and prove the offline server-build mechanism. This is the one task with a discovery component; downstream tasks depend on the exact derivation it establishes. End state is a flake that can build the server offline in the sandbox.

**Files:**
- Modify: `flake.nix` (add `nix-gleam` input + overlay; add a `packages.server` attribute)
- Modify: `flake.lock` (via `nix flake lock`)

**Interfaces:**
- Consumes: `manifest.toml` (exact dep versions + sha256 hashes) for `shared` and `server`; `gleam.toml` files.
- Produces: `packages.server` — a derivation whose `$out` contains the server erlang-shipment (an `entrypoint.sh` plus `lib/*/priv` trees), built with no network access. Task 5 reuses this build to produce `packages.default`; Task 6 reuses the offline-deps approach for checks.

- [ ] **Step 1: Read the tool's interface**

Run: `nix flake show github:arnarg/nix-gleam` and open its README (`https://github.com/arnarg/nix-gleam`). Note the exact builder name and its arguments (expected: an overlay exposing `buildGleamApplication { src; ... }`, plus how it locates `manifest.toml` and how it handles `target = "erlang"` vs path dependencies).

- [ ] **Step 2: Add the input and overlay to `flake.nix`**

In `flake.nix`, add to `inputs`:

```nix
    nix-gleam.url = "github:arnarg/nix-gleam";
```

In `perSystem`, add the overlay to the `pkgs` import so `buildGleamApplication` is available:

```nix
        pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [inputs.nix-gleam.overlays.default];
          config.allowUnfreePredicate = pkg:
            builtins.elem (inputs.nixpkgs.lib.getName pkg) ["surrealdb"];
        };
```

- [ ] **Step 3: Add a minimal `packages.server`**

In the `perSystem` return set, add (the monorepo `shared` path dep means `src` must include `shared/`; pass the repo root and point the builder at the server package — adjust attribute names to match what Step 1 found):

```nix
        packages.server = pkgs.buildGleamApplication {
          src = ./.;
          # Build only the server package (Erlang target). If the builder needs
          # the package directory rather than the repo root, set src = ./server
          # and add ../shared as a localPackages/extra source per its README.
          # The goal output is a `gleam export erlang-shipment` tree.
        };
```

- [ ] **Step 4: Lock and build**

```bash
nix flake lock
nix build .#server -L
```

Expected (success branch): build completes offline; `ls result/` shows an `entrypoint.sh` (and a `lib/` tree). Verify the server app's static dir exists somewhere under the output:

```bash
find result -type d -path '*server/priv/static'
```

- [ ] **Step 5: If the builder cannot handle the monorepo, switch to the FOD fallback**

If Step 4 fails because `buildGleamApplication` cannot resolve the `shared` path dependency or the JavaScript/dev deps, replace `packages.server` with a hand-rolled two-derivation build in `flake.nix`:

```nix
        # Fixed-output derivation: fetch all hex deps named in the manifests.
        # Update the hash once with the value Nix reports on first build.
        gleamDeps = pkgs.stdenvNoCC.mkDerivation {
          name = "npwd-gleam-deps";
          src = ./.;
          nativeBuildInputs = [pkgs.gleam pkgs.cacert];
          buildPhase = ''
            export HEX_HOME=$TMPDIR/hex GLEAM_CACHE=$out
            (cd server && gleam deps download)
          '';
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = pkgs.lib.fakeHash; # replace with reported hash, then rebuild
        };
        packages.server = pkgs.stdenv.mkDerivation {
          name = "npwd-server";
          src = ./.;
          nativeBuildInputs = [pkgs.gleam pkgs.erlang_27 pkgs.rebar3];
          buildPhase = ''
            export GLEAM_CACHE=${gleamDeps}
            (cd server && gleam export erlang-shipment)
          '';
          installPhase = "cp -r server/build/erlang-shipment $out";
        };
```

Run `nix build .#server -L`, copy the `got:` hash it reports into `outputHash`, and rebuild until green. (`gleam deps download`/`GLEAM_CACHE` are the offline-deps levers; confirm the exact cache env var name from `gleam --help` if it differs in 1.17.0.)

- [ ] **Step 6: Record the decision**

Add a one-line comment above `packages.server` in `flake.nix` stating which mechanism is in use (`nix-gleam` or `FOD`), so Tasks 5 and 6 follow the same approach.

- [ ] **Step 7: Verify the dev shell still loads**

Run: `nix develop --command gleam --version`
Expected: prints the Gleam version (the added overlay/input did not break `devShells.default`).

- [ ] **Step 8: Commit**

```bash
git add flake.nix flake.lock
git commit --no-gpg-sign -m "build(nix): offline server erlang-shipment via packages.server

Add the offline Gleam build mechanism (nix-gleam, FOD fallback if the
monorepo path dep is unsupported). manifest.toml hashes make the deps
deterministic; the build runs with no network in the sandbox.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

---

## Task 4: `packages.client` — the client bundle derivation

**Files:**
- Modify: `flake.nix` (add `packages.client`)

**Interfaces:**
- Consumes: the offline-deps mechanism established in Task 3 (same `nix-gleam` deps output or the `gleamDeps` FOD); `pkgs.bun`, `pkgs.gleam`.
- Produces: `packages.client` — a derivation whose `$out/client.js` is the bundled Lustre app. Task 5 injects this file into the server shipment's `priv/static/`.

- [ ] **Step 1: Add `packages.client` to `flake.nix`**

In the `perSystem` return set, add a derivation that runs the same bundle command the README documents (`gleam run -m lustre/dev build`), offline, with `bun` from nixpkgs (the `client/gleam.toml` already sets `[tools.lustre.bin] bun = "system"`):

```nix
        packages.client = pkgs.stdenv.mkDerivation {
          name = "npwd-client";
          src = ./.;
          nativeBuildInputs = [pkgs.gleam pkgs.bun pkgs.erlang_27 pkgs.rebar3];
          buildPhase = ''
            # Prime the offline Gleam dep cache exactly as Task 3 does
            # (GLEAM_CACHE=${"$"}{gleamDeps} for the FOD path, or the nix-gleam
            # deps output). bun is on PATH so the lustre bundler uses it.
            export HOME=$TMPDIR
            (cd client && gleam run -m lustre/dev build --outdir=build/static)
          '';
          installPhase = "install -Dm644 client/build/static/client.js $out/client.js";
        };
```

- [ ] **Step 2: Build it**

Run: `nix build .#client -L`
Expected: build completes offline; `test -f result/client.js && head -c 80 result/client.js` prints the start of a JS bundle.

- [ ] **Step 3: If the bundler fetches anything at build time**

If the build fails on a network fetch (e.g. `lustre_dev_tools` downloading a binary), pin that input as a Nix dependency: add it to `nativeBuildInputs` (for a binary like `esbuild`) or vendor it into the deps cache, and re-run. The `bun = "system"` setting should already prevent the bun download; confirm no `esbuild` download remains by reading the build log.

- [ ] **Step 4: Commit**

```bash
git add flake.nix
git commit --no-gpg-sign -m "build(nix): reproducible client bundle via packages.client

Replaces the manual 'gleam run ... && cp client.js' from README §1 with a
derivation that builds the Lustre bundle offline using the nixpkgs bun.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

---

## Task 5: `packages.default` — server shipment with the client baked in

**Files:**
- Modify: `flake.nix` (add `packages.default` that injects the client bundle into the server build)
- Modify: `README.md` (note that `client.js` is now built by `nix build`, in §1)

**Interfaces:**
- Consumes: `packages.server` (Task 3) and `packages.client` (Task 4).
- Produces: `packages.default` — the deployable artifact: the server erlang-shipment with `packages.client`'s `client.js` present at the server app's `priv/static/client.js`. Running `result/.../entrypoint.sh` with the env contract starts the app. Task 7 (CI) builds this; Task 8 documents running it.

- [ ] **Step 1: Add `packages.default` to `flake.nix`**

Build `packages.default` by injecting the client bundle into the server build. Prefer doing it inside the server derivation so there is one artifact. If using `nix-gleam`, add a `preBuild`/`postPatch` that copies the bundle into the source tree before the shipment is assembled; if using the FOD path, add the copy to the server `buildPhase` before `gleam export`. Concretely, define `packages.default` as the server build with this extra step:

```nix
        # nix-gleam path: pass an attribute to copy the bundle in before build,
        #   postPatch = "cp ${"$"}{packages.client}/client.js server/priv/static/client.js";
        # FOD path: add the same cp as the first line of the server buildPhase.
        packages.default = packages.server.overrideAttrs (old: {
          postPatch =
            (old.postPatch or "")
            + "\ncp ${packages.client}/client.js server/priv/static/client.js\n";
        });
```

(If `overrideAttrs` does not fit the builder, inline the same server derivation with the `cp` added and name it `packages.default`; keep `packages.server` as the bundle-free build for Task 6 reuse.)

- [ ] **Step 2: Build and verify the bundle is baked in**

```bash
nix build .#default -L
find result -path '*server/priv/static/client.js'
```

Expected: the build succeeds and `find` prints a path — the shipment contains `client.js`. Also confirm the entrypoint exists:

```bash
find result -name entrypoint.sh
```

Expected: prints the shipment entrypoint path.

- [ ] **Step 3: Update README §1**

In `README.md`, at the end of the "### 1. Build the client bundle" section, add:

```markdown
> For a deployable build you do not run this by hand: `nix build` (see
> **Deployment** below) builds the client bundle and bakes it into the
> server artifact automatically.
```

- [ ] **Step 4: Commit**

```bash
git add flake.nix README.md
git commit --no-gpg-sign -m "build(nix): packages.default bakes the client into the server shipment

One reproducible artifact: the server erlang-shipment with client.js at
priv/static. nix build replaces the documented manual cp; running the
shipment entrypoint with the env contract starts the app.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

---

## Task 6: `checks.<system>` — fmt + `gleam check` + tests

**Files:**
- Modify: `flake.nix` (add `checks` for `shared`, `client`, `server`)

**Interfaces:**
- Consumes: the offline-deps mechanism from Task 3; `pkgs.gleam`, `pkgs.surrealdb` (already in the flake).
- Produces: `checks.<system>.{shared,client,server}`. `shared` and `client` run on all systems; `server` runs on Linux only (needs the in-sandbox SurrealDB on loopback). Each runs `gleam format --check src test` + `gleam check --warnings-as-errors` + `gleam test`. Task 7 (CI) runs all of these via `nix flake check`.

- [ ] **Step 1: Add the no-DB checks (`shared`, `client`)**

In `perSystem`, add a helper and two checks. Each is a derivation that primes the offline deps cache (same as Task 3/4), then runs fmt + check + test in the package:

```nix
        mkGleamCheck = name: pkgs.stdenv.mkDerivation {
          name = "check-${name}";
          src = ./.;
          nativeBuildInputs = [pkgs.gleam pkgs.erlang_27 pkgs.rebar3 pkgs.bun];
          buildPhase = ''
            export HOME=$TMPDIR
            # Prime the offline dep cache exactly as Task 3 established.
            cd ${name}
            gleam format --check src test
            gleam check --warnings-as-errors
            gleam test
            touch $out
          '';
          phases = ["unpackPhase" "buildPhase"];
        };
        checks.shared = mkGleamCheck "shared";
        checks.client = mkGleamCheck "client";
```

- [ ] **Step 2: Run the no-DB checks**

```bash
nix build .#checks.$(nix eval --raw --impure --expr builtins.currentSystem).shared -L
nix build .#checks.$(nix eval --raw --impure --expr builtins.currentSystem).client -L
```

Expected: both succeed (fmt clean, no warnings, tests pass). If `gleam check --warnings-as-errors` reports a pre-existing warning in `shared`/`client`, fix that warning in the offending `.gleam` file (and `gleam format` it) before continuing.

- [ ] **Step 3: Add the Linux-only `server` check with SurrealDB**

Add a server check that starts an in-memory SurrealDB on loopback, waits with a bounded loop that fails on timeout, then runs the suite. Guard it to Linux so `nix flake check` on macOS skips it:

```nix
        checks.server =
          pkgs.lib.mkIf pkgs.stdenv.isLinux
          (pkgs.stdenv.mkDerivation {
            name = "check-server";
            src = ./.;
            nativeBuildInputs = [
              pkgs.gleam
              pkgs.erlang_27
              pkgs.rebar3
              pkgs.surrealdb
              pkgs.curl
            ];
            buildPhase = ''
              export HOME=$TMPDIR
              surreal start --user root --pass root \
                --bind 127.0.0.1:8001 memory &
              ready=0
              for _ in $(seq 1 30); do
                if curl -sf http://127.0.0.1:8001/health; then ready=1; break; fi
                sleep 1
              done
              if [ "$ready" -ne 1 ]; then
                echo "SurrealDB did not become ready" >&2
                exit 1
              fi
              # Prime the offline dep cache exactly as Task 3 established.
              cd server
              gleam format --check src test
              gleam check --warnings-as-errors
              gleam test
              touch $out
            '';
            phases = ["unpackPhase" "buildPhase"];
          });
```

- [ ] **Step 4: Run `nix flake check`**

Run: `nix flake check -L`
Expected (on Linux): all three checks build green — including the server check, which proves loopback SurrealDB works in the sandbox. If the sandbox blocks `surreal` from binding loopback, record it and fall back per the spec's risk note (run the server check outside the sandbox in CI, still via the flake); the `shared`/`client` checks stay sandboxed.

- [ ] **Step 5: Commit**

```bash
git add flake.nix
git commit --no-gpg-sign -m "build(nix): wire fmt + gleam check + tests into flake checks

checks.{shared,client,server} run gleam format --check, gleam check
--warnings-as-errors, and gleam test. The server check starts an
in-sandbox SurrealDB on loopback (Linux only); macOS skips it.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

---

## Task 7: Replace CI with `nix flake check` + `nix build`

**Files:**
- Delete: `.github/workflows/test.yml`
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `checks.<system>` (Task 6) and `packages.default` (Task 5) — both run through the flake.
- Produces: a single CI job that runs `nix flake check` and `nix build .#default`, with Nix-based caching. No version pins, no `setup-beam`/`setup-node`, no `docker run` poll loop, no per-package duplication, no `master` trigger.

- [ ] **Step 1: Remove the old workflow**

Run: `git rm .github/workflows/test.yml`
Expected: the file is staged for deletion.

- [ ] **Step 2: Create the new workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: ci

on:
  push:
    branches:
      - main
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: DeterminateSystems/nix-installer-action@main
      - uses: DeterminateSystems/magic-nix-cache-action@main
      - name: flake check (fmt + gleam check + tests)
        run: nix flake check -L
      - name: build the deployable artifact
        run: nix build .#default -L
```

- [ ] **Step 3: Validate the workflow locally the way CI will run it**

Run (from the repo root, on Linux): `nix flake check -L && nix build .#default -L`
Expected: both succeed — this is exactly what the CI job runs, so green here means green in CI. (Confirm the YAML is well-formed: `nix run nixpkgs#yamllint -- .github/workflows/ci.yml` should report no syntax errors; ignore style-only warnings.)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git rm --cached .github/workflows/test.yml 2>/dev/null || true
git commit --no-gpg-sign -m "ci: run everything through the flake (nix flake check + nix build)

Replaces the bespoke setup-beam/setup-node/docker-run workflow with one
job that runs nix flake check and nix build .#default. The flake is now
the single source of truth for toolchain, lint, tests, and the artifact;
caching comes from magic-nix-cache. Drops the dead master trigger.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

- [ ] **Step 5: Push and confirm CI is green**

```bash
git push
```

Then check the run: `gh run watch` (or `gh run list --branch main --limit 1`).
Expected: the `check` job succeeds.

---

## Task 8: README Deployment section + final verification

**Files:**
- Modify: `README.md` (add a "## Deployment" section)

**Interfaces:**
- Consumes: `packages.default` (Task 5), `.env.example` (Task 2).
- Produces: end-user deployment docs. No code.

- [ ] **Step 1: Add the Deployment section**

In `README.md`, after the "### 4. Open the app" section, add:

```markdown
## Deployment

Build the self-contained artifact (server + client bundle) with Nix:

\`\`\`sh
nix build .#default
\`\`\`

`result/` is an Erlang shipment with an `entrypoint.sh`. It reads all
configuration from the environment — see `.env.example` for the full
contract. Run it under your process manager (e.g. a systemd unit) with the
env populated from your secrets store:

\`\`\`sh
env $(grep -v '^#' /run/secrets/npwd.env | xargs) result/erlang-shipment/entrypoint.sh run
\`\`\`

The server serves **plain HTTP on `$PORT`** and expects a TLS-terminating
reverse proxy in front of it. For the session cookie to carry the `Secure`
attribute, the proxy must pass `X-Forwarded-Proto: https`. SurrealDB, TLS,
secrets, and the systemd unit are provisioned in your host configuration,
not in this repo.
```

(Replace the `entrypoint.sh` path with the actual one found in Task 5 Step 2 if it differs.)

- [ ] **Step 2: Final full verification**

Run from the repo root (on Linux):

```bash
nix flake check -L
nix build .#default -L
git log --oneline -8
```

Expected: checks and build are green; `git log` shows the Task 1–8 commits on `main`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit --no-gpg-sign -m "docs: add Deployment section for the nix-built artifact

Documents nix build .#default, running the shipment entrypoint with the
env contract, and the plain-HTTP/reverse-proxy + X-Forwarded-Proto
expectation.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

---

## Final verification

After all eight tasks:

- [ ] `nix flake check -L` is green on Linux (shared + client + server checks).
- [ ] `nix build .#default -L` produces a shipment whose `priv/static/` contains `client.js` and which has an `entrypoint.sh`.
- [ ] CI (`.github/workflows/ci.yml`) is green on `main`; `test.yml` is gone.
- [ ] `git log --oneline` shows the eight commits.
- [ ] Manual smoke (optional): run the shipment entrypoint with a populated env against a local SurrealDB; confirm it serves on `$PORT`, and that a deliberately wrong `SURREAL_PASSWORD` makes boot exit non-zero with a "schema apply failed" message.
