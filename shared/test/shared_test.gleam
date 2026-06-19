import gleam/dict
import gleam/json
import gleam/list
import gleeunit
import shared

pub fn main() -> Nil {
  gleeunit.main()
}

fn round_trip(encode, decoder, value) {
  let json_string = value |> encode |> json.to_string
  assert json.parse(json_string, decoder) == Ok(value)
}

pub fn universe_round_trip_test() {
  round_trip(
    shared.universe_to_json,
    shared.universe_decoder(),
    shared.Universe("u1", "Middle Earth", "Tolkien's world"),
  )
}

pub fn edge_round_trip_test() {
  round_trip(
    shared.edge_to_json,
    shared.edge_decoder(),
    shared.Edge("e1", "u1", "was_at", "n1", "n2"),
  )
}

pub fn person_node_round_trip_test() {
  round_trip(
    shared.node_to_json,
    shared.node_decoder(),
    shared.Node(
      "n1",
      "u1",
      shared.Person(shared.Date(2890, 9, 22), "male"),
      "Frodo",
      "Ring-bearer",
    ),
  )
}

pub fn place_node_round_trip_test() {
  round_trip(
    shared.node_to_json,
    shared.node_decoder(),
    shared.Node("n2", "u1", shared.Place, "Shire", "Hobbit homeland"),
  )
}

pub fn event_node_round_trip_test() {
  round_trip(
    shared.node_to_json,
    shared.node_decoder(),
    shared.Node(
      "n3",
      "u1",
      shared.Event(shared.Date(3019, 3, 25)),
      "Fall of Sauron",
      "The Ring is destroyed",
    ),
  )
}

pub fn generic_node_round_trip_test() {
  let fields =
    dict.from_list([
      #("faction", shared.StringValue("fellowship")),
      #("age", shared.IntValue(50)),
      #("height", shared.FloatValue(1.06)),
      #("immortal", shared.BoolValue(False)),
    ])
  round_trip(
    shared.node_to_json,
    shared.node_decoder(),
    shared.Node("n4", "u1", shared.Generic(fields), "Sting", "A sword"),
  )
}

pub fn field_value_round_trip_test() {
  let cases = [
    shared.StringValue("x"),
    shared.IntValue(7),
    shared.FloatValue(3.5),
    shared.BoolValue(True),
  ]
  cases
  |> list.each(fn(v) {
    let json_string = v |> shared.field_value_to_json |> json.to_string
    assert json.parse(json_string, shared.field_value_decoder()) == Ok(v)
  })
}
