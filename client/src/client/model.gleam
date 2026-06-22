import gleam/dict
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, Some}
import gleam/string
import gleam/uri
import rsvp
import shared

pub type Remote(a) {
  Loading
  Loaded(a)
  Failed
}

pub type Route {
  Home
  UniverseView(String)
}

pub type LoginForm {
  LoginForm(email: String, password: String, failed: Bool)
}

pub type Form {
  Form(name: String, description: String)
}

pub type NodeForm {
  NodeForm(name: String, kind: String, fields: List(#(String, String)))
}

pub type EdgeForm {
  EdgeForm(relationship: String, from: String, to: String)
}

pub type GraphFilter {
  GraphFilter(
    from: String,
    relationship: String,
    to: String,
    field: String,
    value: String,
  )
}

pub type Model {
  Model(
    auth: Remote(Option(shared.User)),
    login: LoginForm,
    route: Route,
    universes: Remote(List(shared.Universe)),
    form: Form,
    editing: Option(String),
    selected: Option(shared.Universe),
    nodes: Remote(List(shared.Node)),
    node_form: NodeForm,
    editing_node: Option(String),
    descriptions: Remote(List(shared.Description)),
    description_form: String,
    edges: Remote(List(shared.Edge)),
    edge_form: EdgeForm,
    graph: Remote(shared.Graph),
    graph_filter: GraphFilter,
    timeline: Remote(shared.Graph),
  )
}

pub type Msg {
  MeLoaded(Result(shared.User, rsvp.Error(String)))
  RouteChanged(Route)
  UniverseFetched(Result(shared.Universe, rsvp.Error(String)))
  LoginEmailChanged(String)
  LoginPasswordChanged(String)
  LoginSubmitted
  SignedIn(Result(shared.User, rsvp.Error(String)))
  LogoutClicked
  SignedOut(Result(String, rsvp.Error(String)))
  UniversesLoaded(Result(List(shared.Universe), rsvp.Error(String)))
  NameChanged(String)
  DescriptionChanged(String)
  Submitted
  Saved(Result(shared.Universe, rsvp.Error(String)))
  EditStarted(shared.Universe)
  EditCancelled
  DeleteRequested(String)
  DeleteResolved(Result(String, rsvp.Error(String)))
  UniverseSelected(shared.Universe)
  UniverseDeselected
  NodesLoaded(Result(List(shared.Node), rsvp.Error(String)))
  NodeNameChanged(String)
  NodeKindChanged(String)
  GenericKeyChanged(Int, String)
  GenericValueChanged(Int, String)
  GenericFieldAdded
  GenericFieldRemoved(Int)
  NodeSubmitted
  NodeSaved(Result(shared.Node, rsvp.Error(String)))
  NodeEditStarted(shared.Node)
  NodeEditCancelled
  NodeDeleteRequested(String)
  NodeDeleteResolved(Result(String, rsvp.Error(String)))
  DescriptionsLoaded(Result(List(shared.Description), rsvp.Error(String)))
  DescriptionBodyChanged(String)
  DescriptionSubmitted
  DescriptionSaved(Result(shared.Description, rsvp.Error(String)))
  DescriptionDeleteRequested(String)
  DescriptionDeleteResolved(Result(String, rsvp.Error(String)))
  EdgesLoaded(Result(List(shared.Edge), rsvp.Error(String)))
  EdgeRelationshipChanged(String)
  EdgeFromSelected(String)
  EdgeToSelected(String)
  EdgeSubmitted
  EdgeSaved(Result(shared.Edge, rsvp.Error(String)))
  EdgeDeleteRequested(String)
  EdgeDeleteResolved(Result(String, rsvp.Error(String)))
  GraphLoaded(Result(shared.Graph, rsvp.Error(String)))
  GraphFromChanged(String)
  GraphRelationshipChanged(String)
  GraphToChanged(String)
  GraphFieldChanged(String)
  GraphValueChanged(String)
  GraphFilterApplied
  GraphFilterCleared
  TimelineLoaded(Result(shared.Graph, rsvp.Error(String)))
}

pub const empty_login = LoginForm(email: "", password: "", failed: False)

pub const empty_form = Form(name: "", description: "")

pub fn route_from_path(path: String) -> Route {
  case uri.path_segments(path) {
    ["u", id] -> UniverseView(id)
    _ -> Home
  }
}

pub fn universe_path(id: String) -> String {
  "/u/" <> id
}

pub fn can_edit(model: Model) -> Bool {
  case model.auth, model.selected {
    Loaded(Some(user)), Some(universe) -> user.id == universe.owner
    _, _ -> False
  }
}

pub fn login_body(form: LoginForm) -> Json {
  json.object([
    #("email", json.string(form.email)),
    #("password", json.string(form.password)),
  ])
}

pub const empty_node_form = NodeForm(name: "", kind: "", fields: [])

pub const empty_edge_form = EdgeForm(relationship: "", from: "", to: "")

pub const empty_graph_filter = GraphFilter(
  from: "",
  relationship: "",
  to: "",
  field: "",
  value: "",
)

pub fn graph_query(filter: GraphFilter) -> String {
  let pairs =
    [
      #("from", filter.from),
      #("relationship", filter.relationship),
      #("to", filter.to),
      #("field", filter.field),
      #("value", filter.value),
    ]
    |> list.filter(fn(p) { p.1 != "" })
    |> list.map(fn(p) { p.0 <> "=" <> p.1 })
  case pairs {
    [] -> ""
    _ -> "?" <> string.join(pairs, "&")
  }
}

pub fn edge_submittable(form: EdgeForm) -> Bool {
  form.relationship != "" && form.from != "" && form.to != ""
}

pub fn edge_body(form: EdgeForm) -> Json {
  json.object([
    #("relationship", json.string(form.relationship)),
    #("from", json.string(form.from)),
    #("to", json.string(form.to)),
  ])
}

pub fn node_body(form: NodeForm) -> Json {
  json.object([
    #("name", json.string(form.name)),
    #("kind", json.string(form.kind)),
    #(
      "fields",
      json.object(
        form.fields
        |> list.filter(fn(f) { f.0 != "" })
        |> list.map(fn(f) { #(f.0, json.string(f.1)) }),
      ),
    ),
  ])
}

pub fn description_body(body: String) -> Json {
  json.object([#("body", json.string(body))])
}

pub fn node_to_form(node: shared.Node) -> NodeForm {
  NodeForm(
    node.name,
    node.kind,
    node.fields
      |> dict.to_list
      |> list.map(fn(f) { #(f.0, field_value_to_string(f.1)) }),
  )
}

fn field_value_to_string(v: shared.FieldValue) -> String {
  case v {
    shared.StringValue(s) -> s
    shared.IntValue(i) -> int.to_string(i)
    shared.FloatValue(f) -> float.to_string(f)
    shared.BoolValue(b) ->
      case b {
        True -> "true"
        False -> "false"
      }
  }
}

pub fn update_at(items: List(a), index: Int, f: fn(a) -> a) -> List(a) {
  list.index_map(items, fn(item, i) {
    case i == index {
      True -> f(item)
      False -> item
    }
  })
}

pub fn node_field(node: shared.Node, key: String) -> String {
  case dict.get(node.fields, key) {
    Ok(v) -> field_value_to_string(v)
    Error(_) -> ""
  }
}

pub fn node_name(nodes: Remote(List(shared.Node)), id: String) -> String {
  case nodes {
    Loaded(list) ->
      case list.find(list, fn(n) { n.id == id }) {
        Ok(n) -> n.name
        Error(_) -> id
      }
    _ -> id
  }
}

pub fn kind_suggestions(nodes: Remote(List(shared.Node))) -> List(String) {
  case nodes {
    Loaded(list) -> distinct(list.map(list, fn(n) { n.kind }))
    _ -> []
  }
}

pub fn relationship_options(edges: Remote(List(shared.Edge))) -> List(String) {
  case edges {
    Loaded(list) -> distinct(list.map(list, fn(e) { e.relationship }))
    _ -> []
  }
}

pub fn field_key_options(nodes: Remote(List(shared.Node))) -> List(String) {
  case nodes {
    Loaded(list) -> distinct(list.flat_map(list, fn(n) { dict.keys(n.fields) }))
    _ -> []
  }
}

type Row {
  Row(edge: shared.Edge, from: shared.Node, to: shared.Node)
}

fn graph_rows(model: Model) -> List(Row) {
  case model.nodes, model.edges {
    Loaded(ns), Loaded(es) -> {
      let lookup = dict.from_list(list.map(ns, fn(n) { #(n.id, n) }))
      list.filter_map(es, fn(e) {
        case dict.get(lookup, e.from), dict.get(lookup, e.to) {
          Ok(f), Ok(t) -> Ok(Row(e, f, t))
          _, _ -> Error(Nil)
        }
      })
    }
    _, _ -> []
  }
}

fn endpoint_matches(node: shared.Node, spec: String) -> Bool {
  spec == "" || node.name == spec || node.kind == spec
}

fn field_matches(node: shared.Node, field: String, value: String) -> Bool {
  node_field_value(node, field) == option.Some(value)
}

fn node_field_value(node: shared.Node, field: String) -> Option(String) {
  case dict.get(node.fields, field) {
    Ok(v) -> option.Some(field_value_to_string(v))
    Error(_) -> option.None
  }
}

fn node_field_keys(node: shared.Node) -> List(String) {
  dict.keys(node.fields)
}

fn row_matches(
  row: Row,
  from: String,
  rel: String,
  to: String,
  field: String,
  value: String,
) -> Bool {
  endpoint_matches(row.from, from)
  && { rel == "" || row.edge.relationship == rel }
  && endpoint_matches(row.to, to)
  && case field == "" || value == "" {
    True -> True
    False ->
      field_matches(row.from, field, value)
      || field_matches(row.to, field, value)
  }
}

fn candidate_nodes(model: Model) -> List(shared.Node) {
  let f = model.graph_filter
  case f.from != "" || f.relationship != "" || f.to != "" {
    True ->
      graph_rows(model)
      |> list.filter(fn(r) {
        endpoint_matches(r.from, f.from)
        && { f.relationship == "" || r.edge.relationship == f.relationship }
        && endpoint_matches(r.to, f.to)
      })
      |> list.flat_map(fn(r) { [r.from, r.to] })
    False ->
      case model.nodes {
        Loaded(ns) -> ns
        _ -> []
      }
  }
}

pub fn graph_from_options(model: Model) -> List(String) {
  let f = model.graph_filter
  graph_rows(model)
  |> list.filter(fn(r) {
    row_matches(r, "", f.relationship, f.to, f.field, f.value)
  })
  |> list.flat_map(fn(r) { [r.from.name, r.from.kind] })
  |> distinct
}

pub fn graph_to_options(model: Model) -> List(String) {
  let f = model.graph_filter
  graph_rows(model)
  |> list.filter(fn(r) {
    row_matches(r, f.from, f.relationship, "", f.field, f.value)
  })
  |> list.flat_map(fn(r) { [r.to.name, r.to.kind] })
  |> distinct
}

pub fn graph_relationship_options(model: Model) -> List(String) {
  let f = model.graph_filter
  graph_rows(model)
  |> list.filter(fn(r) { row_matches(r, f.from, "", f.to, f.field, f.value) })
  |> list.map(fn(r) { r.edge.relationship })
  |> distinct
}

pub fn graph_field_options(model: Model) -> List(String) {
  candidate_nodes(model) |> list.flat_map(node_field_keys) |> distinct
}

pub fn graph_value_options(model: Model) -> List(String) {
  case model.graph_filter.field {
    "" -> []
    field ->
      candidate_nodes(model)
      |> list.filter_map(fn(n) {
        option.to_result(node_field_value(n, field), Nil)
      })
      |> distinct
  }
}

fn distinct(items: List(String)) -> List(String) {
  items
  |> list.filter(fn(s) { s != "" })
  |> list.unique
  |> list.sort(string.compare)
}
