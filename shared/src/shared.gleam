import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

pub type FieldValue {
  StringValue(String)
  IntValue(Int)
  FloatValue(Float)
  BoolValue(Bool)
}

pub type Universe {
  Universe(id: String, name: String, description: String, owner: String)
}

pub type User {
  User(id: String, email: String, admin: Bool)
}

pub type Node {
  Node(
    id: String,
    universe: String,
    name: String,
    kind: String,
    fields: Dict(String, FieldValue),
  )
}

pub type Description {
  Description(id: String, node: String, position: Int, body: String)
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

pub fn fields_to_json(fields: Dict(String, FieldValue)) -> Json {
  json.dict(fields, fn(k) { k }, field_value_to_json)
}

fn fields_decoder() -> Decoder(Dict(String, FieldValue)) {
  decode.dict(decode.string, field_value_decoder())
}

pub fn universe_to_json(u: Universe) -> Json {
  json.object([
    #("id", json.string(u.id)),
    #("name", json.string(u.name)),
    #("description", json.string(u.description)),
    #("owner", json.string(u.owner)),
  ])
}

pub fn universe_decoder() -> Decoder(Universe) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use description <- decode.field("description", decode.string)
  use owner <- decode.optional_field("owner", "", decode.string)
  decode.success(Universe(id, name, description, owner))
}

pub fn user_to_json(u: User) -> Json {
  json.object([
    #("id", json.string(u.id)),
    #("email", json.string(u.email)),
    #("admin", json.bool(u.admin)),
  ])
}

pub fn user_decoder() -> Decoder(User) {
  use id <- decode.field("id", decode.string)
  use email <- decode.field("email", decode.string)
  use admin <- decode.optional_field("admin", False, decode.bool)
  decode.success(User(id, email, admin))
}

pub fn node_to_json(n: Node) -> Json {
  json.object([
    #("id", json.string(n.id)),
    #("universe", json.string(n.universe)),
    #("name", json.string(n.name)),
    #("kind", json.string(n.kind)),
    #("fields", fields_to_json(n.fields)),
  ])
}

pub fn node_decoder() -> Decoder(Node) {
  use id <- decode.field("id", decode.string)
  use universe <- decode.field("universe", decode.string)
  use name <- decode.field("name", decode.string)
  use kind <- decode.field("kind", decode.string)
  use fields <- decode.optional_field("fields", dict.new(), fields_decoder())
  decode.success(Node(id, universe, name, kind, fields))
}

pub fn description_to_json(d: Description) -> Json {
  json.object([
    #("id", json.string(d.id)),
    #("node", json.string(d.node)),
    #("position", json.int(d.position)),
    #("body", json.string(d.body)),
  ])
}

pub fn description_decoder() -> Decoder(Description) {
  use id <- decode.field("id", decode.string)
  use node <- decode.field("node", decode.string)
  use position <- decode.field("position", decode.int)
  use body <- decode.field("body", decode.string)
  decode.success(Description(id, node, position, body))
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
