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
    shared.Universe("u1", "Middle Earth", "Tolkien's world", "user:tolkien"),
  )
}

pub fn user_round_trip_test() {
  round_trip(
    shared.user_to_json,
    shared.user_decoder(),
    shared.User("user:1", "frodo@shire.test", True),
  )
}

pub fn edge_round_trip_test() {
  round_trip(
    shared.edge_to_json,
    shared.edge_decoder(),
    shared.Edge("e1", "u1", "was_at", "n1", "n2"),
  )
}

pub fn graph_round_trip_test() {
  round_trip(
    shared.graph_to_json,
    shared.graph_decoder(),
    shared.Graph(
      [
        shared.Node("n1", "u1", "Shire", "Place", dict.new()),
        shared.Node(
          "n2",
          "u1",
          "Frodo",
          "Person",
          dict.from_list([#("gender", shared.StringValue("male"))]),
        ),
      ],
      [shared.Edge("e1", "u1", "lives_in", "n2", "n1")],
    ),
  )
}

pub fn node_round_trip_test() {
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
    shared.Node("n4", "u1", "Sting", "Generic", fields),
  )
}

pub fn placeless_node_round_trip_test() {
  round_trip(
    shared.node_to_json,
    shared.node_decoder(),
    shared.Node("n2", "u1", "Shire", "", dict.new()),
  )
}

pub fn description_round_trip_test() {
  round_trip(
    shared.description_to_json,
    shared.description_decoder(),
    shared.Description("d1", "node:1", 2, "The Ring is destroyed."),
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
