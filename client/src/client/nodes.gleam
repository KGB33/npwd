import client/model.{
  type KindForm, type Model, type Msg, type Remote, DayChanged, EventForm,
  Failed, GenderChanged, GenericFieldAdded, GenericFieldRemoved, GenericForm,
  GenericKeyChanged, GenericValueChanged, KindSelected, Loaded, Loading,
  MonthChanged, NodeDeleteRequested, NodeDescriptionChanged, NodeEditCancelled,
  NodeEditStarted, NodeNameChanged, NodeSubmitted, PersonForm, PlaceForm,
  YearChanged, field_key_options, gender_options, kind_label, kind_name,
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
  html.div(
    [attribute.class("panel"), attribute.attribute("data-test-id", "node-form")],
    [
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
      kind_fields_view(model.node_form.kind, model.nodes),
      html.button(
        [
          attribute.class("btn-primary"),
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
    ],
  )
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

fn kind_fields_view(
  kind: KindForm,
  nodes: Remote(List(shared.Node)),
) -> Element(Msg) {
  case kind {
    PlaceForm -> html.div([], [])
    PersonForm(year, month, day, gender) ->
      html.div([attribute.class("subfields")], [
        date_inputs(year, month, day),
        ui.suggest_input(
          "gender-input",
          "Gender",
          gender,
          GenderChanged,
          gender_options(nodes),
        ),
      ])
    EventForm(year, month, day) -> date_inputs(year, month, day)
    GenericForm(fields) ->
      html.div(
        [
          attribute.class("subfields"),
          attribute.attribute("data-test-id", "generic-fields"),
        ],
        list.append(
          list.index_map(fields, fn(field, i) {
            generic_row(field, i, field_key_options(nodes))
          }),
          [
            html.button(
              [
                attribute.attribute("data-test-id", "generic-add"),
                event.on_click(GenericFieldAdded),
              ],
              [element.text("Add field")],
            ),
          ],
        ),
      )
  }
}

fn date_inputs(year: String, month: String, day: String) -> Element(Msg) {
  html.div([attribute.class("date-inputs")], [
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

fn generic_row(
  field: #(String, String),
  index: Int,
  keys: List(String),
) -> Element(Msg) {
  html.div(
    [
      attribute.class("generic-row"),
      attribute.attribute("data-test-id", "generic-row"),
    ],
    [
      ui.suggest_input(
        "generic-key",
        "Key",
        field.0,
        GenericKeyChanged(index, _),
        keys,
      ),
      html.input([
        attribute.attribute("data-test-id", "generic-value"),
        attribute.placeholder("Value"),
        attribute.value(field.1),
        event.on_input(GenericValueChanged(index, _)),
      ]),
      html.button([event.on_click(GenericFieldRemoved(index))], [
        element.text("Remove"),
      ]),
    ],
  )
}

pub fn nodes_view(nodes: Remote(List(shared.Node))) -> Element(Msg) {
  case nodes {
    Loading -> ui.status("Loading nodes…")
    Failed -> ui.status("Could not load nodes")
    Loaded([]) -> ui.status("No nodes yet")
    Loaded(list) ->
      html.ul(
        [
          attribute.class("registry"),
          attribute.attribute("data-test-id", "node-list"),
        ],
        list.map(list, node_row),
      )
  }
}

fn node_row(node: shared.Node) -> Element(Msg) {
  html.li(
    [attribute.class("entry"), attribute.attribute("data-test-id", "node")],
    [
      html.div([attribute.class("entry__body")], [
        html.span(
          [
            attribute.class("entry__name"),
            attribute.attribute("data-test-id", "node-name"),
          ],
          [element.text(node.name)],
        ),
        html.span(
          [
            attribute.class("kind"),
            attribute.attribute("data-test-id", "node-kind"),
          ],
          [element.text(kind_label(node.kind))],
        ),
      ]),
      html.div([attribute.class("entry__actions")], [
        html.button([event.on_click(NodeEditStarted(node))], [
          element.text("Edit"),
        ]),
        html.button([event.on_click(NodeDeleteRequested(node.id))], [
          element.text("Delete"),
        ]),
      ]),
    ],
  )
}
