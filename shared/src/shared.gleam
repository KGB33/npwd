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

pub fn node_decoder() -> Decoder(Node) {
  use id <- decode.field("id", decode.string)
  use universe <- decode.field("universe", decode.string)
  use name <- decode.field("name", decode.string)
  use description <- decode.field("description", decode.string)
  use kind <- decode.field("kind", decode.string)
  case kind {
    "Person" -> {
      use dob <- decode.field("dob", date_decoder())
      use gender <- decode.field("gender", decode.string)
      decode.success(Node(id, universe, Person(dob, gender), name, description))
    }
    "Place" -> decode.success(Node(id, universe, Place, name, description))
    "Event" -> {
      use when <- decode.field("when", date_decoder())
      decode.success(Node(id, universe, Event(when), name, description))
    }
    "Generic" -> {
      use fields <- decode.field(
        "fields",
        decode.dict(decode.string, field_value_decoder()),
      )
      decode.success(Node(id, universe, Generic(fields), name, description))
    }
    other ->
      decode.failure(
        Node(id, universe, Place, name, description),
        "kind " <> other,
      )
  }
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
