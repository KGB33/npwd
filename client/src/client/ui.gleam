import client/model.{type Msg}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub fn status(text: String) -> Element(Msg) {
  html.p(
    [attribute.class("status"), attribute.attribute("data-test-id", "status")],
    [element.text(text)],
  )
}
