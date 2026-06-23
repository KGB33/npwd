# NPWD

A Who's-Who of characters.

Users can:
  - [x] Enter characters including their name and a description
  - [x] Enter relationships between characters
  - [x] View these character-character relationships on a filterable graph
  - [x] Have multiple "universes" for different book series
  - [x] Plot events on a timeline and link them to people
  - [x] Sign in; universes are shareable by link but only their owner can edit them

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

Everything below assumes the Nix dev shell, which provides `gleam`, `erlang`, `bun`,
and `surrealdb`. Enter it with:

```sh
nix develop
```

(or `direnv allow` once, then it loads automatically on `cd`).

Configuration is read from the environment. Copy `.env.example` to `.env` and adjust as
needed — `direnv` loads `.env` automatically (the defaults there point at the local
SurrealDB started in step 2). Without `direnv`, source it yourself before running the
server: `set -a; . .env; set +a`.

### 1. Build the client bundle

The client compiles to JavaScript. `lustre/dev build` also emits its own `index.html`, but
we serve a hand-owned one (`server/priv/static/index.html`, which links `styles.css`), so
build into a scratch dir and copy only the JS bundle across:

```sh
cd client
gleam run -m lustre/dev build --outdir=build/static
cp build/static/client.js ../server/priv/static/client.js
```

Re-run this whenever you change client code. (`client.js` is a generated artifact and is
git-ignored; `index.html`, `styles.css`, and `fonts/` are hand-owned and committed.)

> The bundler uses Bun. `client/gleam.toml` sets `[tools.lustre.bin] bun = "system"` so it
> uses the Bun from the Nix dev shell rather than downloading a prebuilt binary (the
> downloaded one won't run on NixOS). The first build also compiles the dev tools, so it
> takes a little longer than later ones.

> For a deployable build you do not run this by hand: `nix build` (see
> **Deployment** below) builds the client bundle and bakes it into the
> server artifact automatically.

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
# Config is read from the environment, loaded from `.env` (see the intro above
# and `.env.example` for the full contract). To seed the first admin, set
# ADMIN_EMAIL and ADMIN_PASSWORD on the first run — uncomment them in `.env`,
# or pass them inline as below:
ADMIN_EMAIL=you@example.com ADMIN_PASSWORD=changeme gleam run
```

It listens on **http://localhost:3000** and applies the schema on startup.
Registration is invite-only: when the `user` table is empty the server seeds
one admin from `ADMIN_EMAIL`/`ADMIN_PASSWORD` (omit them after the first run).
Passwords are hashed with PBKDF2-HMAC-SHA512; the session is a signed,
HttpOnly cookie. Admins invite more users via `POST /auth/users`.

### 4. Open the app

Visit <http://localhost:3000> and sign in. Universes you create are yours to
edit; anyone with the `/u/<id>` link can view (but not change) them.

## Deployment

Build the self-contained artifact (server + client bundle) with Nix:

```sh
nix build .#npwd
```

`result/bin/server` is a launcher for the Erlang shipment under `result/lib`.
It reads all configuration from the environment — see `.env.example` for the
full contract. Run it under your process manager (e.g. a systemd unit) with
the env populated from your secrets store:

```sh
set -a; . /run/secrets/npwd.env; set +a
result/bin/server
```

The server serves **plain HTTP on `$PORT`** and expects a TLS-terminating
reverse proxy in front of it. For the session cookie to carry the `Secure`
attribute, the proxy must pass `X-Forwarded-Proto: https`. SurrealDB, TLS,
secrets, and the systemd unit are provisioned in your host configuration,
not in this repo.

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
