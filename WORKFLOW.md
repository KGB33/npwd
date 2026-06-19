# NPWD — Implementation Workflow

Resumable plan of record. If context is lost, read this top-to-bottom: it holds every
decision, fact, and the current progress so work can restart cold.

## Vision (from README)

A "Who's-Who" worldbuilding tool. Users can:
- Enter characters (name + description)
- Enter relationships between characters
- View character-character relationships on a **filterable graph**
- Keep multiple **"universes"** for different book series
- Plot **events on a timeline** and link them to people

Graph nodes are **generic nouns** — not just people. Model everything as a node.

## Author preferences (treat as hard constraints)

- Terse, simple code over complex branching.
- Comments are usually a code smell — omit them; let names carry meaning.
- **Testing is the highest priority.** Every milestone is test-first.
- Functional Gleam throughout (frontend and backend).

## Locked decisions

- **Language/structure:** Gleam monorepo, three packages already scaffolded:
  - `client/` — Lustre frontend, **JavaScript target**.
  - `server/` — backend, **Erlang target**. wisp.
  - `shared/` — path dependency used by both; **must compile to both targets**
    (keep codecs target-agnostic, no FFI).
- **Database: SurrealDB.** Chosen over Postgres because **custom/unstructured node kinds
  are a central filter target** — schema-on-read is the main event, so native
  arbitrary-field querying + first-class graph edges outweigh squirrel's compile-time
  checking. Access via:
  - A community Gleam driver (`surreal_gleam` / `meppu/surreal`) — server-only (Erlang
    target), fine since DB access is backend-only. **Pin the maintained one in M0.**
  - **Fallback if no driver is adequate:** hit SurrealDB's HTTP `/sql` endpoint with
    `gleam_httpc` + `gleam_json`. Robust and simple for this scale.
  - Schema via SurrealQL `DEFINE TABLE/FIELD/INDEX` applied at startup (no cigogne/squirrel).
  - **Cost accepted:** no compile-time query checking — compensated by the testing
    strategy below (one centralized query wrapper + in-memory integration tests).

## Architecture principles

- **The UI is a display layer only — no business logic.** All domain rules (filtering,
  validation, traversal, any derived result) live on the server.
- The client may hold **UI state** (selected filter, form contents, loading, open modal)
  and renders server-provided domain data; it never *computes* a domain result.
- Filtering is **server-side**: the client sends the selected filter as query params
  (e.g. `GET /universes/:id/graph?kind=Person&relationship=was_at`); the server returns
  exactly the subgraph to draw. Drawing/layout in the browser is display, not logic.
- Filtering is server-side SurrealQL with **bound parameters** (`WHERE kind = $kind`,
  native nested access `WHERE faction = $faction`); never interpolate user input into
  query strings.

## Data model

Everything is a **node** (a record); every connection is an **edge** created with
SurrealQL `RELATE` (edges are first-class records that can carry their own fields).
No event/place tables — those are node *kinds*. Schema is mostly schemaless, so custom
kinds carry arbitrary top-level fields natively (the reason we chose SurrealDB).
All records scoped by a `universe` link.

- `universe` — `{ name, description }`
- `node` — `{ universe, kind, name, description, ...kind-specific fields }`
- edges — `RELATE node->relationship->node` (e.g. `character->was_at->event`,
  `event->took_place_at->place`); the relationship record may carry fields.

`kind` discriminates the record; per-kind fields are top-level (not buried in a blob),
decoded into a Gleam sum type (`type` is reserved, so the field is `kind`):

```gleam
pub type NodeKind {
  Person(dob: Date, gender: String)
  Place
  Event(when: Date)
  Generic(fields: Dict(String, Json))
}
```

## Dependencies to add (M0)

- `client`: `lustre`, `lustre_http`, `gleam_json`
- `server`: `wisp`, `mist`, `gleam_json`, `gleam_otp`, + a SurrealDB driver
  (`surreal_gleam` / `meppu/surreal`, or `gleam_httpc` for the HTTP fallback)
- `shared`: `gleam_json`
- Each package keeps `gleeunit` as a dev dependency (already present).

## Layout conventions

- `server/schema.surql` — SurrealQL `DEFINE` statements, applied at startup.
- `server/src/server/db.gleam` — the **single** module wrapping all SurrealQL queries
  (centralized so query strings live in one tested place). No queries scattered elsewhere.
- `shared/src/shared/*.gleam` — domain types + JSON codecs.
- `client/src/client/*.gleam` — Lustre MVU (model/msg/update/view).

## Testing strategy (per package)

- `shared`: encode→decode **round-trip** tests on every codec.
- `server`: handler tests via `wisp/testing` (no socket) + DB **integration tests**
  against an **in-memory SurrealDB** (`surreal start memory`), each test on a fresh
  namespace/database for isolation. Queries aren't compile-time checked, so the
  `db.gleam` wrapper carries thorough query tests — this is the main safety net.
- `client`: `update` is pure — unit-test message→state transitions; assert views via
  element-to-string. Use Lustre's `dev/simulate` to drive the app through messages and
  `dev/query` to assert on the rendered element tree. Keep logic out of any FFI so it
  stays testable.

## CI (needs fixing in M0)

Current `.github/workflows/test.yml` runs `gleam test` / `gleam format --check` at the
repo root, but this is a **three-package monorepo**. Fix:
- Run `gleam test` and `gleam format --check src test` **per package**.
- Run an **in-memory SurrealDB** (`surreal start --memory`) in CI for the server's
  integration tests.

## Git workflow

- Currently on `main`. Do work on a **feature branch per milestone**; commit when the
  user asks. Co-author trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Never GPG-sign commits** — always commit with signing off (`--no-gpg-sign`).

---

## Milestones (each independently shippable, test-first)

### M0 — Foundation & wiring ✅
- [x] Add dependencies to all three packages (above).
- [x] `shared`: domain types (`Universe`, `Node`, `NodeKind`, `Edge`, `Date`,
      `FieldValue`) + JSON codecs, with round-trip tests.
- [x] `server`: wisp router on mist, health endpoint, static-file serving for client
      bundle.
- [x] `server`: SurrealDB connection (HTTP `/sql` fallback), `schema.surql`
      `DEFINE`s applied at startup, `db.gleam` query wrapper + in-memory test harness.
- [x] `client`: Lustre MVU skeleton talking to server via `rsvp` (replaces the
      now-superseded `lustre_http`).
- [x] Fix CI to run per-package + add in-memory SurrealDB container.

### M1 — Universes ✅
(Everything is scoped to a universe, so this is first.)
- [x] Server: CRUD endpoints (`GET/POST /universes`, `GET/PUT/DELETE /universes/:id`)
      + `db.gleam` queries + handler/integration tests.
- [x] Client: universe list + create/edit/delete views.

### M2 — Nodes (generic nouns, all kinds incl. Event/Place) ✅
- [x] Server: CRUD scoped to universe, `kind` + per-kind fields; tests.
- [x] Client: node list + create/edit views per kind.

### M3 — Edges / relationships
- [ ] Server: directed edges via `RELATE node->relationship->node` between any two nodes;
      CRUD + tests.
- [ ] Client: relationship create/edit between nodes.

### M4 — Filterable relationship graph (main piece)
- [ ] Server: graph endpoint returning the filtered subgraph (nodes + edges) for a
      universe; filters by `kind` / `relationship` / arbitrary node fields via bound
      SurrealQL params; tests.
- [ ] Client: filter controls hold the selected filter as UI state, request the subgraph,
      and render it via FFI to a JS graph lib (cytoscape.js / force-directed) behind a thin
      wrapper. No filtering logic in the client — it only draws what the server returns.

### M5 — Timeline
- [ ] Server: query returning `Event`-kind nodes (ordered by `when`) with their edges,
      filterable by universe; tests.
- [ ] Client: horizontal timeline rendering the server's result; events link to nodes.

---

## Progress log

Append a dated line as milestones complete; update the checkboxes above.

- 2026-06-19 — Workflow written. Stack + DB decided. Nothing implemented yet (packages
  are hello-world stubs). Next: M0.
- 2026-06-19 — Model collapsed to nodes+edges (events/places are node kinds; no
  event_nodes table). Locked "UI is display-only / business logic + filtering server-side"
  principle; revised M2–M5 accordingly.
- 2026-06-19 — Switched DB Postgres→SurrealDB: custom/unstructured node kinds are a
  central filter target, so schema-on-read + native arbitrary-field queries + first-class
  `RELATE` edges outweigh squirrel's compile-time checking. Dropped pog/squirrel/cigogne;
  added a community SurrealDB driver (HTTP `/sql` fallback) and an in-memory test harness.
  Testing now leans on a centralized `db.gleam` query wrapper since queries aren't
  compiler-checked. Driver-vs-HTTP pinned in M0.
- 2026-06-19 — **M0 complete** (branch `m0-foundation`, 20 tests passing).
  Decisions made while implementing:
  - **DB access = HTTP `/sql`**, not a community driver. The wrapper posts SurrealQL to
    `/sql` with root basic-auth and `surreal-ns`/`surreal-db` headers; fresh ns/db
    auto-create under root, which is what makes per-test isolation cheap.
  - **gleam_json 3.x / gleam_stdlib 1.x** — the new `gleam/dynamic/decode` API. (json 2.x
    uses the old `dynamic.Decoder` API and will not compile against stdlib 1.x.)
  - **`FieldValue`** scalar (`String|Int|Float|Bool`) backs `Generic` node fields instead
    of raw `Json`, because `Json` is encode-only and can't round-trip through a decoder.
  - **`rsvp`** is the client HTTP lib (maintained for Lustre 5); `lustre_http` is superseded.
  - **Client tests** use `lustre/dev/simulate` + `lustre/dev/query`; note `query.test_id`
    matches the `data-test-id` attribute (hyphenated).
  - **schema.surql lives in `server/priv/`** (not `server/`) so `priv_directory` finds it
    at runtime and in tests.
  - **Dev env:** `flake.nix` now ships erlang_27, rebar3, nodejs, surrealdb (surrealdb is
    BSL-licensed → allowed via a narrow `allowUnfreePredicate`). Local tests need a
    SurrealDB on `127.0.0.1:8001`: `surreal start --user root --pass root --bind
    127.0.0.1:8001 memory`.
- 2026-06-19 — **M1 complete** (branch `m1-universes`, 41 tests passing: shared 7,
  server 24, client 10). Decisions:
  - **Bound params over HTTP `/sql`:** variables are passed as query-string params and
    each value is **JSON-encoded** (`?name="Dune"`). Verified this is injection-safe (an
    injection payload is treated as a data value) **and** correctly typed (a JSON `5` is a
    number; quoting forces strings, so a name like `1984` stays a string). `db.gleam`'s
    `run` now takes `vars: List(#(String, Json))`; `query`/`execute` pass `[]`.
  - **Record ids** are the full SurrealDB thing string (`universe:xxxx`) end to end;
    select/update/delete by id use `type::thing($id)`. The id sits in the URL path
    (`/universes/universe:xxxx`) and `wisp.path_segments` keeps the colon.
  - **HTTP handlers** live in `server/src/server/universes.gleam`; `db.gleam` stays the
    only place SurrealQL is written. `NotFound`→404, bad JSON→400, bad verb→405, delete→204.
  - **Router** now takes the `db.Config` (`router.handle_request(config, req)`); `main`
    partially applies it into the wisp_mist handler.
  - **Client = display layer:** every mutation (create/update/delete) re-fetches
    `/universes` instead of editing client state, keeping the server authoritative.
  - **Test helper** `server/test/helpers.gleam` (`fresh_config`/`fresh_db`) gives each
    integration test an isolated database.
- 2026-06-19 — **M2 complete** (branch `m2-nodes`, 70 tests passing: shared 8,
  server 41, client 21). Decisions:
  - **Whole-node create/update via `CREATE/UPDATE … CONTENT $data`** with one bound
    `$data` JSON object (`shared.node_content_to_json`). Verified empirically that
    SurrealDB **coerces a plain string `"universe:xxx"` into the `record<universe>`
    link**, so the content object carries `universe` as a string — no `type::thing`
    juggling for the link itself. Nested `dob`/`when` Date objects and Generic `fields`
    store/return as-is in the SCHEMALESS table. CONTENT replaces the whole record, so
    changing a node's kind cleanly drops the old kind's fields.
  - **Nodes are universe-scoped end to end:** routes nest under
    `/universes/:uid/nodes[/:nid]` (router matches the nested pattern *before*
    `["universes", ..rest]`). get/update/delete add `WHERE universe = type::thing($u)`,
    so reaching a node via the wrong universe path → empty → 404 (tested).
  - **Shared codec reuse:** extracted `shared.node_kind_decoder()` (used by
    `node_decoder` via `decode.then`) and the server's node `input_decoder`; added
    `shared.node_content_to_json` for the create/update payload.
  - **Client:** selecting a universe opens its node manager (`selected`/`nodes` in the
    model); a kind `<select>` (`event.on_change`) swaps the per-kind sub-form
    (`KindForm`: Person/Place/Event/Generic). Generic fields are dynamic key/value
    string rows (add/remove); empty keys are dropped when building the body.
    `node_body` is public so the body-building is unit-tested directly. Same
    display-only discipline: every node mutation re-fetches the universe's nodes.
