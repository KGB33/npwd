# NPWD Hardening Pass — Design

## Context

An audit of the NPWD server found the codebase fundamentally sound (clean package
separation, bound-parameter queries, consistent ownership gating, real isolated
integration tests) but surfaced five issues to fix before building further. Two block
deployment, one is a correctness landmine, and two are smaller integrity/security items.

This spec covers fixing all five. Work commits directly to `main` (no worktree), each
issue as its own TDD red→green cycle and commit, with `--no-gpg-sign`.

## Locked decisions

- **Config behavior: always fail-fast.** Every environment supplies all config
  explicitly via environment variables. No hardcoded fallbacks. Missing/invalid required
  vars crash at startup with a clear message.
- Keep all five fixes, including the two (4b, 4c) whose fixes are structural and cannot be
  meaningfully verified by an automated test.

## Issues and fixes

### Issue 1 + 2 — Deployability (secret key + DB/port config)

**Problem.** `server.gleam:13` generates `secret_key_base` with `wisp.random_string(64)`
on every startup, so every restart invalidates all signed-cookie sessions and multiple
instances cannot share sessions. `db.default_config()` hardcodes `127.0.0.1:8000` /
`root:root`, and the HTTP listen port is hardcoded `mist.port(3000)`. Nothing reads DB
host, credentials, or ports from the environment, so the app cannot run anywhere but a
developer laptop without editing source.

**Fix.** Introduce explicit env-loading that runs only in `main()`. Tests are unaffected
because `helpers.fresh_config()` constructs `Config` directly.

Add a pure, injectable function in `server/db.gleam`:

```gleam
pub fn config_from_env(get: fn(String) -> Result(String, Nil)) -> Result(Config, String)
```

It reads `SURREAL_HOST`, `SURREAL_PORT`, `SURREAL_NAMESPACE`, `SURREAL_DATABASE`,
`SURREAL_USER`, `SURREAL_PASSWORD`. It returns `Error("<VAR> is required")` on the first
missing var and `Error("<VAR> must be an integer")` when `SURREAL_PORT` does not parse.
On success it returns `Ok(Config)`.

Add a sibling loader for the web tier (in `server.gleam` or a small `config` helper) that
reads `SECRET_KEY_BASE` (required, non-empty) and `PORT` (required, integer) using the
same injectable-`get` pattern so it is unit-testable.

`main()` calls these loaders and `let assert Ok(...)`-crashes with the returned message
when any var is missing or invalid — fail-fast in every environment.

**Local dev / CI.** Set the required vars in the Nix dev shell (`flake.nix` `shellHook`)
with the current local values (`SURREAL_HOST=127.0.0.1`, `SURREAL_PORT=8000`,
`SURREAL_NAMESPACE=npwd`, `SURREAL_DATABASE=npwd`, `SURREAL_USER=root`,
`SURREAL_PASSWORD=root`, `PORT=3000`) plus a fixed dev `SECRET_KEY_BASE` so dev sessions
survive restarts. After `direnv allow`, local dev remains zero-touch. CI runs `gleam test`,
which never calls `main()`, so it needs no new vars.

**Tests.**
- `config_from_env` with a `get` that returns `Error(Nil)` for one var → `Error` naming
  that var.
- `config_from_env` with a `get` supplying all vars → `Ok(Config)` with the parsed values.
- `SURREAL_PORT` non-integer → `Error` mentioning the port.
- The secret-key/port loader: missing `SECRET_KEY_BASE` → `Error`; full set → `Ok`.

### Issue 3 — `+`-corruption in bound-variable transport (highest correctness risk)

**Problem.** `db.run` serializes bound vars into the URL query string
(`request.set_query(vars_query(vars))`, `db.gleam:106`). SurrealDB form-decodes `+` in the
query string to a space, corrupting any user-supplied value containing `+` (node names,
description bodies, emails, filter values). The same transport mangles other special
characters and fails for large values because of URL-length limits.

**Fix.** Stop using the URL query string for variables. Prepend each variable to the
SurrealQL body as a `LET $name = <json>;` statement, where `<json>` is
`json.to_string(value)`. Valid JSON is a valid SurrealQL value literal, and JSON string
escaping makes this injection-safe. `last_result` continues to read the final statement,
so query semantics are unchanged. Existing in-body `LET` statements (subgraph, timeline,
create_description, create_edge) still work: the prepended variable `LET`s are defined
before the query body that references them, and the final `RETURN`/query remains the last
statement. `execute` still sees all statements as `OK`.

Remove `vars_query` and the `set_query` call; build the prepended `LET` block in `run`.

**Tests.**
- Round-trip a node named `"a+b"` (create then read back) and assert the name is intact.
- Round-trip a description body containing `+` and assert it is intact.

### Issue 4a — Edge cross-universe integrity check

**Problem.** `db.create_edge` (`db.gleam:470`) sets `universe` on the new edge but never
verifies that the `from` and `to` nodes belong to that universe, so an owner can create an
edge referencing node IDs from other universes.

**Fix.** Before `RELATE`, verify both endpoints belong to the universe using the existing
`get_node(config, universe, id)` guard (the same pattern `create_description` already uses
for its node). If either lookup fails, return its error and create no edge.

**Tests.**
- Creating an edge whose `from` node belongs to a different universe → error, and
  `list_edges` for the target universe still shows no edge.

### Issue 4d — `create_user` error mapping

**Problem.** `auth.gleam:124` maps every `db.create_user` error to `409 Conflict`, so a
transport or decode failure is reported as "email taken."

**Fix.** Distinguish a unique-constraint violation (a `QueryError` from the duplicate-email
index) from infrastructure failures: `QueryError` → 409, `TransportError` /
`ResultDecodeError` / others → 500.

**Tests.**
- Creating a user with an already-used email → 409 (HTTP-level test).

### Issue 4b — Description position race

**Problem.** `db.create_description` (`db.gleam:406`) computes `position` via `count()` then
`CREATE`s, so two concurrent creates can read the same count and collide.

**Fix.** Wrap the `count`+`CREATE` in `BEGIN TRANSACTION; ... COMMIT TRANSACTION;`.

**Caveat (accepted).** This serializes the statements but does not fully eliminate the race
under SurrealDB's optimistic concurrency; a complete fix would require a non-contiguous
position scheme, which is out of scope. The test can only cover the sequential happy path.

**Tests.**
- Creating three descriptions in sequence yields positions 0, 1, 2 (behavior preserved).

### Issue 4c — Sign-in timing side channel

**Problem.** `auth.gleam:84` returns 401 immediately when an email is unknown, while a known
email pays the full PBKDF2 cost — a user-enumeration timing oracle.

**Fix.** When `find_credentials` returns an error, run `passwords.verify` against a fixed
dummy hash before returning 401, equalizing the timing of the known- and unknown-email
paths.

**Caveat (accepted).** Timing itself is not unit-testable; the test only asserts the
unchanged 401 behavior.

**Tests.**
- Sign-in with an unknown email → 401 (behavior preserved).

## Execution order

Each issue is an independent TDD red→green cycle with its own commit on `main`:

1. Issue 3 (highest risk, strongest test)
2. Issues 1 + 2 (deployability; env loading + dev-shell vars)
3. Issue 4a, then 4d (clean, well-tested)
4. Issue 4b, then 4c (structural; behavior-only tests)

## Out of scope

- Switching the SurrealDB transport to the RPC/WebSocket protocol.
- A non-contiguous description position scheme.
- Any feature work or unrelated refactoring.
