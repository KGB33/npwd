import client/model.{
  type Msg, type Remote, Failed, Loaded, Loading, node_field, node_name,
}
import client/ui
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import shared

pub fn timeline_view(
  timeline: Remote(shared.Graph),
  nodes: Remote(List(shared.Node)),
) -> Element(Msg) {
  case timeline {
    Loading -> ui.status("Loading timeline…")
    Failed -> ui.status("Could not load timeline")
    Loaded(g) ->
      case g.nodes {
        [] -> ui.status("No events yet")
        events ->
          html.ol(
            [
              attribute.class("chronicle"),
              attribute.attribute("data-test-id", "timeline"),
            ],
            list.map(events, fn(ev) { timeline_event(ev, g.edges, nodes) }),
          )
      }
  }
}

fn timeline_event(
  event: shared.Node,
  edges: List(shared.Edge),
  nodes: Remote(List(shared.Node)),
) -> Element(Msg) {
  let incident =
    list.filter(edges, fn(e) { e.from == event.id || e.to == event.id })
  html.li(
    [
      attribute.class("event"),
      attribute.attribute("data-test-id", "timeline-event"),
    ],
    [
      html.span(
        [
          attribute.class("event__when"),
          attribute.attribute("data-test-id", "timeline-when"),
        ],
        [element.text(node_field(event, "when"))],
      ),
      html.span(
        [
          attribute.class("event__name"),
          attribute.attribute("data-test-id", "timeline-name"),
        ],
        [element.text(event.name)],
      ),
      html.ul(
        [attribute.class("event__links")],
        list.map(incident, fn(e) { timeline_link(event, e, nodes) }),
      ),
    ],
  )
}

fn timeline_link(
  event: shared.Node,
  edge: shared.Edge,
  nodes: Remote(List(shared.Node)),
) -> Element(Msg) {
  let other = case edge.from == event.id {
    True -> edge.to
    False -> edge.from
  }
  html.li(
    [
      attribute.class("marginalia"),
      attribute.attribute("data-test-id", "timeline-link"),
    ],
    [element.text(edge.relationship <> " → " <> node_name(nodes, other))],
  )
}
