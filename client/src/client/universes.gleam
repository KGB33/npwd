import client/model.{
  type Model, type Msg, type Remote, DeleteRequested, DescriptionChanged,
  EditCancelled, EditStarted, Failed, Loaded, Loading, NameChanged, Submitted,
  UniverseSelected,
}
import client/ui
import gleam/list
import gleam/option.{None}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared

pub fn form_view(model: Model) -> Element(Msg) {
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

pub fn universes_view(universes: Remote(List(shared.Universe))) -> Element(Msg) {
  case universes {
    Loading -> ui.status("Loading universes…")
    Failed -> ui.status("Could not load universes")
    Loaded([]) -> ui.status("No universes yet")
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
    html.button(
      [
        attribute.attribute("data-test-id", "open"),
        event.on_click(UniverseSelected(universe)),
      ],
      [element.text("Open")],
    ),
    html.button([event.on_click(EditStarted(universe))], [element.text("Edit")]),
    html.button([event.on_click(DeleteRequested(universe.id))], [
      element.text("Delete"),
    ]),
  ])
}
