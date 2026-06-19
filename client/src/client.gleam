import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import rsvp

pub type Status {
  Checking
  Connected
  Unreachable
}

pub type Model {
  Model(status: Status)
}

pub type Msg {
  ServerChecked(Result(String, rsvp.Error(String)))
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub fn init(_args) -> #(Model, Effect(Msg)) {
  #(Model(status: Checking), check_server())
}

fn check_server() -> Effect(Msg) {
  rsvp.get("/health", rsvp.expect_text(ServerChecked))
}

pub fn update(_model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ServerChecked(Ok(_)) -> #(Model(status: Connected), effect.none())
    ServerChecked(Error(_)) -> #(Model(status: Unreachable), effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [element.text("NPWD")]),
    html.p([attribute.attribute("data-test-id", "status")], [
      element.text(status_label(model.status)),
    ]),
  ])
}

fn status_label(status: Status) -> String {
  case status {
    Checking -> "Checking server…"
    Connected -> "Connected"
    Unreachable -> "Server unreachable"
  }
}
