# NPWD Hardening Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the five issues from the hardening audit: the `+`-corruption transport bug, fail-fast env-based config (secret key + DB + port), edge cross-universe integrity, `create_user` error mapping, the description position race, and the sign-in timing side channel.

**Architecture:** Server-side changes only, in the existing `server/` Gleam package. Database access stays centralized in `server/db.gleam`; all environment parsing moves into a new `server/env.gleam`. Each issue is an independent TDD red→green cycle with its own commit on `main`.

**Tech Stack:** Gleam (Erlang target), wisp/mist, SurrealDB over HTTP, gleeunit + `wisp/simulate` for tests, `envoy` for env vars.

## Global Constraints

- Commit directly to `main`. No worktree, no feature branch.
- Every commit uses `--no-gpg-sign`.
- Commit message footer (both lines):
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r`
- Run `gleam format` on every `.gleam` file you create or edit (CI runs `gleam format --check`). Do NOT reformat files you did not touch (the repo has a known gleam-format skew).
- Tests need a SurrealDB on `127.0.0.1:8001` (namespace `test`). Start it the same way CI does if it is not already running:
  `docker run -d --name surreal -p 8001:8000 surrealdb/surrealdb:v2.6.1 start --user root --pass root --bind 0.0.0.0:8000 memory`
  (Locally, `surrealdb` from the Nix dev shell can be used instead: `surreal start --user root --pass root --bind 127.0.0.1:8001 memory`.)
- Run server tests from the `server/` directory with `gleam test`.
- Config behavior is **fail-fast everywhere**: missing/invalid env vars crash at startup. No hardcoded fallbacks remain in application code.

---

## Task 1: Fix the `+`-corruption bound-variable transport

**Files:**
- Modify: `server/src/server/db.gleam` (the private `run`/`vars_query`, plus `create_node`/`update_node` and a new `fields_json` helper)
- Modify: `shared/src/shared.gleam` (remove now-unused `node_content_to_json`, if no other caller)
- Test: `server/test/node_db_test.gleam`, `server/test/description_db_test.gleam`

**Interfaces:**
- Consumes: existing `shared.field_value_to_json`.
- Produces: no public signature changes to `db` functions. `run`, `query`, `query_vars`, `query_first`, `execute`, `create_node`, `update_node` keep their current signatures and behavior; only the wire transport for variables and the internal SurrealQL of the two node writes change.

**Background:** Today `run` serializes variables into the URL query string via `request.set_query(vars_query(vars))` (`db.gleam:106`). SurrealDB form-decodes `+` in the query string to a space, corrupting any user value containing `+`. The fix prepends each variable to the SurrealQL body as a `LET $name = <json>;` statement, so values travel in the request body where JSON encoding is lossless and injection-safe. `last_result` still reads the final statement (the prepended `LET`s come first), so query semantics are unchanged.

- [ ] **Step 1: Write the failing tests**

Add to `server/test/node_db_test.gleam`:

```gleam
pub fn name_with_plus_round_trips_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let assert Ok(node) = db.create_node(config, u, "a+b", "Place", dict.new())
  assert node.name == "a+b"
  let assert Ok(fetched) = db.get_node(config, u, node.id)
  assert fetched.name == "a+b"
}
```

Add to `server/test/description_db_test.gleam`:

```gleam
pub fn body_with_plus_round_trips_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let n = node(config, u, "Shire")
  let assert Ok(d) = db.create_description(config, u, n, "1 + 1 = 2")
  assert d.body == "1 + 1 = 2"
  let assert Ok(ds) = db.list_descriptions(config, u, n)
  assert bodies(ds) == ["1 + 1 = 2"]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `gleam test` (from `server/`)
Expected: both new tests FAIL — the `+` is stored/returned as a space, so `node.name == "a+b"` and the body assertion are false. (If either test PASSES before the fix, stop and investigate: the corruption may manifest differently than assumed.)

- [ ] **Step 3: Implement the body-based variable transport**

In `server/src/server/db.gleam`, replace the `run` function so it builds a `LET` prelude in the body and drops `set_query`. Replace this block:

```gleam
fn run(
  config: Config,
  surql: String,
  vars: List(#(String, Json)),
) -> Result(List(Statement), DbError) {
  let credentials =
    bit_array.base64_encode(
      bit_array.from_string(config.user <> ":" <> config.password),
      True,
    )
  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_scheme(http.Http)
    |> request.set_host(config.host)
    |> request.set_port(config.port)
    |> request.set_path("/sql")
    |> request.set_query(vars_query(vars))
    |> request.set_header("accept", "application/json")
    |> request.set_header("content-type", "text/plain")
    |> request.set_header("surreal-ns", config.namespace)
    |> request.set_header("surreal-db", config.database)
    |> request.set_header("authorization", "Basic " <> credentials)
    |> request.set_body(surql)

  use response <- result.try(
    httpc.send(req) |> result.replace_error(TransportError),
  )
  case response.status {
    200 ->
      json.parse(response.body, decode.list(statement_decoder()))
      |> result.replace_error(ResultDecodeError)
    status -> Error(ResponseError(status, response.body))
  }
}

fn vars_query(vars: List(#(String, Json))) -> List(#(String, String)) {
  list.map(vars, fn(v) { #(v.0, json.to_string(v.1)) })
}
```

with:

```gleam
fn run(
  config: Config,
  surql: String,
  vars: List(#(String, Json)),
) -> Result(List(Statement), DbError) {
  let credentials =
    bit_array.base64_encode(
      bit_array.from_string(config.user <> ":" <> config.password),
      True,
    )
  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_scheme(http.Http)
    |> request.set_host(config.host)
    |> request.set_port(config.port)
    |> request.set_path("/sql")
    |> request.set_header("accept", "application/json")
    |> request.set_header("content-type", "text/plain")
    |> request.set_header("surreal-ns", config.namespace)
    |> request.set_header("surreal-db", config.database)
    |> request.set_header("authorization", "Basic " <> credentials)
    |> request.set_body(let_prelude(vars) <> surql)

  use response <- result.try(
    httpc.send(req) |> result.replace_error(TransportError),
  )
  case response.status {
    200 ->
      json.parse(response.body, decode.list(statement_decoder()))
      |> result.replace_error(ResultDecodeError)
    status -> Error(ResponseError(status, response.body))
  }
}

fn let_prelude(vars: List(#(String, Json))) -> String {
  list.fold(vars, "", fn(acc, v) {
    acc <> "LET $" <> v.0 <> " = " <> json.to_string(v.1) <> ";\n"
  })
}
```

Note: the `list` and `json` imports are already present. After this edit `set_query` is no longer referenced; leave the `gleam/http/request` import (still used for the other `request.*` calls).

- [ ] **Step 3b: Decompose the node CONTENT writes so record links still coerce**

The body-based transport changes one coercion behavior: SurrealDB 2.6.1 coerces a plain string like `"universe:abc"` into a `record<universe>` field when it arrives as a query-string param, but a string bound via a `LET` JSON literal stays a strict `string` and is rejected by `CONTENT`-typed `record<...>` fields. `create_node` and `update_node` are the only writes that bury a record id (`universe`) inside a `CONTENT $data` blob; every other write already wraps record ids with `type::thing($x)`. Fix those two to build the content object in SurrealQL with `type::thing($u)` and pass the other fields as separate bound vars.

Add this helper near the other private helpers in `server/src/server/db.gleam`:

```gleam
fn fields_json(fields: dict.Dict(String, shared.FieldValue)) -> Json {
  json.dict(fields, fn(k) { k }, shared.field_value_to_json)
}
```

Replace `create_node` with:

```gleam
pub fn create_node(
  config: Config,
  universe: String,
  name: String,
  kind: String,
  fields: dict.Dict(String, shared.FieldValue),
) -> Result(shared.Node, DbError) {
  use <- require_valid([universe])
  query_first(
    config,
    "CREATE node CONTENT { universe: type::thing($u), name: $name, kind: $kind, fields: $fields }",
    [
      #("u", json.string(universe)),
      #("name", json.string(name)),
      #("kind", json.string(kind)),
      #("fields", fields_json(fields)),
    ],
    shared.node_decoder(),
  )
}
```

Replace `update_node` with:

```gleam
pub fn update_node(
  config: Config,
  universe: String,
  id: String,
  name: String,
  kind: String,
  fields: dict.Dict(String, shared.FieldValue),
) -> Result(shared.Node, DbError) {
  use <- require_valid([id, universe])
  query_first(
    config,
    "UPDATE type::thing($id) CONTENT { universe: type::thing($u), name: $name, kind: $kind, fields: $fields } WHERE universe = type::thing($u)",
    [
      #("id", json.string(id)),
      #("u", json.string(universe)),
      #("name", json.string(name)),
      #("kind", json.string(kind)),
      #("fields", fields_json(fields)),
    ],
    shared.node_decoder(),
  )
}
```

This leaves `shared.node_content_to_json` unused. Run `grep -rn node_content_to_json --include=*.gleam` from the repo root; if `server/src/server/db.gleam` is the only (now-removed) caller, delete `node_content_to_json` from `shared/src/shared.gleam`. If any other caller exists (client or a test), leave it in place.

- [ ] **Step 4: Run the full suite to verify green**

Run: `gleam test` (from `server/`)
Expected: the two new tests PASS and ALL existing tests still PASS — including every node/edge/description/timeline/HTTP test, which confirms record-link coercion now works through the body-based transport.

- [ ] **Step 5: Format and commit**

```bash
cd server && gleam format src/server/db.gleam test/node_db_test.gleam test/description_db_test.gleam && cd ..
# include shared/src/shared.gleam in the add only if node_content_to_json was removed
git add server/src/server/db.gleam server/test/node_db_test.gleam server/test/description_db_test.gleam shared/src/shared.gleam
git commit --no-gpg-sign -m "fix(db): send bound variables in body, not query string

The query-string transport let SurrealDB form-decode '+' to a space,
corrupting any value containing it. Send variables as LET statements in
the request body instead, which is lossless and injection-safe. Build the
node CONTENT object with type::thing(\$u) so record links still coerce
under the body transport.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

---

## Task 2: Fail-fast env-based configuration (secret key + DB + port)

**Files:**
- Create: `server/src/server/env.gleam`
- Create: `server/test/env_test.gleam`
- Modify: `server/src/server.gleam` (replace `db.default_config()` + `wisp.random_string(64)` + `mist.port(3000)`)
- Modify: `server/src/server/db.gleam` (remove `default_config`, lines 63–72)
- Modify: `flake.nix` (add a `shellHook` exporting dev env vars)

**Interfaces:**
- Consumes: `db.Config` (record with fields `host: String, port: Int, namespace: String, database: String, user: String, password: String`).
- Produces:
  - `pub type Env { Env(config: db.Config, secret_key_base: String, port: Int) }`
  - `pub fn env.load(get: fn(String) -> Result(String, Nil)) -> Result(Env, String)` — reads all config from the injected getter; returns `Error("<VAR> is required")` on the first missing var and `Error("<VAR> must be an integer")` when `SURREAL_PORT` or `PORT` does not parse.

- [ ] **Step 1: Write the failing tests**

Create `server/test/env_test.gleam`:

```gleam
import gleam/dict
import gleam/list
import server/env

fn getter(vars: List(#(String, String))) -> fn(String) -> Result(String, Nil) {
  let d = dict.from_list(vars)
  fn(name) { dict.get(d, name) }
}

fn all() -> List(#(String, String)) {
  [
    #("SURREAL_HOST", "127.0.0.1"),
    #("SURREAL_PORT", "8000"),
    #("SURREAL_NAMESPACE", "npwd"),
    #("SURREAL_DATABASE", "npwd"),
    #("SURREAL_USER", "root"),
    #("SURREAL_PASSWORD", "root"),
    #("SECRET_KEY_BASE", "dev-secret"),
    #("PORT", "3000"),
  ]
}

pub fn load_with_all_vars_succeeds_test() {
  let assert Ok(e) = env.load(getter(all()))
  assert e.config.host == "127.0.0.1"
  assert e.config.port == 8000
  assert e.config.namespace == "npwd"
  assert e.config.user == "root"
  assert e.secret_key_base == "dev-secret"
  assert e.port == 3000
}

pub fn missing_var_reports_it_test() {
  let without = list.filter(all(), fn(p) { p.0 != "SECRET_KEY_BASE" })
  assert env.load(getter(without)) == Error("SECRET_KEY_BASE is required")
}

pub fn non_integer_surreal_port_is_error_test() {
  let bad =
    list.map(all(), fn(p) {
      case p.0 {
        "SURREAL_PORT" -> #(p.0, "abc")
        _ -> p
      }
    })
  assert env.load(getter(bad)) == Error("SURREAL_PORT must be an integer")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `gleam test` (from `server/`)
Expected: FAIL to compile — module `server/env` does not exist yet.

- [ ] **Step 3: Create the env loader**

Create `server/src/server/env.gleam`:

```gleam
import gleam/int
import gleam/result
import server/db

pub type Env {
  Env(config: db.Config, secret_key_base: String, port: Int)
}

fn require(
  get: fn(String) -> Result(String, Nil),
  name: String,
) -> Result(String, String) {
  get(name) |> result.replace_error(name <> " is required")
}

fn require_int(
  get: fn(String) -> Result(String, Nil),
  name: String,
) -> Result(Int, String) {
  use raw <- result.try(require(get, name))
  int.parse(raw) |> result.replace_error(name <> " must be an integer")
}

pub fn load(get: fn(String) -> Result(String, Nil)) -> Result(Env, String) {
  use host <- result.try(require(get, "SURREAL_HOST"))
  use db_port <- result.try(require_int(get, "SURREAL_PORT"))
  use namespace <- result.try(require(get, "SURREAL_NAMESPACE"))
  use database <- result.try(require(get, "SURREAL_DATABASE"))
  use user <- result.try(require(get, "SURREAL_USER"))
  use password <- result.try(require(get, "SURREAL_PASSWORD"))
  use secret_key_base <- result.try(require(get, "SECRET_KEY_BASE"))
  use http_port <- result.try(require_int(get, "PORT"))
  Ok(Env(
    config: db.Config(
      host:,
      port: db_port,
      namespace:,
      database:,
      user:,
      password:,
    ),
    secret_key_base:,
    port: http_port,
  ))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `gleam test` (from `server/`)
Expected: the three `env_test` tests PASS.

- [ ] **Step 5: Wire env loading into `main` and remove the hardcoded config**

Replace the whole body of `server/src/server.gleam` with:

```gleam
import envoy
import gleam/erlang/process
import mist
import server/db
import server/env
import server/passwords
import server/router
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()
  let loaded = case env.load(envoy.get) {
    Ok(e) -> e
    Error(message) -> panic as message
  }
  let config = loaded.config
  let _ = db.apply_schema(config)
  seed_admin(config)

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(config, _), loaded.secret_key_base)
    |> mist.new
    |> mist.port(loaded.port)
    |> mist.start

  process.sleep_forever()
}

fn seed_admin(config: db.Config) -> Nil {
  case db.count_users(config), envoy.get("ADMIN_EMAIL"), envoy.get("ADMIN_PASSWORD") {
    Ok(0), Ok(email), Ok(password) -> {
      let _ = db.create_user(config, email, passwords.hash(password), True)
      Nil
    }
    _, _, _ -> Nil
  }
}
```

Then delete `default_config` from `server/src/server/db.gleam` (the function at lines 63–72):

```gleam
pub fn default_config() -> Config {
  Config(
    host: "127.0.0.1",
    port: 8000,
    namespace: "npwd",
    database: "npwd",
    user: "root",
    password: "root",
  )
}
```

- [ ] **Step 6: Verify the build and full suite are green**

Run: `gleam build && gleam test` (from `server/`)
Expected: build succeeds (no remaining reference to `default_config`), all tests PASS. (Tests construct `Config` directly via `helpers.fresh_config`, so they do not depend on env vars.)

- [ ] **Step 7: Add dev env vars to the Nix dev shell**

In `flake.nix`, replace the `devShells.default` block:

```nix
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            gleam
            erlang_27
            rebar3
            nodejs
            bun
            surrealdb
          ];
        };
```

with:

```nix
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            gleam
            erlang_27
            rebar3
            nodejs
            bun
            surrealdb
          ];
          shellHook = ''
            export SURREAL_HOST=127.0.0.1
            export SURREAL_PORT=8000
            export SURREAL_NAMESPACE=npwd
            export SURREAL_DATABASE=npwd
            export SURREAL_USER=root
            export SURREAL_PASSWORD=root
            export PORT=3000
            export SECRET_KEY_BASE=dev-only-secret-key-base-change-in-prod
          '';
        };
```

(This keeps local dev zero-touch after `direnv allow` and makes dev sessions survive restarts. CI runs `gleam test` only, which never calls `main`, so it needs none of these.)

- [ ] **Step 8: Format and commit**

```bash
cd server && gleam format src/server.gleam src/server/db.gleam src/server/env.gleam test/env_test.gleam && cd ..
git add server/src/server.gleam server/src/server/db.gleam server/src/server/env.gleam server/test/env_test.gleam flake.nix
git commit --no-gpg-sign -m "feat(server): fail-fast env-based config for db, secret key, and port

Replace hardcoded db credentials, the per-restart random secret key, and
the hardcoded listen port with required environment variables loaded at
startup. Missing or invalid vars crash with a clear message. Dev vars are
provided by the Nix dev shell.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

---

## Task 3: Edge cross-universe integrity check

**Files:**
- Modify: `server/src/server/db.gleam` (`create_edge`, lines 470–489)
- Test: `server/test/edge_db_test.gleam`

**Interfaces:**
- Consumes: existing `get_node(config, universe, id) -> Result(shared.Node, DbError)`.
- Produces: `create_edge` signature unchanged; it now returns `Error(NotFound)` when either endpoint does not belong to `universe`.

- [ ] **Step 1: Write the failing test**

Add to `server/test/edge_db_test.gleam`:

```gleam
pub fn create_with_foreign_node_is_not_found_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let na = node(config, a, "Frodo")
  let nb = node(config, b, "Sam")
  assert db.create_edge(config, b, "knows", na, nb) == Error(db.NotFound)
  let assert Ok(edges) = db.list_edges(config, b)
  assert edges == []
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `gleam test` (from `server/`)
Expected: FAIL — `create_edge` currently succeeds (returns `Ok`) even though `na` belongs to universe `A`, so the `== Error(db.NotFound)` assertion fails.

- [ ] **Step 3: Add the endpoint guard**

In `server/src/server/db.gleam`, change the start of `create_edge` from:

```gleam
pub fn create_edge(
  config: Config,
  universe: String,
  relationship: String,
  from: String,
  to: String,
) -> Result(shared.Edge, DbError) {
  use <- require_valid([universe, from, to])
  query_first(
```

to:

```gleam
pub fn create_edge(
  config: Config,
  universe: String,
  relationship: String,
  from: String,
  to: String,
) -> Result(shared.Edge, DbError) {
  use <- require_valid([universe, from, to])
  use _ <- result.try(get_node(config, universe, from))
  use _ <- result.try(get_node(config, universe, to))
  query_first(
```

(The `result` import is already present.)

- [ ] **Step 4: Run the full suite to verify green**

Run: `gleam test` (from `server/`)
Expected: the new test PASSES and all existing edge tests still PASS (their endpoints are all in-universe).

- [ ] **Step 5: Format and commit**

```bash
cd server && gleam format src/server/db.gleam test/edge_db_test.gleam && cd ..
git add server/src/server/db.gleam server/test/edge_db_test.gleam
git commit --no-gpg-sign -m "fix(db): reject edges referencing nodes from another universe

create_edge set the edge's universe but never checked that its endpoints
belonged to it. Verify both nodes are in-universe before RELATE.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

---

## Task 4: Map `create_user` errors to the right status

**Files:**
- Modify: `server/src/server/auth.gleam` (`create_user`, lines 109–128)
- Create: `server/test/auth_unit_test.gleam`

**Interfaces:**
- Consumes: `db.DbError` (variants include `QueryError(detail: String)`, `TransportError`, `ResultDecodeError`).
- Produces: `pub fn auth.create_user_status(error: db.DbError) -> Int` — `QueryError(_) -> 409`, everything else `-> 500`.

- [ ] **Step 1: Write the failing tests**

Create `server/test/auth_unit_test.gleam`:

```gleam
import server/auth
import server/db

pub fn query_error_is_conflict_test() {
  assert auth.create_user_status(db.QueryError("duplicate")) == 409
}

pub fn transport_error_is_server_error_test() {
  assert auth.create_user_status(db.TransportError) == 500
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `gleam test` (from `server/`)
Expected: FAIL to compile — `auth.create_user_status` does not exist.

- [ ] **Step 3: Add the mapping and use it**

In `server/src/server/auth.gleam`, add the public function (place it just below the existing `require_admin` function, at the end of the file):

```gleam
pub fn create_user_status(error: db.DbError) -> Int {
  case error {
    db.QueryError(_) -> 409
    _ -> 500
  }
}
```

Then, in `create_user`, change the error branch from:

```gleam
        Ok(user) -> web.json(user, shared.user_to_json, 201)
        Error(_) -> wisp.response(409)
```

to:

```gleam
        Ok(user) -> web.json(user, shared.user_to_json, 201)
        Error(e) -> wisp.response(create_user_status(e))
```

- [ ] **Step 4: Run the full suite to verify green**

Run: `gleam test` (from `server/`)
Expected: the two new unit tests PASS, and the existing `duplicate_email_is_409_test` (in `auth_http_test.gleam`) still PASSES (a duplicate email is a `QueryError`, which maps to 409).

- [ ] **Step 5: Format and commit**

```bash
cd server && gleam format src/server/auth.gleam test/auth_unit_test.gleam && cd ..
git add server/src/server/auth.gleam server/test/auth_unit_test.gleam
git commit --no-gpg-sign -m "fix(auth): only map constraint violations to 409 on user create

A transport or decode failure was reported as 409 'email taken'. Map
QueryError to 409 and infrastructure errors to 500.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

---

## Task 5: Tighten the description position computation

**Files:**
- Modify: `server/src/server/db.gleam` (`create_description`, lines 406–422)
- Test: `server/test/description_db_test.gleam`

**Note on approach (deviation from spec):** The spec proposed wrapping the count+create in `BEGIN/COMMIT TRANSACTION`. During planning we found that adding a trailing `COMMIT` statement breaks `last_result`, which reads the final statement's result (a `COMMIT` carries none), and interacts awkwardly with the Task 1 `LET` prelude. Instead we collapse the two-step `LET $p = count(...); CREATE ...` into a single `CREATE` statement that computes `position` inline. This keeps the single-final-result contract intact and removes the in-request two-step read. **Accepted caveat (unchanged from spec):** this narrows but does not eliminate the race under concurrent requests; a complete fix needs a non-contiguous position scheme, which is out of scope.

**Interfaces:**
- Consumes: nothing new.
- Produces: `create_description` signature and return shape unchanged.

- [ ] **Step 1: Write the regression-lock test**

Add to `server/test/description_db_test.gleam`:

```gleam
pub fn positions_are_sequential_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let n = node(config, u, "Shire")
  let assert Ok(a) = db.create_description(config, u, n, "first")
  let assert Ok(b) = db.create_description(config, u, n, "second")
  let assert Ok(c) = db.create_description(config, u, n, "third")
  assert a.position == 0
  assert b.position == 1
  assert c.position == 2
}
```

- [ ] **Step 2: Run the test (expected to pass already)**

Run: `gleam test` (from `server/`)
Expected: PASS. This test locks the current sequential-position behavior; the change in Step 3 is a structural refactor that must keep it green (there is no red phase for this structural change — this is the accepted caveat documented in the spec).

- [ ] **Step 3: Collapse to a single inline-count CREATE**

In `server/src/server/db.gleam`, change the `query_first` call inside `create_description` from:

```gleam
  query_first(
    config,
    "LET $rec = type::thing($n);
     LET $p = count(SELECT id FROM description WHERE node = $rec);
     CREATE description CONTENT { node: $rec, position: $p, body: $body } RETURN id, node, position, body;",
    [#("n", json.string(node)), #("body", json.string(body))],
    shared.description_decoder(),
  )
```

to:

```gleam
  query_first(
    config,
    "CREATE description CONTENT {
       node: type::thing($n),
       position: count(SELECT id FROM description WHERE node = type::thing($n)),
       body: $body
     } RETURN id, node, position, body;",
    [#("n", json.string(node)), #("body", json.string(body))],
    shared.description_decoder(),
  )
```

- [ ] **Step 4: Run the full suite to verify green**

Run: `gleam test` (from `server/`)
Expected: `positions_are_sequential_test`, the existing `create_appends_and_lists_in_order_test`, and all other description tests PASS.

- [ ] **Step 5: Format and commit**

```bash
cd server && gleam format src/server/db.gleam test/description_db_test.gleam && cd ..
git add server/src/server/db.gleam server/test/description_db_test.gleam
git commit --no-gpg-sign -m "fix(db): compute description position in a single CREATE statement

Collapse the LET count + CREATE two-step into one statement, removing the
in-request read/write window. Full concurrency-safety would need a
non-contiguous position scheme and is out of scope.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

---

## Task 6: Close the sign-in timing side channel

**Files:**
- Modify: `server/src/server/passwords.gleam` (add `dummy_verify`)
- Modify: `server/src/server/auth.gleam` (`signin`, the `find_credentials` error branch)
- Test: `server/test/passwords_test.gleam`

**Interfaces:**
- Consumes: existing private `stretch`, `iterations` in `passwords.gleam`.
- Produces: `pub fn passwords.dummy_verify(password: String) -> Bool` — always returns `False`, but performs one full PBKDF2 stretch so the unknown-email path costs the same as a real verify.

- [ ] **Step 1: Write the failing test**

Add to `server/test/passwords_test.gleam`:

```gleam
pub fn dummy_verify_is_false_test() {
  assert passwords.dummy_verify("anything") == False
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `gleam test` (from `server/`)
Expected: FAIL to compile — `passwords.dummy_verify` does not exist.

- [ ] **Step 3: Add `dummy_verify`**

In `server/src/server/passwords.gleam`, add this function (place it just below `verify`):

```gleam
pub fn dummy_verify(password: String) -> Bool {
  let _ = stretch(password, <<0:size(128)>>, iterations)
  False
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `gleam test` (from `server/`)
Expected: `dummy_verify_is_false_test` PASSES.

- [ ] **Step 5: Equalize timing in `signin`**

In `server/src/server/auth.gleam`, change the `find_credentials` error branch inside `signin` from:

```gleam
        Error(_) -> wisp.response(401)
```

to:

```gleam
        Error(_) -> {
          let _ = passwords.dummy_verify(input.password)
          wisp.response(401)
        }
```

- [ ] **Step 6: Run the full suite to verify green**

Run: `gleam test` (from `server/`)
Expected: all tests PASS, including the existing `signin_unknown_email_is_401_test` and `signin_wrong_password_is_401_test` (behavior is unchanged; only timing of the unknown-email path changes, which is not asserted).

- [ ] **Step 7: Format and commit**

```bash
cd server && gleam format src/server/passwords.gleam src/server/auth.gleam test/passwords_test.gleam && cd ..
git add server/src/server/passwords.gleam server/src/server/auth.gleam server/test/passwords_test.gleam
git commit --no-gpg-sign -m "fix(auth): equalize sign-in timing for unknown emails

An unknown email returned 401 instantly while a known one paid the full
PBKDF2 cost, a user-enumeration oracle. Run a dummy stretch on the
unknown-email path so both cost the same.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014eRtR4hn8wjX2yR1uBiS3r"
```

---

## Final verification

After all six tasks:

- [ ] Run the full server suite once more from `server/`: `gleam format --check src test && gleam test` — expect clean format and all tests passing.
- [ ] Confirm `git log --oneline` shows the six fix commits on `main`.
```
