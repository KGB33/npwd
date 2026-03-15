import gleam/dynamic/decode
import gleam/json
import shared/character.{uuid_string_decoder}
import youid/uuid.{type Uuid}

pub type Entry {
  Entry(id: Uuid, character_id: Uuid, text: String)
}

pub fn entry_to_json(entry: Entry) -> json.Json {
  let Entry(id:, character_id:, text:) = entry
  json.object([
    #("id", json.string(uuid.to_string(id))),
    #("character_id", json.string(uuid.to_string(character_id))),
    #("text", json.string(text)),
  ])
}

pub fn entry_list_to_json(entries: List(Entry)) -> json.Json {
  json.array(entries, of: entry_to_json)
}

pub fn entry_decoder() -> decode.Decoder(Entry) {
  use id <- decode.field("id", uuid_string_decoder())
  use character_id <- decode.field("character_id", uuid_string_decoder())
  use text <- decode.field("text", decode.string)
  decode.success(Entry(id:, character_id:, text:))
}

pub type NewEntry {
  NewEntry(character_id: Uuid, text: String)
}

pub fn new_entry_decoder() -> decode.Decoder(NewEntry) {
  use character_id <- decode.field("character_id", uuid_string_decoder())
  use text <- decode.field("text", decode.string)
  decode.success(NewEntry(character_id:, text:))
}
