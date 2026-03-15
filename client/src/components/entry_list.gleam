import gleam/dynamic/decode
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import lustre
import lustre/attribute
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import shared/character.{type Character}
import shared/entry.{type Entry}
import youid/uuid

pub type Model {
  Model(
    character: Character,
    entries: List(Entry),
    new_text: String,
    io_wait: Bool,
  )
}

pub type Msg {
  SetCharacter(Character)
  EntriesLoaded(Result(Response(String), rsvp.Error))
  UserTypedText(String)
  Submit
  SubmitResponse(Result(Response(String), rsvp.Error))
  DeleteEntry(uuid.Uuid)
  DeleteResponse(uuid.Uuid, Result(Response(String), rsvp.Error))
}

fn init(_) -> #(Model, Effect(Msg)) {
  #(
    Model(
      character: character.Character(id: uuid.nil, name: ""),
      entries: [],
      new_text: "",
      io_wait: False,
    ),
    effect.none(),
  )
}

fn fetch_entries(character_id: uuid.Uuid) -> Effect(Msg) {
  let url = "/api/character/" <> uuid.to_string(character_id) <> "/entries"
  rsvp.get(url, rsvp.expect_ok_response(EntriesLoaded))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SetCharacter(c) -> #(
      Model(..model, character: c, entries: []),
      fetch_entries(c.id),
    )

    EntriesLoaded(Ok(resp)) -> {
      case json.parse(resp.body, decode.list(entry.entry_decoder())) {
        Ok(entries) -> #(Model(..model, entries: entries), effect.none())
        Error(_) -> #(model, effect.none())
      }
    }

    EntriesLoaded(Error(_)) -> #(model, effect.none())

    UserTypedText(s) -> #(Model(..model, new_text: s), effect.none())

    Submit ->
      case model.new_text {
        "" -> #(model, effect.none())
        _ -> {
          let body =
            json.object([
              #("character_id", json.string(uuid.to_string(model.character.id))),
              #("text", json.string(model.new_text)),
            ])
          #(
            Model(..model, io_wait: True),
            rsvp.post(
              "/api/entry",
              body,
              rsvp.expect_ok_response(SubmitResponse),
            ),
          )
        }
      }

    SubmitResponse(Ok(resp)) -> {
      case json.parse(resp.body, entry.entry_decoder()) {
        Ok(new_entry) -> #(
          Model(
            ..model,
            entries: list.append(model.entries, [new_entry]),
            new_text: "",
            io_wait: False,
          ),
          effect.none(),
        )
        Error(_) -> #(Model(..model, io_wait: False), effect.none())
      }
    }

    SubmitResponse(Error(_)) -> #(Model(..model, io_wait: False), effect.none())

    DeleteEntry(id) -> {
      let url = "/api/entry/" <> uuid.to_string(id)
      #(
        model,
        rsvp.delete(
          url,
          json.object([]),
          rsvp.expect_ok_response(DeleteResponse(id, _)),
        ),
      )
    }

    DeleteResponse(id, Ok(_)) -> #(
      Model(..model, entries: list.filter(model.entries, fn(e) { e.id != id })),
      effect.none(),
    )

    DeleteResponse(_, Error(_)) -> #(model, effect.none())
  }
}

fn view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.styles([
        #("padding", "1em"),
        #("display", "flex"),
        #("flex-direction", "column"),
        #("gap", "1em"),
      ]),
    ],
    [
      html.h2([], [html.text(model.character.name)]),
      case model.entries {
        [] -> html.p([], [html.text("No entries yet.")])
        entries ->
          html.ul(
            [],
            list.map(entries, fn(e) {
              html.li(
                [attribute.styles([#("display", "flex"), #("gap", "0.5em")])],
                [
                  html.span([attribute.style("flex", "1")], [html.text(e.text)]),
                  html.button([event.on_click(DeleteEntry(e.id))], [
                    html.text("🗑️"),
                  ]),
                ],
              )
            }),
          )
      },
      html.div([attribute.styles([#("display", "flex"), #("gap", "0.5em")])], [
        html.textarea(
          [
            attribute.placeholder("New entry..."),
            attribute.value(model.new_text),
            attribute.disabled(model.io_wait),
            event.on_input(UserTypedText),
          ],
          model.new_text,
        ),
        html.button(
          [event.on_click(Submit), attribute.disabled(model.io_wait)],
          [
            html.text(case model.io_wait {
              True -> "..."
              False -> "Add"
            }),
          ],
        ),
      ]),
    ],
  )
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
  lustre.register(app, "entry-list")
}
