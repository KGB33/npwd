import client
import gleeunit
import lustre/dev/query
import lustre/dev/simulate
import rsvp

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn update_connected_test() {
  let #(model, _) =
    client.update(client.Model(client.Checking), client.ServerChecked(Ok("ok")))
  assert model.status == client.Connected
}

pub fn update_unreachable_test() {
  let #(model, _) =
    client.update(
      client.Model(client.Checking),
      client.ServerChecked(Error(rsvp.BadBody)),
    )
  assert model.status == client.Unreachable
}

fn shows_status(simulation, text) -> Bool {
  query.has(
    simulate.view(simulation),
    query.and(query.test_id("status"), query.text(text)),
  )
}

pub fn initial_view_is_checking_test() {
  let simulation =
    simulate.application(client.init, client.update, client.view)
    |> simulate.start(Nil)
  assert shows_status(simulation, "Checking server…")
}

pub fn view_connects_after_message_test() {
  let simulation =
    simulate.application(client.init, client.update, client.view)
    |> simulate.start(Nil)
    |> simulate.message(client.ServerChecked(Ok("ok")))
  assert shows_status(simulation, "Connected")
}

pub fn view_unreachable_after_error_test() {
  let simulation =
    simulate.application(client.init, client.update, client.view)
    |> simulate.start(Nil)
    |> simulate.message(client.ServerChecked(Error(rsvp.BadBody)))
  assert shows_status(simulation, "Server unreachable")
}
