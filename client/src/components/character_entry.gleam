import gleam/http/response.{type Response}
import gleam/json
import lustre
import lustre/attribute
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import shared/character.{type Character}
import youid/uuid

pub type Model {
  Model(c: Character, io_wait: Bool)
}

pub type Msg {
  SetCharacter(Character)
  Delete
  DeleteResponse(Result(Response(String), rsvp.Error))
}

fn init(_) -> #(Model, Effect(Msg)) {
  #(
    Model(c: character.Character(id: uuid.nil, name: ""), io_wait: False),
    effect.none(),
  )
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SetCharacter(c) -> #(Model(..model, c: c), effect.none())

    Delete -> {
      let url = "/api/character/" <> uuid.to_string(model.c.id)
      #(
        Model(..model, io_wait: True),
        rsvp.delete(url, json.object([]), rsvp.expect_ok_response(DeleteResponse)),
      )
    }

    DeleteResponse(Ok(_)) -> {
      let payload =
        json.object([#("id", json.string(uuid.to_string(model.c.id)))])
      #(model, event.emit("character-deleted", payload))
    }

    DeleteResponse(Error(_)) -> #(Model(..model, io_wait: False), effect.none())
  }
}

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.styles([#("display", "flex"), #("gap", "1em")])], [
    html.span([attribute.style("flex", "1")], [html.text(model.c.name)]),
    html.button(
      [event.on_click(Delete), attribute.disabled(model.io_wait)],
      [html.text(case model.io_wait { True -> "..." False -> "🗑️" })],
    ),
  ])
}

pub fn register() -> Result(Nil, lustre.Error) {
  let app =
    lustre.component(init, update, view, [
      component.on_attribute_change("character", fn(str) {
        case json.parse(str, character.character_decoder()) {
          Ok(c) -> Ok(SetCharacter(c))
          Error(_) -> Error(Nil)
        }
      }),
    ])
  lustre.register(app, "character-entry")
}
