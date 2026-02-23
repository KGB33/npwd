import gleam/dynamic/decode
import gleam/json
import gleam/list
import youid/uuid.{type Uuid}

pub type Character {
  Character(id: Uuid, name: String)
}

pub fn character_to_json(character: Character) -> json.Json {
  let Character(id:, name:) = character
  json.object([
    #("id", json.string(uuid.to_string(id))),
    #("name", json.string(name)),
  ])
}

pub fn character_list_to_json(characters: List(Character)) {
  json.array(characters, of: character_to_json)
}

pub fn character_decoder() -> decode.Decoder(Character) {
  use id <- decode.field("id", uuid_string_decoder())
  use name <- decode.field("name", decode.string)
  decode.success(Character(id:, name:))
}

// TODO: Move this to a more reuseable location
pub fn uuid_string_decoder() {
  use str <- decode.then(decode.string)
  case uuid.from_string(str) {
    Ok(uuid) -> decode.success(uuid)
    Error(_) -> decode.failure(uuid.v7(), "Uuid")
  }
}
