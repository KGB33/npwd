import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import shared

pub type Remote(a) {
  Loading
  Loaded(a)
  Failed
}

pub type Form {
  Form(name: String, description: String)
}

pub type Model {
  Model(
    universes: Remote(List(shared.Universe)),
    form: Form,
    editing: Option(String),
  )
}

pub type Msg {
  UniversesLoaded(Result(List(shared.Universe), rsvp.Error(String)))
  NameChanged(String)
  DescriptionChanged(String)
  Submitted
  Saved(Result(shared.Universe, rsvp.Error(String)))
  EditStarted(shared.Universe)
  EditCancelled
  DeleteRequested(String)
  DeleteResolved(Result(String, rsvp.Error(String)))
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub fn init(_args) -> #(Model, Effect(Msg)) {
  #(
    Model(universes: Loading, form: empty_form, editing: None),
    load_universes(),
  )
}

const empty_form = Form(name: "", description: "")

fn load_universes() -> Effect(Msg) {
  rsvp.get(
    "/universes",
    rsvp.expect_json(decode.list(shared.universe_decoder()), UniversesLoaded),
  )
}

fn save(model: Model) -> Effect(Msg) {
  let body =
    json.object([
      #("name", json.string(model.form.name)),
      #("description", json.string(model.form.description)),
    ])
  let handler = rsvp.expect_json(shared.universe_decoder(), Saved)
  case model.editing {
    None -> rsvp.post("/universes", body, handler)
    Some(id) -> rsvp.put("/universes/" <> id, body, handler)
  }
}

fn delete(id: String) -> Effect(Msg) {
  rsvp.delete(
    "/universes/" <> id,
    json.null(),
    rsvp.expect_text(DeleteResolved),
  )
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UniversesLoaded(Ok(universes)) -> #(
      Model(..model, universes: Loaded(universes)),
      effect.none(),
    )
    UniversesLoaded(Error(_)) -> #(
      Model(..model, universes: Failed),
      effect.none(),
    )
    NameChanged(name) -> #(
      Model(..model, form: Form(..model.form, name:)),
      effect.none(),
    )
    DescriptionChanged(description) -> #(
      Model(..model, form: Form(..model.form, description:)),
      effect.none(),
    )
    Submitted -> #(model, save(model))
    Saved(Ok(_)) -> #(
      Model(..model, form: empty_form, editing: None),
      load_universes(),
    )
    Saved(Error(_)) -> #(model, effect.none())
    EditStarted(universe) -> #(
      Model(
        ..model,
        editing: Some(universe.id),
        form: Form(universe.name, universe.description),
      ),
      effect.none(),
    )
    EditCancelled -> #(
      Model(..model, editing: None, form: empty_form),
      effect.none(),
    )
    DeleteRequested(id) -> #(model, delete(id))
    DeleteResolved(_) -> #(model, load_universes())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [element.text("NPWD")]),
    form_view(model),
    universes_view(model.universes),
  ])
}

fn form_view(model: Model) -> Element(Msg) {
  let editing = model.editing != None
  let submit_label = case editing {
    True -> "Save"
    False -> "Create"
  }
  html.div([attribute.attribute("data-test-id", "form")], [
    html.input([
      attribute.attribute("data-test-id", "name-input"),
      attribute.placeholder("Name"),
      attribute.value(model.form.name),
      event.on_input(NameChanged),
    ]),
    html.input([
      attribute.attribute("data-test-id", "description-input"),
      attribute.placeholder("Description"),
      attribute.value(model.form.description),
      event.on_input(DescriptionChanged),
    ]),
    html.button(
      [attribute.attribute("data-test-id", "submit"), event.on_click(Submitted)],
      [element.text(submit_label)],
    ),
    ..case editing {
      True -> [
        html.button([event.on_click(EditCancelled)], [element.text("Cancel")]),
      ]
      False -> []
    }
  ])
}

fn universes_view(universes: Remote(List(shared.Universe))) -> Element(Msg) {
  case universes {
    Loading -> status("Loading universes…")
    Failed -> status("Could not load universes")
    Loaded([]) -> status("No universes yet")
    Loaded(list) ->
      html.ul(
        [attribute.attribute("data-test-id", "universe-list")],
        list.map(list, universe_row),
      )
  }
}

fn universe_row(universe: shared.Universe) -> Element(Msg) {
  html.li([attribute.attribute("data-test-id", "universe")], [
    html.span([attribute.attribute("data-test-id", "universe-name")], [
      element.text(universe.name),
    ]),
    html.button([event.on_click(EditStarted(universe))], [element.text("Edit")]),
    html.button([event.on_click(DeleteRequested(universe.id))], [
      element.text("Delete"),
    ]),
  ])
}

fn status(text: String) -> Element(Msg) {
  html.p([attribute.attribute("data-test-id", "status")], [element.text(text)])
}
