import client/edges
import client/graph
import client/model.{
  type Model, type Msg, Loaded, Loading, LoginEmailChanged, LoginPasswordChanged,
  LoginSubmitted, LogoutClicked, can_edit,
}
import client/nodes
import client/timeline
import client/universes
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared

pub fn view(model: Model) -> Element(Msg) {
  case model.auth {
    Loading ->
      html.div([attribute.class("codex")], [
        masthead("NPWD", "Register of Worlds", []),
        html.p(
          [
            attribute.class("status"),
            attribute.attribute("data-test-id", "status"),
          ],
          [element.text("Loading…")],
        ),
      ])
    _ ->
      case model.selected {
        Some(universe) -> selected_view(model, universe.name)
        None ->
          case model.auth {
            Loaded(Some(user)) -> home_view(model, user)
            _ -> login_view(model)
          }
      }
  }
}

fn login_view(model: Model) -> Element(Msg) {
  html.div([attribute.class("codex")], [
    masthead("NPWD", "Register of Worlds", []),
    html.div(
      [attribute.class("panel"), attribute.attribute("data-test-id", "login")],
      [
        html.input([
          attribute.attribute("data-test-id", "login-email"),
          attribute.type_("email"),
          attribute.placeholder("Email"),
          attribute.value(model.login.email),
          event.on_input(LoginEmailChanged),
        ]),
        html.input([
          attribute.attribute("data-test-id", "login-password"),
          attribute.type_("password"),
          attribute.placeholder("Password"),
          attribute.value(model.login.password),
          event.on_input(LoginPasswordChanged),
        ]),
        html.button(
          [
            attribute.class("btn-primary"),
            attribute.attribute("data-test-id", "login-submit"),
            event.on_click(LoginSubmitted),
          ],
          [element.text("Sign in")],
        ),
        ..case model.login.failed {
          True -> [
            html.p(
              [
                attribute.class("status"),
                attribute.attribute("data-test-id", "login-error"),
              ],
              [element.text("Wrong email or password")],
            ),
          ]
          False -> []
        }
      ],
    ),
  ])
}

fn home_view(model: Model, user: shared.User) -> Element(Msg) {
  html.div([attribute.class("codex")], [
    masthead("NPWD", "Register of Worlds", [signed_in(user.email)]),
    chapter("New entry", [universes.form_view(model)]),
    chapter("The worlds", [universes.universes_view(model.universes)]),
  ])
}

fn signed_in(email: String) -> Element(Msg) {
  html.div([attribute.class("masthead__account")], [
    html.span([attribute.attribute("data-test-id", "account")], [
      element.text(email),
    ]),
    html.button(
      [
        attribute.attribute("data-test-id", "logout"),
        event.on_click(LogoutClicked),
      ],
      [element.text("Sign out")],
    ),
  ])
}

fn selected_view(model: Model, title: String) -> Element(Msg) {
  let editable = can_edit(model)
  html.div([attribute.class("codex")], [
    masthead(title, "A chronicle", [
      html.a(
        [
          attribute.class("masthead__back"),
          attribute.attribute("data-test-id", "back"),
          attribute.href("/"),
        ],
        [element.text("← Back to the shelf")],
      ),
    ]),
    chapter("The web", [
      graph.graph_filter_view(model),
      graph.graph_view(model.graph),
    ]),
    chapter("Chronicle", [timeline.timeline_view(model.timeline, model.nodes)]),
    chapter("Catalogue", gated(editable, nodes.node_form_view(model), [
      nodes.nodes_view(model.nodes, editable),
    ])),
    chapter("Relations", gated(editable, edges.edge_form_view(model), [
      edges.edges_view(model.edges, model.nodes, editable),
    ])),
  ])
}

fn gated(
  editable: Bool,
  form: Element(Msg),
  rest: List(Element(Msg)),
) -> List(Element(Msg)) {
  case editable {
    True -> [form, ..rest]
    False -> rest
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
