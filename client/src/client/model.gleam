import gleam/dict
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import gleam/string
import rsvp
import shared

pub type Remote(a) {
  Loading
  Loaded(a)
  Failed
}

pub type Form {
  Form(name: String, description: String)
}

pub type KindForm {
  PersonForm(year: String, month: String, day: String, gender: String)
  PlaceForm
  EventForm(year: String, month: String, day: String)
  GenericForm(fields: List(#(String, String)))
}

pub type NodeForm {
  NodeForm(name: String, description: String, kind: KindForm)
}

pub type EdgeForm {
  EdgeForm(relationship: String, from: String, to: String)
}

pub type GraphFilter {
  GraphFilter(kind: String, relationship: String, field: String, value: String)
}

pub type Model {
  Model(
    universes: Remote(List(shared.Universe)),
    form: Form,
    editing: Option(String),
    selected: Option(shared.Universe),
    nodes: Remote(List(shared.Node)),
    node_form: NodeForm,
    editing_node: Option(String),
    edges: Remote(List(shared.Edge)),
    edge_form: EdgeForm,
    graph: Remote(shared.Graph),
    graph_filter: GraphFilter,
    timeline: Remote(shared.Graph),
  )
}

pub type Msg {
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
  NodeDescriptionChanged(String)
  KindSelected(String)
  YearChanged(String)
  MonthChanged(String)
  DayChanged(String)
  GenderChanged(String)
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
  EdgesLoaded(Result(List(shared.Edge), rsvp.Error(String)))
  EdgeRelationshipChanged(String)
  EdgeFromSelected(String)
  EdgeToSelected(String)
  EdgeSubmitted
  EdgeSaved(Result(shared.Edge, rsvp.Error(String)))
  EdgeDeleteRequested(String)
  EdgeDeleteResolved(Result(String, rsvp.Error(String)))
  GraphLoaded(Result(shared.Graph, rsvp.Error(String)))
  GraphKindChanged(String)
  GraphRelationshipChanged(String)
  GraphFieldChanged(String)
  GraphValueChanged(String)
  GraphFilterApplied
  TimelineLoaded(Result(shared.Graph, rsvp.Error(String)))
}

pub const empty_form = Form(name: "", description: "")

pub const empty_node_form = NodeForm(name: "", description: "", kind: PlaceForm)

pub const empty_edge_form = EdgeForm(relationship: "", from: "", to: "")

pub const empty_graph_filter = GraphFilter(
  kind: "",
  relationship: "",
  field: "",
  value: "",
)

pub fn graph_query(filter: GraphFilter) -> String {
  let pairs =
    [
      #("kind", filter.kind),
      #("relationship", filter.relationship),
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
    #("description", json.string(form.description)),
    ..kind_fields(form.kind)
  ])
}

fn kind_fields(kind: KindForm) -> List(#(String, Json)) {
  case kind {
    PlaceForm -> [#("kind", json.string("Place"))]
    PersonForm(year, month, day, gender) -> [
      #("kind", json.string("Person")),
      #("dob", date_json(year, month, day)),
      #("gender", json.string(gender)),
    ]
    EventForm(year, month, day) -> [
      #("kind", json.string("Event")),
      #("when", date_json(year, month, day)),
    ]
    GenericForm(fields) -> [
      #("kind", json.string("Generic")),
      #(
        "fields",
        json.object(
          fields
          |> list.filter(fn(f) { f.0 != "" })
          |> list.map(fn(f) { #(f.0, json.string(f.1)) }),
        ),
      ),
    ]
  }
}

fn date_json(year: String, month: String, day: String) -> Json {
  json.object([
    #("year", json.int(parse_int(year))),
    #("month", json.int(parse_int(month))),
    #("day", json.int(parse_int(day))),
  ])
}

fn parse_int(s: String) -> Int {
  case int.parse(s) {
    Ok(n) -> n
    Error(_) -> 0
  }
}

pub fn default_kind(name: String) -> KindForm {
  case name {
    "Person" -> PersonForm("", "", "", "")
    "Event" -> EventForm("", "", "")
    "Generic" -> GenericForm([#("", "")])
    _ -> PlaceForm
  }
}

pub fn node_to_form(node: shared.Node) -> NodeForm {
  NodeForm(node.name, node.description, kind_to_form(node.kind))
}

fn kind_to_form(kind: shared.NodeKind) -> KindForm {
  case kind {
    shared.Person(dob, gender) ->
      PersonForm(
        int.to_string(dob.year),
        int.to_string(dob.month),
        int.to_string(dob.day),
        gender,
      )
    shared.Place -> PlaceForm
    shared.Event(when) ->
      EventForm(
        int.to_string(when.year),
        int.to_string(when.month),
        int.to_string(when.day),
      )
    shared.Generic(fields) ->
      GenericForm(
        fields
        |> dict.to_list
        |> list.map(fn(f) { #(f.0, field_value_to_string(f.1)) }),
      )
  }
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

pub fn set_date(
  model: Model,
  year: Option(String),
  month: Option(String),
  day: Option(String),
) -> Model {
  let pick = fn(new, old) { option.unwrap(new, old) }
  case model.node_form.kind {
    PersonForm(y, m, d, gender) ->
      set_kind(
        model,
        PersonForm(pick(year, y), pick(month, m), pick(day, d), gender),
      )
    EventForm(y, m, d) ->
      set_kind(model, EventForm(pick(year, y), pick(month, m), pick(day, d)))
    _ -> model
  }
}

pub fn set_kind(model: Model, kind: KindForm) -> Model {
  Model(..model, node_form: NodeForm(..model.node_form, kind:))
}

pub fn update_at(items: List(a), index: Int, f: fn(a) -> a) -> List(a) {
  list.index_map(items, fn(item, i) {
    case i == index {
      True -> f(item)
      False -> item
    }
  })
}

pub fn kind_name(kind: KindForm) -> String {
  case kind {
    PersonForm(..) -> "Person"
    PlaceForm -> "Place"
    EventForm(..) -> "Event"
    GenericForm(..) -> "Generic"
  }
}

pub fn kind_label(kind: shared.NodeKind) -> String {
  case kind {
    shared.Person(..) -> "Person"
    shared.Place -> "Place"
    shared.Event(..) -> "Event"
    shared.Generic(..) -> "Generic"
  }
}

pub fn event_when(kind: shared.NodeKind) -> String {
  case kind {
    shared.Event(when) ->
      int.to_string(when.year)
      <> "-"
      <> int.to_string(when.month)
      <> "-"
      <> int.to_string(when.day)
    _ -> ""
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

pub fn kind_options() -> List(String) {
  ["Person", "Place", "Event", "Generic"]
}

pub fn relationship_options(edges: Remote(List(shared.Edge))) -> List(String) {
  case edges {
    Loaded(list) -> distinct(list.map(list, fn(e) { e.relationship }))
    _ -> []
  }
}

pub fn gender_options(nodes: Remote(List(shared.Node))) -> List(String) {
  loaded_strings(nodes, fn(node) {
    case node.kind {
      shared.Person(_, gender) -> [gender]
      _ -> []
    }
  })
}

pub fn field_key_options(nodes: Remote(List(shared.Node))) -> List(String) {
  loaded_strings(nodes, fn(node) {
    case node.kind {
      shared.Generic(fields) -> dict.keys(fields)
      _ -> []
    }
  })
}

pub fn field_value_options(nodes: Remote(List(shared.Node))) -> List(String) {
  loaded_strings(nodes, fn(node) {
    case node.kind {
      shared.Generic(fields) ->
        dict.values(fields) |> list.map(field_value_to_string)
      _ -> []
    }
  })
}

fn loaded_strings(
  nodes: Remote(List(shared.Node)),
  pick: fn(shared.Node) -> List(String),
) -> List(String) {
  case nodes {
    Loaded(list) -> distinct(list.flat_map(list, pick))
    _ -> []
  }
}

fn distinct(items: List(String)) -> List(String) {
  items
  |> list.filter(fn(s) { s != "" })
  |> list.unique
  |> list.sort(string.compare)
}
