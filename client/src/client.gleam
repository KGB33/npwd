import gleam/dynamic/decode
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import plinth/browser/document
import plinth/browser/element as plinth_element
import rsvp
import shared/character.{type Character}
import youid/uuid

pub fn main() -> Nil {
  let initial_items =
    document.query_selector("#model")
    |> result.map(plinth_element.inner_text)
    |> result.try(fn(j) {
      json.parse(j, decode.list(character.character_decoder()))
      |> result.replace_error(Nil)
    }) |> result.unwrap([])

  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", initial_items)

  Nil
}

// Model -------------------------------------------------------------------------------- 

type Model {
  Model(
    characters: List(Character),
    new_character: String,
    saving: Bool,
    error: Option(String),
  )
}

fn init(characters: List(Character)) -> #(Model, Effect(Msg)) {
  let model =
    Model(characters:, new_character: "", saving: False, error: option.None)

  #(model, effect.none())
}

// Update -------------------------------------------------------------------------------- 

type Msg {
  ServerSavedCharacters(Result(Response(String), rsvp.Error))
  UserAddedCharacter
  UserTypedNewCharacter(String)
  UserSaved
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ServerSavedCharacters(Ok(_)) -> #(
      Model(..model, saving: False, error: option.None),
      effect.none(),
    )
    ServerSavedCharacters(Error(_)) -> #(
      Model(..model, saving: False, error: option.Some("Failed to save")),
      effect.none(),
    )
    UserAddedCharacter -> {
      case model.new_character {
        "" -> #(model, effect.none())
        name -> {
          let chara = character.Character(id: uuid.nil, name: name)
          let updated_chars = list.append(model.characters, [chara])

          #(
            Model(..model, characters: updated_chars, new_character: ""),
            effect.none(),
          )
        }
      }
    }
    UserTypedNewCharacter(text) -> #(
      Model(..model, new_character: text),
      effect.none(),
    )
    UserSaved -> #(
      Model(..model, saving: True),
      save_characters(model.characters),
    )
  }
}

fn save_characters(characters: List(Character)) -> Effect(Msg) {
  let body = character.character_list_to_json(characters)
  let url = "/api/characters"

  rsvp.post(url, body, rsvp.expect_ok_response(ServerSavedCharacters))
}

// View -------------------------------------------------------------------------------- 

fn view(model: Model) -> Element(Msg) {
  let styles = [
    #("max-width", "30ch"),
    #("margin", "0 auto"),
    #("display", "flex"),
    #("flex-direction", "column"),
    #("gap", "1em"),
  ]

  html.div([attribute.styles(styles)], [
    html.h1([], [html.text("Characters")]),
    view_character_list(model.characters),
    view_new_character(model.new_character),
    html.div([], [
      html.button(
        [event.on_click(UserSaved), attribute.disabled(model.saving)],
        [
          html.text(case model.saving {
            True -> "Saving..."
            False -> "Save"
          }),
        ],
      ),
    ]),
    case model.error {
      option.Some(err) ->
        html.div([attribute.style("color", "red")], [html.text(err)])
      option.None -> element.none()
    },
  ])
}

fn view_new_character(new_char: String) -> Element(Msg) {
  html.div([], [
    html.input([
      attribute.placeholder("Character Name"),
      attribute.value(new_char),
      event.on_input(UserTypedNewCharacter),
    ]),
    html.button([event.on_click(UserAddedCharacter)], [html.text("Add")]),
  ])
}

fn view_character_list(characters: List(Character)) -> Element(Msg) {
  case characters {
    [] -> html.p([], [html.text("No dudes yet.")])
    _ -> {
      html.ul(
        [],
        list.map(characters, fn(c) { html.li([], [view_character(c)]) }),
      )
    }
  }
}

fn view_character(character: Character) -> Element(Msg) {
  html.div([attribute.styles([#("display", "flex"), #("gap", "1em")])], [
    html.span([attribute.style("flex", "1")], [html.text(character.name)]),
  ])
}
