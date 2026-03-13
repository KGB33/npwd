---
name: create-db-module
description: Create db modules that wrap squirrel-generated SQL calls (from server/src/sql.gleam) and return shared domain types, acting as a full data-access layer.
disable-model-invocation: true
argument-hint: [shared-type-module]
---

# Create Squirrel SQL DB Module

Create a db module that wraps squirrel-generated SQL calls in `server/src/sql.gleam` and returns clean domain types from `$ARGUMENTS`. Handlers should never import `sql` or `pog` directly — the db module is the full data-access layer.

The shared `DbError` type lives in `server/src/db.gleam`. All db modules should import it from there rather than defining their own.

## Steps

1. **Read the shared type module** at `shared/src/shared/$ARGUMENTS.gleam` to identify the target type and its fields.

2. **Read `server/src/sql.gleam`** and find all squirrel-generated functions related to the domain type (e.g., for `character` find `insert_character`, `list_characters`, `get_characters_by_id`, etc.).

3. **Read `server/src/db/character.gleam`** as a reference implementation for the db module pattern.

4. **Create `server/src/db/$ARGUMENTS.gleam`** with:

   Import the shared `DbError` from the parent module:
   ```gleam
   import db.{NotFound, QueryError}
   ```

   One wrapper function per SQL operation. Each function:
   - Calls the `sql.*` function
   - Pattern-matches on `pog.Returned(count, rows)`
   - Converts rows to the shared domain type
   - Returns `Result(DomainType, db.DbError)` (or `Result(List(DomainType), db.DbError)` / `Result(Nil, db.DbError)` as appropriate)

   Follow these conventions:
   - **Single-row returns** (insert, get_by_id, update): Match `Ok(pog.Returned(_, [row]))` → `Ok(Type(...))`. For get/update, `0` rows → `Error(NotFound)`.
   - **List returns** (list, get_by_name): Match `Ok(pog.Returned(_, rows))` → `Ok(list.map(...))`. Empty list is valid, not `NotFound`.
   - **Delete**: Match `Ok(pog.Returned(1, _))` → `Ok(Nil)`, `Ok(pog.Returned(0, _))` → `Error(NotFound)`.
   - **Impossible states**: Use `Error(QueryError(pog.UnexpectedResultType([])))`.
   - **SQL errors**: `Error(e)` → `Error(QueryError(e))`.

5. **Update handler files** (`server/src/handlers/$ARGUMENTS.gleam` or `${ARGUMENTS}s.gleam`):
   - Remove `pog`, `sql`, and `gleam/list` imports (unless `list` is used elsewhere).
   - Import `db/$ARGUMENTS as ${ARGUMENTS}_db`.
   - Call db functions directly and match on `Ok(value)` / `Error(db.NotFound)` / `Error(_)`.

6. **Update any other files** that call `sql` functions for this domain type (e.g., `server/src/handlers/index.gleam`) to use the db module instead.

7. **Verify** by running `cd server && gleam build` to confirm compilation succeeds, then `cd server && gleam test` to confirm tests pass.
