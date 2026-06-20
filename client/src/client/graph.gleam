import client/model.{
  type GraphFilter, type Msg, type Remote, Failed, GraphFieldChanged,
  GraphFilterApplied, GraphKindChanged, GraphRelationshipChanged,
  GraphValueChanged, Loaded, Loading,
}
import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared

pub fn graph_filter_view(filter: GraphFilter) -> Element(Msg) {
  html.div(
    [
      attribute.class("panel"),
      attribute.attribute("data-test-id", "graph-filter"),
    ],
    [
      filter_input("graph-kind-input", "Kind", filter.kind, GraphKindChanged),
      filter_input(
        "graph-relationship-input",
        "Relationship",
        filter.relationship,
        GraphRelationshipChanged,
      ),
      filter_input(
        "graph-field-input",
        "Field",
        filter.field,
        GraphFieldChanged,
      ),
      filter_input(
        "graph-value-input",
        "Value",
        filter.value,
        GraphValueChanged,
      ),
      html.button(
        [
          attribute.class("btn-primary"),
          attribute.attribute("data-test-id", "graph-apply"),
          event.on_click(GraphFilterApplied),
        ],
        [element.text("Apply")],
      ),
    ],
  )
}

fn filter_input(
  test_id: String,
  placeholder: String,
  value: String,
  msg: fn(String) -> Msg,
) -> Element(Msg) {
  html.input([
    attribute.attribute("data-test-id", test_id),
    attribute.placeholder(placeholder),
    attribute.value(value),
    event.on_input(msg),
  ])
}

pub fn graph_view(graph: Remote(shared.Graph)) -> Element(Msg) {
  let summary = case graph {
    Loading -> "Loading graph…"
    Failed -> "Could not load graph"
    Loaded(g) ->
      int.to_string(list.length(g.nodes))
      <> " nodes, "
      <> int.to_string(list.length(g.edges))
      <> " edges"
  }
  html.div([], [
    html.p(
      [
        attribute.class("graph__summary"),
        attribute.attribute("data-test-id", "graph-summary"),
      ],
      [element.text(summary)],
    ),
    html.div(
      [
        attribute.class("graph__canvas"),
        attribute.attribute("data-test-id", "graph"),
        attribute.id("graph-canvas"),
      ],
      [],
    ),
  ])
}
