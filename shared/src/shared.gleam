import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list

pub type Date {
  Date(year: Int, month: Int, day: Int)
}

pub type FieldValue {
  StringValue(String)
  IntValue(Int)
  FloatValue(Float)
  BoolValue(Bool)
}

pub type NodeKind {
  Person(dob: Date, gender: String)
  Place
  Event(when: Date)
  Generic(fields: Dict(String, FieldValue))
}

pub type Universe {
  Universe(id: String, name: String, description: String)
}

pub type Node {
  Node(
    id: String,
    universe: String,
    kind: NodeKind,
    name: String,
    description: String,
  )
}

pub type Edge {
  Edge(
    id: String,
    universe: String,
    relationship: String,
    from: String,
    to: String,
  )
}

pub type Graph {
  Graph(nodes: List(Node), edges: List(Edge))
}

pub fn date_to_json(d: Date) -> Json {
  json.object([
    #("year", json.int(d.year)),
    #("month", json.int(d.month)),
    #("day", json.int(d.day)),
  ])
}

pub fn date_decoder() -> Decoder(Date) {
  use year <- decode.field("year", decode.int)
  use month <- decode.field("month", decode.int)
  use day <- decode.field("day", decode.int)
  decode.success(Date(year, month, day))
}

pub fn field_value_to_json(v: FieldValue) -> Json {
  case v {
    StringValue(s) -> json.string(s)
    IntValue(i) -> json.int(i)
    FloatValue(f) -> json.float(f)
    BoolValue(b) -> json.bool(b)
  }
}

pub fn field_value_decoder() -> Decoder(FieldValue) {
  decode.one_of(decode.string |> decode.map(StringValue), [
    decode.bool |> decode.map(BoolValue),
    decode.int |> decode.map(IntValue),
    decode.float |> decode.map(FloatValue),
  ])
}

pub fn universe_to_json(u: Universe) -> Json {
  json.object([
    #("id", json.string(u.id)),
    #("name", json.string(u.name)),
    #("description", json.string(u.description)),
  ])
}

pub fn universe_decoder() -> Decoder(Universe) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use description <- decode.field("description", decode.string)
  decode.success(Universe(id, name, description))
}

pub fn node_to_json(n: Node) -> Json {
  let base = [
    #("id", json.string(n.id)),
    #("universe", json.string(n.universe)),
    #("name", json.string(n.name)),
    #("description", json.string(n.description)),
  ]
  json.object(list.append(base, kind_fields(n.kind)))
}

fn kind_fields(kind: NodeKind) -> List(#(String, Json)) {
  case kind {
    Person(dob, gender) -> [
      #("kind", json.string("Person")),
      #("dob", date_to_json(dob)),
      #("gender", json.string(gender)),
    ]
    Place -> [#("kind", json.string("Place"))]
    Event(when) -> [
      #("kind", json.string("Event")),
      #("when", date_to_json(when)),
    ]
    Generic(fields) -> [
      #("kind", json.string("Generic")),
      #("fields", json.dict(fields, fn(k) { k }, field_value_to_json)),
    ]
  }
}

pub fn node_content_to_json(
  universe: String,
  name: String,
  description: String,
  kind: NodeKind,
) -> Json {
  json.object([
    #("universe", json.string(universe)),
    #("name", json.string(name)),
    #("description", json.string(description)),
    ..kind_fields(kind)
  ])
}

pub fn node_kind_decoder() -> Decoder(NodeKind) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "Person" -> {
      use dob <- decode.field("dob", date_decoder())
      use gender <- decode.field("gender", decode.string)
      decode.success(Person(dob, gender))
    }
    "Place" -> decode.success(Place)
    "Event" -> {
      use when <- decode.field("when", date_decoder())
      decode.success(Event(when))
    }
    "Generic" -> {
      use fields <- decode.field(
        "fields",
        decode.dict(decode.string, field_value_decoder()),
      )
      decode.success(Generic(fields))
    }
    other -> decode.failure(Place, "kind " <> other)
  }
}

pub fn node_decoder() -> Decoder(Node) {
  use id <- decode.field("id", decode.string)
  use universe <- decode.field("universe", decode.string)
  use name <- decode.field("name", decode.string)
  use description <- decode.field("description", decode.string)
  use kind <- decode.then(node_kind_decoder())
  decode.success(Node(id, universe, kind, name, description))
}

pub fn graph_to_json(g: Graph) -> Json {
  json.object([
    #("nodes", json.array(g.nodes, node_to_json)),
    #("edges", json.array(g.edges, edge_to_json)),
  ])
}

pub fn graph_decoder() -> Decoder(Graph) {
  use nodes <- decode.field("nodes", decode.list(node_decoder()))
  use edges <- decode.field("edges", decode.list(edge_decoder()))
  decode.success(Graph(nodes, edges))
}

pub fn edge_to_json(e: Edge) -> Json {
  json.object([
    #("id", json.string(e.id)),
    #("universe", json.string(e.universe)),
    #("relationship", json.string(e.relationship)),
    #("from", json.string(e.from)),
    #("to", json.string(e.to)),
  ])
}

pub fn edge_decoder() -> Decoder(Edge) {
  use id <- decode.field("id", decode.string)
  use universe <- decode.field("universe", decode.string)
  use relationship <- decode.field("relationship", decode.string)
  use from <- decode.field("from", decode.string)
  use to <- decode.field("to", decode.string)
  decode.success(Edge(id, universe, relationship, from, to))
}
