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
      html.div([attribute.class("codex")], [
        masthead("NPWD", "Register of Worlds", []),
        chapter("New entry", [universes.form_view(model)]),
        chapter("The worlds", [universes.universes_view(model.universes)]),
      ])
    Some(universe) ->
      html.div([attribute.class("codex")], [
        masthead(universe.name, "A chronicle", [
          html.button(
            [
              attribute.class("masthead__back"),
              attribute.attribute("data-test-id", "back"),
              event.on_click(UniverseDeselected),
            ],
            [element.text("← Back to the shelf")],
          ),
        ]),
        chapter("The web", [
          graph.graph_filter_view(model),
          graph.graph_view(model.graph),
        ]),
        chapter("Chronicle", [
          timeline.timeline_view(model.timeline, model.nodes),
        ]),
        chapter("Catalogue", [
          nodes.node_form_view(model),
          nodes.nodes_view(model.nodes),
        ]),
        chapter("Relations", [
          edges.edge_form_view(model),
          edges.edges_view(model.edges, model.nodes),
        ]),
      ])
  }
}

fn masthead(
  title: String,
  subtitle: String,
  lead: List(Element(Msg)),
) -> Element(Msg) {
  html.header([attribute.class("masthead")], [
    html.div([attribute.class("masthead__lead")], lead),
    html.h1([attribute.class("masthead__title")], [element.text(title)]),
    html.div([attribute.class("masthead__sub")], [element.text(subtitle)]),
  ])
}

fn chapter(title: String, body: List(Element(Msg))) -> Element(Msg) {
  html.section([attribute.class("chapter")], [
    html.h2([attribute.class("chapter__title")], [element.text(title)]),
    ..body
  ])
}
