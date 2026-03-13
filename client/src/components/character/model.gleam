import shared/character.{type Character}
import youid/uuid

pub type Model {
  Model(c: Character, io_wait: Bool)
}

pub fn init(_) -> Model {
  Model(c: character.Character(id: uuid.nil, name: ""), io_wait: False)
}
