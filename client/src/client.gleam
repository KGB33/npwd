import client/model.{
  type GraphFilter, type Model, type Msg, DeleteRequested, DeleteResolved,
  DescriptionBodyChanged, DescriptionChanged, DescriptionDeleteRequested,
  DescriptionDeleteResolved, DescriptionSaved, DescriptionSubmitted,
  DescriptionsLoaded, EdgeDeleteRequested, EdgeDeleteResolved, EdgeForm,
  EdgeFromSelected, EdgeRelationshipChanged, EdgeSaved, EdgeSubmitted,
  EdgeToSelected, EdgesLoaded, EditCancelled, EditStarted, Failed, Form,
  GenericFieldAdded, GenericFieldRemoved, GenericKeyChanged, GenericValueChanged,
  GraphFieldChanged, GraphFilter, GraphFilterApplied, GraphFilterCleared,
  GraphFromChanged, GraphLoaded, GraphRelationshipChanged, GraphToChanged,
  GraphValueChanged, Home, Loaded, Loading, LoginEmailChanged, LoginForm,
  LoginPasswordChanged, LoginSubmitted, LogoutClicked, MeLoaded, Model,
  NameChanged, NodeDeleteRequested, NodeDeleteResolved, NodeEditCancelled,
  NodeEditStarted, NodeForm, NodeKindChanged, NodeNameChanged, NodeSaved,
  NodeSubmitted, NodesLoaded, RouteChanged, Saved, SignedIn, SignedOut,
  Submitted, TimelineLoaded, UniverseDeselected, UniverseFetched,
  UniverseSelected, UniverseView, UniversesLoaded, description_body, edge_body,
  edge_submittable, empty_edge_form, empty_form, empty_graph_filter, empty_login,
  empty_node_form, graph_query, login_body, node_body, node_to_form,
  route_from_path, update_at,
}
import client/view
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/uri
import lustre
import lustre/effect.{type Effect}
import modem
import rsvp
import shared

pub fn main() -> Nil {
  let app = lustre.application(init, update, view.view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub fn init(_args) -> #(Model, Effect(Msg)) {
  let route = route_from_path(current_pathname())
  #(
    Model(
      auth: Loading,
      login: empty_login,
      route: route,
      universes: Loading,
      form: empty_form,
      editing: None,
      selected: None,
      nodes: Loading,
      node_form: empty_node_form,
      editing_node: None,
      descriptions: Loaded([]),
      description_form: "",
      edges: Loading,
      edge_form: empty_edge_form,
      graph: Loading,
      graph_filter: empty_graph_filter,
      timeline: Loading,
    ),
    effect.batch([load_me(), modem.init(on_route), route_effect(route)]),
  )
}

fn on_route(uri: uri.Uri) -> Msg {
  RouteChanged(route_from_path(uri.path))
}

fn route_effect(route) -> Effect(Msg) {
  case route {
    UniverseView(id) -> load_universe(id)
    Home -> effect.none()
  }
}

@external(javascript, "./route_ffi.mjs", "pathname")
fn current_pathname() -> String {
  "/"
}

fn load_me() -> Effect(Msg) {
  rsvp.get("/me", rsvp.expect_json(shared.user_decoder(), MeLoaded))
}

fn load_universe(id: String) -> Effect(Msg) {
  rsvp.get(
    "/universes/" <> id,
    rsvp.expect_json(shared.universe_decoder(), UniverseFetched),
  )
}

fn sign_in(model: Model) -> Effect(Msg) {
  rsvp.post(
    "/auth/signin",
    login_body(model.login),
    rsvp.expect_json(shared.user_decoder(), SignedIn),
  )
}

fn sign_out() -> Effect(Msg) {
  rsvp.post("/auth/signout", json.null(), rsvp.expect_text(SignedOut))
}

fn load_universes() -> Effect(Msg) {
  rsvp.get(
    "/universes",
    rsvp.expect_json(decode.list(shared.universe_decoder()), UniversesLoaded),
  )
}

fn load_nodes(universe: String) -> Effect(Msg) {
  rsvp.get(
    "/universes/" <> universe <> "/nodes",
    rsvp.expect_json(decode.list(shared.node_decoder()), NodesLoaded),
  )
}

fn save(model: Model) -> Effect(Msg) {
  let body =
    json.object([
      #("name", json.string(model.form.name)),
      #("description", json.string(model.form.description)),
    ])
  let handler = rsvp.expect_json(shared.universe_decoder(), Saved)
  case model.editing {
    None -> rsvp.post("/universes", body, handler)
    Some(id) -> rsvp.put("/universes/" <> id, body, handler)
  }
}

fn delete(id: String) -> Effect(Msg) {
  rsvp.delete(
    "/universes/" <> id,
    json.null(),
    rsvp.expect_text(DeleteResolved),
  )
}

fn selected_effect(
  model: Model,
  then: fn(shared.Universe) -> Effect(Msg),
) -> Effect(Msg) {
  case model.selected {
    Some(universe) -> then(universe)
    None -> effect.none()
  }
}

fn save_node(model: Model) -> Effect(Msg) {
  use universe <- selected_effect(model)
  let body = node_body(model.node_form)
  let handler = rsvp.expect_json(shared.node_decoder(), NodeSaved)
  let base = "/universes/" <> universe.id <> "/nodes"
  case model.editing_node {
    None -> rsvp.post(base, body, handler)
    Some(id) -> rsvp.put(base <> "/" <> id, body, handler)
  }
}

fn delete_node(model: Model, id: String) -> Effect(Msg) {
  use universe <- selected_effect(model)
  rsvp.delete(
    "/universes/" <> universe.id <> "/nodes/" <> id,
    json.null(),
    rsvp.expect_text(NodeDeleteResolved),
  )
}

fn reload_nodes(model: Model) -> Effect(Msg) {
  use universe <- selected_effect(model)
  load_nodes(universe.id)
}

fn descriptions_base(model: Model, node: String) -> Result(String, Nil) {
  case model.selected {
    Some(universe) ->
      Ok("/universes/" <> universe.id <> "/nodes/" <> node <> "/descriptions")
    None -> Error(Nil)
  }
}

fn load_descriptions(universe: String, node: String) -> Effect(Msg) {
  rsvp.get(
    "/universes/" <> universe <> "/nodes/" <> node <> "/descriptions",
    rsvp.expect_json(
      decode.list(shared.description_decoder()),
      DescriptionsLoaded,
    ),
  )
}

fn save_description(model: Model) -> Effect(Msg) {
  case model.editing_node {
    Some(node) ->
      case descriptions_base(model, node) {
        Ok(base) ->
          rsvp.post(
            base,
            description_body(model.description_form),
            rsvp.expect_json(shared.description_decoder(), DescriptionSaved),
          )
        Error(_) -> effect.none()
      }
    None -> effect.none()
  }
}

fn delete_description(model: Model, id: String) -> Effect(Msg) {
  case model.editing_node {
    Some(node) ->
      case descriptions_base(model, node) {
        Ok(base) ->
          rsvp.delete(
            base <> "/" <> id,
            json.null(),
            rsvp.expect_text(DescriptionDeleteResolved),
          )
        Error(_) -> effect.none()
      }
    None -> effect.none()
  }
}

fn set_fields(model: Model, fields: List(#(String, String))) -> Model {
  Model(..model, node_form: NodeForm(..model.node_form, fields:))
}

fn reload_descriptions(model: Model) -> Effect(Msg) {
  case model.selected, model.editing_node {
    Some(universe), Some(node) -> load_descriptions(universe.id, node)
    _, _ -> effect.none()
  }
}

fn load_edges(universe: String) -> Effect(Msg) {
  rsvp.get(
    "/universes/" <> universe <> "/edges",
    rsvp.expect_json(decode.list(shared.edge_decoder()), EdgesLoaded),
  )
}

fn save_edge(model: Model) -> Effect(Msg) {
  use universe <- selected_effect(model)
  rsvp.post(
    "/universes/" <> universe.id <> "/edges",
    edge_body(model.edge_form),
    rsvp.expect_json(shared.edge_decoder(), EdgeSaved),
  )
}

fn delete_edge(model: Model, id: String) -> Effect(Msg) {
  use universe <- selected_effect(model)
  rsvp.delete(
    "/universes/" <> universe.id <> "/edges/" <> id,
    json.null(),
    rsvp.expect_text(EdgeDeleteResolved),
  )
}

fn reload_edges(model: Model) -> Effect(Msg) {
  use universe <- selected_effect(model)
  load_edges(universe.id)
}

fn load_graph(universe: String, filter: GraphFilter) -> Effect(Msg) {
  rsvp.get(
    "/universes/" <> universe <> "/graph" <> graph_query(filter),
    rsvp.expect_json(shared.graph_decoder(), GraphLoaded),
  )
}

fn load_timeline(universe: String) -> Effect(Msg) {
  rsvp.get(
    "/universes/" <> universe <> "/timeline",
    rsvp.expect_json(shared.graph_decoder(), TimelineLoaded),
  )
}

fn render_graph(graph: shared.Graph) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    do_render_graph(json.to_string(shared.graph_to_json(graph)))
  })
}

@external(javascript, "./graph_ffi.mjs", "render")
fn do_render_graph(_data: String) -> Nil {
  Nil
}

fn select(model: Model, universe: shared.Universe) -> #(Model, Effect(Msg)) {
  #(
    Model(
      ..model,
      selected: Some(universe),
      nodes: Loading,
      node_form: empty_node_form,
      editing_node: None,
      descriptions: Loaded([]),
      description_form: "",
      edges: Loading,
      edge_form: empty_edge_form,
      graph: Loading,
      graph_filter: empty_graph_filter,
      timeline: Loading,
    ),
    effect.batch([
      load_nodes(universe.id),
      load_edges(universe.id),
      load_graph(universe.id, empty_graph_filter),
      load_timeline(universe.id),
    ]),
  )
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    MeLoaded(Ok(user)) -> #(
      Model(..model, auth: Loaded(Some(user))),
      case model.route {
        Home -> load_universes()
        UniverseView(_) -> effect.none()
      },
    )
    MeLoaded(Error(_)) -> #(Model(..model, auth: Loaded(None)), effect.none())
    RouteChanged(Home) -> #(
      Model(..model, route: Home, selected: None),
      case model.auth {
        Loaded(Some(_)) -> load_universes()
        _ -> effect.none()
      },
    )
    RouteChanged(UniverseView(id)) -> #(
      Model(..model, route: UniverseView(id)),
      load_universe(id),
    )
    UniverseFetched(Ok(universe)) -> select(model, universe)
    UniverseFetched(Error(_)) -> #(
      Model(..model, route: Home, selected: None),
      effect.none(),
    )
    LoginEmailChanged(email) -> #(
      Model(..model, login: LoginForm(..model.login, email:, failed: False)),
      effect.none(),
    )
    LoginPasswordChanged(password) -> #(
      Model(..model, login: LoginForm(..model.login, password:, failed: False)),
      effect.none(),
    )
    LoginSubmitted -> #(model, sign_in(model))
    SignedIn(Ok(user)) -> #(
      Model(..model, auth: Loaded(Some(user)), login: empty_login),
      load_universes(),
    )
    SignedIn(Error(_)) -> #(
      Model(..model, login: LoginForm(..model.login, failed: True)),
      effect.none(),
    )
    LogoutClicked -> #(model, sign_out())
    SignedOut(_) -> #(
      Model(
        ..model,
        auth: Loaded(None),
        selected: None,
        route: Home,
        universes: Loading,
      ),
      modem.push("/", None, None),
    )
    UniversesLoaded(Ok(universes)) -> #(
      Model(..model, universes: Loaded(universes)),
      effect.none(),
    )
    UniversesLoaded(Error(_)) -> #(
      Model(..model, universes: Failed),
      effect.none(),
    )
    NameChanged(name) -> #(
      Model(..model, form: Form(..model.form, name:)),
      effect.none(),
    )
    DescriptionChanged(description) -> #(
      Model(..model, form: Form(..model.form, description:)),
      effect.none(),
    )
    Submitted -> #(model, save(model))
    Saved(Ok(_)) -> #(
      Model(..model, form: empty_form, editing: None),
      load_universes(),
    )
    Saved(Error(_)) -> #(model, effect.none())
    EditStarted(universe) -> #(
      Model(
        ..model,
        editing: Some(universe.id),
        form: Form(universe.name, universe.description),
      ),
      effect.none(),
    )
    EditCancelled -> #(
      Model(..model, editing: None, form: empty_form),
      effect.none(),
    )
    DeleteRequested(id) -> #(model, delete(id))
    DeleteResolved(_) -> #(model, load_universes())
    UniverseSelected(universe) -> select(model, universe)
    UniverseDeselected -> #(
      Model(
        ..model,
        selected: None,
        nodes: Loading,
        edges: Loading,
        graph: Loading,
        timeline: Loading,
      ),
      effect.none(),
    )
    NodesLoaded(Ok(nodes)) -> #(
      Model(..model, nodes: Loaded(nodes)),
      effect.none(),
    )
    NodesLoaded(Error(_)) -> #(Model(..model, nodes: Failed), effect.none())
    NodeNameChanged(name) -> #(
      Model(..model, node_form: NodeForm(..model.node_form, name:)),
      effect.none(),
    )
    NodeKindChanged(kind) -> #(
      Model(..model, node_form: NodeForm(..model.node_form, kind:)),
      effect.none(),
    )
    GenericKeyChanged(index, key) -> #(
      set_fields(
        model,
        update_at(model.node_form.fields, index, fn(f) { #(key, f.1) }),
      ),
      effect.none(),
    )
    GenericValueChanged(index, value) -> #(
      set_fields(
        model,
        update_at(model.node_form.fields, index, fn(f) { #(f.0, value) }),
      ),
      effect.none(),
    )
    GenericFieldAdded -> #(
      set_fields(model, list.append(model.node_form.fields, [#("", "")])),
      effect.none(),
    )
    GenericFieldRemoved(index) -> #(
      set_fields(
        model,
        list.index_fold(model.node_form.fields, [], fn(acc, f, i) {
          case i == index {
            True -> acc
            False -> list.append(acc, [f])
          }
        }),
      ),
      effect.none(),
    )
    NodeSubmitted -> #(model, save_node(model))
    NodeSaved(Ok(_)) -> #(
      Model(..model, node_form: empty_node_form, editing_node: None),
      reload_nodes(model),
    )
    NodeSaved(Error(_)) -> #(model, effect.none())
    NodeEditStarted(node) -> #(
      Model(
        ..model,
        editing_node: Some(node.id),
        node_form: node_to_form(node),
        descriptions: Loading,
        description_form: "",
      ),
      case model.selected {
        Some(universe) -> load_descriptions(universe.id, node.id)
        None -> effect.none()
      },
    )
    NodeEditCancelled -> #(
      Model(
        ..model,
        editing_node: None,
        node_form: empty_node_form,
        descriptions: Loaded([]),
        description_form: "",
      ),
      effect.none(),
    )
    NodeDeleteRequested(id) -> #(model, delete_node(model, id))
    NodeDeleteResolved(_) -> #(model, reload_nodes(model))
    DescriptionsLoaded(Ok(descriptions)) -> #(
      Model(..model, descriptions: Loaded(descriptions)),
      effect.none(),
    )
    DescriptionsLoaded(Error(_)) -> #(
      Model(..model, descriptions: Failed),
      effect.none(),
    )
    DescriptionBodyChanged(description_form) -> #(
      Model(..model, description_form:),
      effect.none(),
    )
    DescriptionSubmitted ->
      case model.description_form {
        "" -> #(model, effect.none())
        _ -> #(model, save_description(model))
      }
    DescriptionSaved(Ok(_)) -> #(
      Model(..model, description_form: ""),
      reload_descriptions(model),
    )
    DescriptionSaved(Error(_)) -> #(model, effect.none())
    DescriptionDeleteRequested(id) -> #(model, delete_description(model, id))
    DescriptionDeleteResolved(_) -> #(model, reload_descriptions(model))
    EdgesLoaded(Ok(edges)) -> #(
      Model(..model, edges: Loaded(edges)),
      effect.none(),
    )
    EdgesLoaded(Error(_)) -> #(Model(..model, edges: Failed), effect.none())
    EdgeRelationshipChanged(relationship) -> #(
      Model(..model, edge_form: EdgeForm(..model.edge_form, relationship:)),
      effect.none(),
    )
    EdgeFromSelected(from) -> #(
      Model(..model, edge_form: EdgeForm(..model.edge_form, from:)),
      effect.none(),
    )
    EdgeToSelected(to) -> #(
      Model(..model, edge_form: EdgeForm(..model.edge_form, to:)),
      effect.none(),
    )
    EdgeSubmitted ->
      case edge_submittable(model.edge_form) {
        True -> #(model, save_edge(model))
        False -> #(model, effect.none())
      }
    EdgeSaved(Ok(_)) -> #(
      Model(..model, edge_form: empty_edge_form),
      reload_edges(model),
    )
    EdgeSaved(Error(_)) -> #(model, effect.none())
    EdgeDeleteRequested(id) -> #(model, delete_edge(model, id))
    EdgeDeleteResolved(_) -> #(model, reload_edges(model))
    GraphLoaded(Ok(graph)) -> #(
      Model(..model, graph: Loaded(graph)),
      render_graph(graph),
    )
    GraphLoaded(Error(_)) -> #(Model(..model, graph: Failed), effect.none())
    GraphFromChanged(from) -> #(
      Model(..model, graph_filter: GraphFilter(..model.graph_filter, from:)),
      effect.none(),
    )
    GraphRelationshipChanged(relationship) -> #(
      Model(
        ..model,
        graph_filter: GraphFilter(..model.graph_filter, relationship:),
      ),
      effect.none(),
    )
    GraphToChanged(to) -> #(
      Model(..model, graph_filter: GraphFilter(..model.graph_filter, to:)),
      effect.none(),
    )
    GraphFieldChanged(field) -> #(
      Model(..model, graph_filter: GraphFilter(..model.graph_filter, field:)),
      effect.none(),
    )
    GraphValueChanged(value) -> #(
      Model(..model, graph_filter: GraphFilter(..model.graph_filter, value:)),
      effect.none(),
    )
    GraphFilterApplied ->
      case model.selected {
        Some(universe) -> #(
          Model(..model, graph: Loading),
          load_graph(universe.id, model.graph_filter),
        )
        None -> #(model, effect.none())
      }
    GraphFilterCleared ->
      case model.selected {
        Some(universe) -> #(
          Model(..model, graph: Loading, graph_filter: empty_graph_filter),
          load_graph(universe.id, empty_graph_filter),
        )
        None -> #(
          Model(..model, graph_filter: empty_graph_filter),
          effect.none(),
        )
      }
    TimelineLoaded(Ok(timeline)) -> #(
      Model(..model, timeline: Loaded(timeline)),
      effect.none(),
    )
    TimelineLoaded(Error(_)) -> #(
      Model(..model, timeline: Failed),
      effect.none(),
    )
  }
}
