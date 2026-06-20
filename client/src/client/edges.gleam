import client/model.{
  type Model, type Msg, type Remote, EdgeDeleteRequested, EdgeFromSelected,
  EdgeRelationshipChanged, EdgeSubmitted, EdgeToSelected, Failed, Loaded,
  Loading, node_name, relationship_options,
}
import client/ui
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared

pub fn edge_form_view(model: Model) -> Element(Msg) {
  html.div(
    [attribute.class("panel"), attribute.attribute("data-test-id", "edge-form")],
    [
      node_select(
        "edge-from-select",
        model.edge_form.from,
        model.nodes,
        EdgeFromSelected,
      ),
      ui.suggest_input(
        "edge-relationship-input",
        "Relationship",
        model.edge_form.relationship,
        EdgeRelationshipChanged,
        relationship_options(model.edges),
      ),
      node_select(
        "edge-to-select",
        model.edge_form.to,
        model.nodes,
        EdgeToSelected,
      ),
      html.button(
        [
          attribute.class("btn-primary"),
          attribute.attribute("data-test-id", "edge-submit"),
          event.on_click(EdgeSubmitted),
        ],
        [element.text("Add edge")],
      ),
    ],
  )
}

fn node_select(
  test_id: String,
  current: String,
  nodes: Remote(List(shared.Node)),
  msg: fn(String) -> Msg,
) -> Element(Msg) {
  let placeholder =
    html.option(
      [attribute.value(""), attribute.selected(current == "")],
      "Choose a node",
    )
  let options = case nodes {
    Loaded(list) ->
      list.map(list, fn(n) {
        html.option(
          [attribute.value(n.id), attribute.selected(n.id == current)],
          n.name,
        )
      })
    _ -> []
  }
  html.select(
    [attribute.attribute("data-test-id", test_id), event.on_change(msg)],
    [placeholder, ..options],
  )
}

pub fn edges_view(
  edges: Remote(List(shared.Edge)),
  nodes: Remote(List(shared.Node)),
) -> Element(Msg) {
  case edges {
    Loading -> ui.status("Loading edges…")
    Failed -> ui.status("Could not load edges")
    Loaded([]) -> ui.status("No edges yet")
    Loaded(list) ->
      html.ul(
        [
          attribute.class("registry"),
          attribute.attribute("data-test-id", "edge-list"),
        ],
        list.map(list, fn(e) { edge_row(e, nodes) }),
      )
  }
}

fn edge_row(
  edge: shared.Edge,
  nodes: Remote(List(shared.Node)),
) -> Element(Msg) {
  html.li(
    [attribute.class("entry"), attribute.attribute("data-test-id", "edge")],
    [
      html.div([attribute.class("entry__body")], [
        html.span([attribute.attribute("data-test-id", "edge-from")], [
          element.text(node_name(nodes, edge.from)),
        ]),
        html.span(
          [
            attribute.class("relation"),
            attribute.attribute("data-test-id", "edge-relationship"),
          ],
          [element.text(edge.relationship)],
        ),
        html.span([attribute.attribute("data-test-id", "edge-to")], [
          element.text(node_name(nodes, edge.to)),
        ]),
      ]),
      html.div([attribute.class("entry__actions")], [
        html.button([event.on_click(EdgeDeleteRequested(edge.id))], [
          element.text("Delete"),
        ]),
      ]),
    ],
  )
}
