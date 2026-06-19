# NPWD

A Who's-Who of characters.

Users can:
  - [x] Enter characters including their name and a description
  - [x] Enter relationships between characters
  - [x] View these character-character relationships on a filterable graph
  - [x] Have multiple "universes" for different book series
  - [x] Plot events on a timeline and link them to people

---

Character-relationship graph nodes are generic nouns/nodes — we can place more than just
people on the graph.

## Project layout

A Gleam monorepo of three packages:

- `shared/` — domain types + JSON codecs, compiled for both targets.
- `server/` — `wisp`-on-`mist` HTTP API; talks to SurrealDB over HTTP. Also serves the
  built client. Business logic (filtering, traversal, ordering) lives here.
- `client/` — a Lustre single-page app (compiles to JavaScript). Display only — it renders
  what the server returns.

State lives in SurrealDB: every entity is a `node` (Person / Place / Event / Generic kinds),
every connection is a `relationship` edge.

## Running locally

Everything below assumes the Nix dev shell, which provides `gleam`, `erlang_27`, `nodejs`,
and `surrealdb`. Enter it with:

```sh
nix develop
```

(or `direnv allow` once, then it loads automatically on `cd`).

### 1. Build the client bundle

The client compiles to JavaScript. `lustre/dev build` bundles it into
`server/priv/static/` (producing `client.js` and an `index.html`), which the server serves:

```sh
cd client
gleam run -m lustre/dev build --outdir=../server/priv/static
```

Re-run this whenever you change client code. (`client.js` and `index.html` are generated
artifacts and are git-ignored.)

> The bundler uses Bun. `client/gleam.toml` sets `[tools.lustre.bin] bun = "system"` so it
> uses the Bun from the Nix dev shell rather than downloading a prebuilt binary (the
> downloaded one won't run on NixOS). The first build also compiles the dev tools, so it
> takes a little longer than later ones.

### 2. Start SurrealDB

The server expects SurrealDB at `127.0.0.1:8000` with user/pass `root`/`root` (see
`db.default_config` in `server/src/server/db.gleam`). In its own terminal:

```sh
surreal start --user root --pass root --bind 127.0.0.1:8000 memory
```

`memory` keeps everything in RAM (wiped on exit). For persistence, swap it for a storage
path, e.g. `rocksdb:npwd.db`.

### 3. Start the server

In another terminal (inside the dev shell):

```sh
cd server
gleam run
```

It listens on **http://localhost:3000** and applies the schema on startup.

### 4. Open the app

Visit <http://localhost:3000>.

## Tests

The server tests run against a real SurrealDB on port **8001** (separate from the dev DB on
8000), so start one first:

```sh
surreal start --user root --pass root --bind 127.0.0.1:8001 memory
```

Then run the suite for each package:

```sh
cd shared && gleam test
cd ../server && gleam test
cd ../client && gleam test
```

`shared` and `client` tests need no database.
