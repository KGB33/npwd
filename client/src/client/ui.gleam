import client/model.{type Msg}
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn status(text: String) -> Element(Msg) {
  html.p(
    [attribute.class("status"), attribute.attribute("data-test-id", "status")],
    [element.text(text)],
  )
}

pub fn suggest_input(
  test_id: String,
  placeholder: String,
  value: String,
  msg: fn(String) -> Msg,
  suggestions: List(String),
) -> Element(Msg) {
  let list_id = test_id <> "-options"
  element.fragment([
    html.input([
      attribute.attribute("data-test-id", test_id),
      attribute.attribute("list", list_id),
      attribute.placeholder(placeholder),
      attribute.value(value),
      event.on_input(msg),
    ]),
    html.datalist(
      [attribute.id(list_id)],
      list.map(suggestions, fn(s) { html.option([attribute.value(s)], "") }),
    ),
  ])
}
