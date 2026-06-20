import client/model.{
  type KindForm, type Model, type Msg, type Remote, DayChanged, EventForm, Failed,
  GenderChanged, GenericFieldAdded, GenericFieldRemoved, GenericForm,
  GenericKeyChanged, GenericValueChanged, KindSelected, Loaded, Loading,
  MonthChanged, NodeDeleteRequested, NodeDescriptionChanged, NodeEditCancelled,
  NodeEditStarted, NodeNameChanged, NodeSubmitted, PersonForm, PlaceForm,
  YearChanged, kind_label, kind_name,
}
import client/ui
import gleam/list
import gleam/option.{None}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared

pub fn node_form_view(model: Model) -> Element(Msg) {
  let editing = model.editing_node != None
  let submit_label = case editing {
    True -> "Save"
    False -> "Create"
  }
  html.div([attribute.attribute("data-test-id", "node-form")], [
    html.input([
      attribute.attribute("data-test-id", "node-name-input"),
      attribute.placeholder("Name"),
      attribute.value(model.node_form.name),
      event.on_input(NodeNameChanged),
    ]),
    html.input([
      attribute.attribute("data-test-id", "node-description-input"),
      attribute.placeholder("Description"),
      attribute.value(model.node_form.description),
      event.on_input(NodeDescriptionChanged),
    ]),
    kind_select(model.node_form.kind),
    kind_fields_view(model.node_form.kind),
    html.button(
      [
        attribute.attribute("data-test-id", "node-submit"),
        event.on_click(NodeSubmitted),
      ],
      [element.text(submit_label)],
    ),
    ..case editing {
      True -> [
        html.button([event.on_click(NodeEditCancelled)], [
          element.text("Cancel"),
        ]),
      ]
      False -> []
    }
  ])
}

fn kind_select(kind: KindForm) -> Element(Msg) {
  let current = kind_name(kind)
  html.select(
    [
      attribute.attribute("data-test-id", "kind-select"),
      event.on_change(KindSelected),
    ],
    list.map(["Person", "Place", "Event", "Generic"], fn(name) {
      html.option(
        [attribute.value(name), attribute.selected(name == current)],
        name,
      )
    }),
  )
}

fn kind_fields_view(kind: KindForm) -> Element(Msg) {
  case kind {
    PlaceForm -> html.div([], [])
    PersonForm(year, month, day, gender) ->
      html.div([], [
        date_inputs(year, month, day),
        html.input([
          attribute.attribute("data-test-id", "gender-input"),
          attribute.placeholder("Gender"),
          attribute.value(gender),
          event.on_input(GenderChanged),
        ]),
      ])
    EventForm(year, month, day) -> date_inputs(year, month, day)
    GenericForm(fields) ->
      html.div(
        [attribute.attribute("data-test-id", "generic-fields")],
        list.append(list.index_map(fields, generic_row), [
          html.button(
            [
              attribute.attribute("data-test-id", "generic-add"),
              event.on_click(GenericFieldAdded),
            ],
            [element.text("Add field")],
          ),
        ]),
      )
  }
}

fn date_inputs(year: String, month: String, day: String) -> Element(Msg) {
  html.div([], [
    html.input([
      attribute.attribute("data-test-id", "year-input"),
      attribute.placeholder("Year"),
      attribute.value(year),
      event.on_input(YearChanged),
    ]),
    html.input([
      attribute.attribute("data-test-id", "month-input"),
      attribute.placeholder("Month"),
      attribute.value(month),
      event.on_input(MonthChanged),
    ]),
    html.input([
      attribute.attribute("data-test-id", "day-input"),
      attribute.placeholder("Day"),
      attribute.value(day),
      event.on_input(DayChanged),
    ]),
  ])
}

fn generic_row(field: #(String, String), index: Int) -> Element(Msg) {
  html.div([attribute.attribute("data-test-id", "generic-row")], [
    html.input([
      attribute.attribute("data-test-id", "generic-key"),
      attribute.placeholder("Key"),
      attribute.value(field.0),
      event.on_input(GenericKeyChanged(index, _)),
    ]),
    html.input([
      attribute.attribute("data-test-id", "generic-value"),
      attribute.placeholder("Value"),
      attribute.value(field.1),
      event.on_input(GenericValueChanged(index, _)),
    ]),
    html.button([event.on_click(GenericFieldRemoved(index))], [
      element.text("Remove"),
    ]),
  ])
}

pub fn nodes_view(nodes: Remote(List(shared.Node))) -> Element(Msg) {
  case nodes {
    Loading -> ui.status("Loading nodes…")
    Failed -> ui.status("Could not load nodes")
    Loaded([]) -> ui.status("No nodes yet")
    Loaded(list) ->
      html.ul(
        [attribute.attribute("data-test-id", "node-list")],
        list.map(list, node_row),
      )
  }
}

fn node_row(node: shared.Node) -> Element(Msg) {
  html.li([attribute.attribute("data-test-id", "node")], [
    html.span([attribute.attribute("data-test-id", "node-name")], [
      element.text(node.name),
    ]),
    html.span([attribute.attribute("data-test-id", "node-kind")], [
      element.text(kind_label(node.kind)),
    ]),
    html.button([event.on_click(NodeEditStarted(node))], [element.text("Edit")]),
    html.button([event.on_click(NodeDeleteRequested(node.id))], [
      element.text("Delete"),
    ]),
  ])
}
