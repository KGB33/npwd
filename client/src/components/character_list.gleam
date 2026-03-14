import gleam/dynamic/decode
import gleam/json
import gleam/list
import lustre
import lustre/attribute
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import shared/character.{type Character}

pub type Model {
  Model(characters: List(Character))
}

pub type Msg {
  SetCharacters(List(Character))
}

fn init(_) -> #(Model, Effect(Msg)) {
  #(Model(characters: []), effect.none())
}

fn update(_model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SetCharacters(chars) -> #(Model(characters: chars), effect.none())
  }
}

fn view(model: Model) -> Element(Msg) {
  case model.characters {
    [] -> html.p([], [html.text("No characters yet.")])
    chars ->
      html.ul(
        [],
        list.map(chars, fn(c) {
          html.li([], [
            element.element(
              "character-entry",
              [
                attribute.attribute(
                  "character",
                  json.to_string(character.character_to_json(c)),
                ),
              ],
              [],
            ),
          ])
        }),
      )
  }
}

pub fn register() -> Result(Nil, lustre.Error) {
  let app =
    lustre.component(init, update, view, [
      component.on_attribute_change("characters", fn(str) {
        case json.parse(str, decode.list(character.character_decoder())) {
          Ok(chars) -> Ok(SetCharacters(chars))
          Error(_) -> Error(Nil)
        }
      }),
    ])
  lustre.register(app, "character-list")
}
