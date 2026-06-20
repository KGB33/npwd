import client/edges
import client/graph
import client/model.{type Model, type Msg, UniverseDeselected}
import client/nodes
import client/timeline
import client/universes
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn view(model: Model) -> Element(Msg) {
  case model.selected {
    None ->
      html.div([], [
        html.h1([], [element.text("NPWD")]),
        universes.form_view(model),
        universes.universes_view(model.universes),
      ])
    Some(universe) ->
      html.div([], [
        html.h1([], [element.text(universe.name)]),
        html.button(
          [
            attribute.attribute("data-test-id", "back"),
            event.on_click(UniverseDeselected),
          ],
          [element.text("Back")],
        ),
        nodes.node_form_view(model),
        nodes.nodes_view(model.nodes),
        edges.edge_form_view(model),
        edges.edges_view(model.edges, model.nodes),
        graph.graph_filter_view(model.graph_filter),
        graph.graph_view(model.graph),
        timeline.timeline_view(model.timeline, model.nodes),
      ])
  }
}
