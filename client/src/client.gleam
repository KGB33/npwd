import components/character_entry
import components/character_form
import components/character_list
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import plinth/browser/document
import plinth/browser/element as plinth_element
import shared/character
import youid/uuid

pub fn main() -> Nil {
  let initial_items =
    document.query_selector("#model")
    |> result.map(plinth_element.inner_text)
    |> result.try(fn(j) {
      json.parse(j, decode.list(character.character_decoder()))
      |> result.replace_error(Nil)
    })
    |> result.unwrap([])

  let assert Ok(_) = character_form.register()
  let assert Ok(_) = character_list.register()
  let assert Ok(_) = character_entry.register()

  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", initial_items)

  Nil
}

// Model -----------------------------------------------------------------------

type Model {
  Model(characters: List(character.Character))
}

fn init(characters: List(character.Character)) -> #(Model, Effect(Msg)) {
  #(Model(characters:), effect.none())
}

// Update ----------------------------------------------------------------------

type Msg {
  CharacterCreated(character.Character)
  CharacterDeleted(uuid.Uuid)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    CharacterCreated(c) -> #(
      Model(characters: list.append(model.characters, [c])),
      effect.none(),
    )
    CharacterDeleted(id) -> #(
      Model(characters: list.filter(model.characters, fn(c) { c.id != id })),
      effect.none(),
    )
  }
}

// View ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  let container_styles = [
    #("display", "flex"),
    #("flex-direction", "row"),
    #("height", "100vh"),
    #("width", "100%"),
  ]

  let left_panel_styles = [
    #("width", "25%"),
    #("display", "flex"),
    #("flex-direction", "column"),
    #("gap", "0.5em"),
    #("padding", "1em"),
  ]

  let right_panel_styles = [
    #("flex", "1"),
    #("border-left", "1px solid #ccc"),
  ]

  html.div([attribute.styles(container_styles)], [
    html.div([attribute.styles(left_panel_styles)], [
      element.element(
        "character-form",
        [
          event.on("character-created", {
            use c <- decode.field("detail", character.character_decoder())
            decode.success(CharacterCreated(c))
          }),
        ],
        [],
      ),
      element.element(
        "character-list",
        [
          attribute.attribute(
            "characters",
            json.to_string(json.array(
              model.characters,
              character.character_to_json,
            )),
          ),
          event.on(
            "character-deleted",
            decode.at(["detail", "id"], character.uuid_string_decoder())
              |> decode.map(CharacterDeleted),
          ),
        ],
        [],
      ),
    ]),
    html.div([attribute.styles(right_panel_styles)], []),
  ])
}
