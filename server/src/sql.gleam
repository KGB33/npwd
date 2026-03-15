//// This module contains the code to run the sql queries defined in
//// `./src/sql`.
//// > 🐿️ This module was generated automatically using v4.6.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog
import youid/uuid.{type Uuid}

/// A row you get from running the `delete_character` query
/// defined in `./src/sql/delete_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type DeleteCharacterRow {
  DeleteCharacterRow(id: Uuid, name: String)
}

/// Runs the `delete_character` query
/// defined in `./src/sql/delete_character.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_character(
  db: pog.Connection,
  arg_1: Uuid,
) -> Result(pog.Returned(DeleteCharacterRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use name <- decode.field(1, decode.string)
    decode.success(DeleteCharacterRow(id:, name:))
  }

  "DELETE FROM characters
WHERE id = $1
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `delete_entry` query
/// defined in `./src/sql/delete_entry.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type DeleteEntryRow {
  DeleteEntryRow(id: Uuid, character_id: Uuid, text: String)
}

/// Runs the `delete_entry` query
/// defined in `./src/sql/delete_entry.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_entry(
  db: pog.Connection,
  arg_1: Uuid,
) -> Result(pog.Returned(DeleteEntryRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use character_id <- decode.field(1, uuid_decoder())
    use text <- decode.field(2, decode.string)
    decode.success(DeleteEntryRow(id:, character_id:, text:))
  }

  "DELETE FROM entries WHERE id = $1 RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_characters_by_id` query
/// defined in `./src/sql/get_characters_by_id.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetCharactersByIdRow {
  GetCharactersByIdRow(id: Uuid, name: String)
}

/// Get A character by id
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_characters_by_id(
  db: pog.Connection,
  arg_1: Uuid,
) -> Result(pog.Returned(GetCharactersByIdRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use name <- decode.field(1, decode.string)
    decode.success(GetCharactersByIdRow(id:, name:))
  }

  "-- Get A character by id

select
    *
from
    characters
where
    id = $1
;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_characters_by_name` query
/// defined in `./src/sql/get_characters_by_name.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetCharactersByNameRow {
  GetCharactersByNameRow(id: Uuid, name: String)
}

/// Get A list of characters by name
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_characters_by_name(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(GetCharactersByNameRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use name <- decode.field(1, decode.string)
    decode.success(GetCharactersByNameRow(id:, name:))
  }

  "-- Get A list of characters by name

select
    *
from
    characters
where
    name ilike $1
;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `insert_character` query
/// defined in `./src/sql/insert_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type InsertCharacterRow {
  InsertCharacterRow(id: Uuid, name: String)
}

/// Create a new Character
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_character(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(InsertCharacterRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use name <- decode.field(1, decode.string)
    decode.success(InsertCharacterRow(id:, name:))
  }

  "-- Create a new Character
insert into characters
    (name)
VALUES
    ($1)
returning *
;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `insert_entry` query
/// defined in `./src/sql/insert_entry.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type InsertEntryRow {
  InsertEntryRow(id: Uuid, character_id: Uuid, text: String)
}

/// Runs the `insert_entry` query
/// defined in `./src/sql/insert_entry.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_entry(
  db: pog.Connection,
  arg_1: Uuid,
  arg_2: String,
) -> Result(pog.Returned(InsertEntryRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use character_id <- decode.field(1, uuid_decoder())
    use text <- decode.field(2, decode.string)
    decode.success(InsertEntryRow(id:, character_id:, text:))
  }

  "INSERT INTO entries (character_id, text) VALUES ($1, $2) RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.parameter(pog.text(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `list_characters` query
/// defined in `./src/sql/list_characters.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ListCharactersRow {
  ListCharactersRow(id: Uuid, name: String)
}

/// Runs the `list_characters` query
/// defined in `./src/sql/list_characters.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn list_characters(
  db: pog.Connection,
) -> Result(pog.Returned(ListCharactersRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use name <- decode.field(1, decode.string)
    decode.success(ListCharactersRow(id:, name:))
  }

  "select * from characters;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `list_entries_by_character` query
/// defined in `./src/sql/list_entries_by_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ListEntriesByCharacterRow {
  ListEntriesByCharacterRow(id: Uuid, character_id: Uuid, text: String)
}

/// Runs the `list_entries_by_character` query
/// defined in `./src/sql/list_entries_by_character.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn list_entries_by_character(
  db: pog.Connection,
  arg_1: Uuid,
) -> Result(pog.Returned(ListEntriesByCharacterRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use character_id <- decode.field(1, uuid_decoder())
    use text <- decode.field(2, decode.string)
    decode.success(ListEntriesByCharacterRow(id:, character_id:, text:))
  }

  "SELECT * FROM entries WHERE character_id = $1 ORDER BY id;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `update_character` query
/// defined in `./src/sql/update_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UpdateCharacterRow {
  UpdateCharacterRow(id: Uuid, name: String)
}

/// Runs the `update_character` query
/// defined in `./src/sql/update_character.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn update_character(
  db: pog.Connection,
  arg_1: Uuid,
  arg_2: String,
) -> Result(pog.Returned(UpdateCharacterRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use name <- decode.field(1, decode.string)
    decode.success(UpdateCharacterRow(id:, name:))
  }

  "UPDATE characters
SET
  name = $2
WHERE id = $1
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.parameter(pog.text(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

// --- Encoding/decoding utils -------------------------------------------------

/// A decoder to decode `Uuid`s coming from a Postgres query.
///
fn uuid_decoder() {
  use bit_array <- decode.then(decode.bit_array)
  case uuid.from_bit_array(bit_array) {
    Ok(uuid) -> decode.success(uuid)
    Error(_) -> decode.failure(uuid.v7(), "Uuid")
  }
}
