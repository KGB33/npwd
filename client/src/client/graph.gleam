import client/model.{
  type Model, type Msg, type Remote, Failed, GraphFieldChanged,
  GraphFilterApplied, GraphKindChanged, GraphRelationshipChanged,
  GraphValueChanged, Loaded, Loading, field_key_options, field_value_options,
  kind_options, relationship_options,
}
import client/ui
import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared

pub fn graph_filter_view(model: Model) -> Element(Msg) {
  let filter = model.graph_filter
  html.div(
    [
      attribute.class("panel"),
      attribute.attribute("data-test-id", "graph-filter"),
    ],
    [
      ui.suggest_input(
        "graph-kind-input",
        "Kind",
        filter.kind,
        GraphKindChanged,
        kind_options(),
      ),
      ui.suggest_input(
        "graph-relationship-input",
        "Relationship",
        filter.relationship,
        GraphRelationshipChanged,
        relationship_options(model.edges),
      ),
      ui.suggest_input(
        "graph-field-input",
        "Field",
        filter.field,
        GraphFieldChanged,
        field_key_options(model.nodes),
      ),
      ui.suggest_input(
        "graph-value-input",
        "Value",
        filter.value,
        GraphValueChanged,
        field_value_options(model.nodes),
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
