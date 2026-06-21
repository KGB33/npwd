import client/model.{
  type Model, type Msg, type Remote, DescriptionBodyChanged,
  DescriptionDeleteRequested, DescriptionSubmitted, Failed, GenericFieldAdded,
  GenericFieldRemoved, GenericKeyChanged, GenericValueChanged, Loaded, Loading,
  NodeDeleteRequested, NodeEditCancelled, NodeEditStarted, NodeKindChanged,
  NodeNameChanged, NodeSubmitted, field_key_options, kind_suggestions,
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
      ui.suggest_input(
        "node-kind-input",
        "Kind",
        model.node_form.kind,
        NodeKindChanged,
        kind_suggestions(model.nodes),
      ),
      fields_view(model.node_form.fields, model.nodes),
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
          descriptions_view(model),
        ]
        False -> []
      }
    ],
  )
}

fn fields_view(
  fields: List(#(String, String)),
  nodes: Remote(List(shared.Node)),
) -> Element(Msg) {
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

fn descriptions_view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class("descriptions"),
      attribute.attribute("data-test-id", "descriptions"),
    ],
    [
      html.p([attribute.class("descriptions__head")], [
        element.text("Annotations"),
      ]),
      descriptions_list(model.descriptions),
      html.div([attribute.class("descriptions__compose")], [
        html.textarea(
          [
            attribute.class("descriptions__field"),
            attribute.attribute("data-test-id", "description-input"),
            attribute.placeholder("Note an entry — two or three sentences"),
            attribute.value(model.description_form),
            event.on_input(DescriptionBodyChanged),
          ],
          model.description_form,
        ),
        html.button(
          [
            attribute.class("btn-primary"),
            attribute.attribute("data-test-id", "description-add"),
            event.on_click(DescriptionSubmitted),
          ],
          [element.text("Add entry")],
        ),
      ]),
    ],
  )
}

fn descriptions_list(descriptions: Remote(List(shared.Description))) -> Element(Msg) {
  case descriptions {
    Loading -> ui.status("Loading entries…")
    Failed -> ui.status("Could not load entries")
    Loaded([]) -> ui.status("No entries yet")
    Loaded(list) ->
      html.ol(
        [attribute.class("descriptions__list")],
        list.map(list, description_row),
      )
  }
}

fn description_row(d: shared.Description) -> Element(Msg) {
  html.li(
    [
      attribute.class("description"),
      attribute.attribute("data-test-id", "description"),
    ],
    [
      html.p(
        [
          attribute.class("description-body"),
          attribute.attribute("data-test-id", "description-body"),
        ],
        [element.text(d.body)],
      ),
      html.button(
        [
          attribute.class("description-delete"),
          attribute.attribute("data-test-id", "description-delete"),
          event.on_click(DescriptionDeleteRequested(d.id)),
        ],
        [element.text("Delete")],
      ),
    ],
  )
}

pub fn nodes_view(
  nodes: Remote(List(shared.Node)),
  can_edit: Bool,
) -> Element(Msg) {
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
        list.map(list, fn(n) { node_row(n, can_edit) }),
      )
  }
}

fn node_row(node: shared.Node, can_edit: Bool) -> Element(Msg) {
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
        ..case node.kind {
          "" -> []
          kind -> [
            html.span(
              [
                attribute.class("kind"),
                attribute.attribute("data-test-id", "node-kind"),
              ],
              [element.text(kind)],
            ),
          ]
        }
      ]),
      ..case can_edit {
        True -> [
          html.div([attribute.class("entry__actions")], [
            html.button([event.on_click(NodeEditStarted(node))], [
              element.text("Edit"),
            ]),
            html.button([event.on_click(NodeDeleteRequested(node.id))], [
              element.text("Delete"),
            ]),
          ]),
        ]
        False -> []
      }
    ],
  )
}
