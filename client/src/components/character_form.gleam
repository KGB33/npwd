import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import shared/character
import youid/uuid

pub type Model {
  Model(name: String, io_wait: Bool, error: Option(String))
}

pub type Msg {
  UserTypedName(String)
  Create
  CreateResponse(Result(Response(String), rsvp.Error))
}

pub fn init(_) -> #(Model, Effect(Msg)) {
  #(Model(name: "", io_wait: False, error: option.None), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserTypedName(s) -> #(Model(..model, name: s), effect.none())

    Create ->
      case model.name {
        "" -> #(model, effect.none())
        _ -> {
          let chara = character.Character(id: uuid.nil, name: model.name)
          #(
            Model(..model, io_wait: True),
            rsvp.post(
              "/api/character",
              character.character_to_json(chara),
              rsvp.expect_ok_response(CreateResponse),
            ),
          )
        }
      }

    CreateResponse(Ok(resp)) -> {
      case json.parse(resp.body, character.character_decoder()) {
        Ok(created) -> #(
          Model(name: "", io_wait: False, error: option.None),
          event.emit("character-created", character.character_to_json(created)),
        )
        Error(_) -> #(
          Model(
            ..model,
            io_wait: False,
            error: option.Some("Failed to parse response"),
          ),
          effect.none(),
        )
      }
    }

    CreateResponse(Error(_)) -> #(
      Model(..model, io_wait: False, error: option.Some("Failed to save")),
      effect.none(),
    )
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.input([
      attribute.placeholder("Enter Name"),
      attribute.value(model.name),
      attribute.disabled(model.io_wait),
      event.on_input(UserTypedName),
    ]),
    html.button([event.on_click(Create), attribute.disabled(model.io_wait)], [
      html.text(case model.io_wait {
        True -> "..."
        False -> "+ add"
      }),
    ]),
    case model.error {
      option.Some(err) ->
        html.span([attribute.style("color", "red")], [html.text(err)])
      option.None -> element.none()
    },
  ])
}

pub fn register() -> Result(Nil, lustre.Error) {
  let app = lustre.component(init, update, view, [])
  lustre.register(app, "character-form")
}
