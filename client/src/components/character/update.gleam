import shared/character
import components/character/model.{type Model}
import gleam/http/response.{type Response}
import gleam/json
import lustre/effect.{type Effect}
import rsvp
import youid/uuid

pub type Msg {
  Create
  CreateResponse(Result(Response(String), rsvp.Error))
  Update
  UpdateResponse(Result(Response(String), rsvp.Error))
  Delete
  DeleteResponse(Result(Response(String), rsvp.Error))
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Create -> #(model, create_character(model))
    CreateResponse(_) -> todo
    Update -> todo
    UpdateResponse(_) -> #(model, update_character(model))
    Delete -> {
      #(model.init(Nil), delete_character(model.c.id))
    }
    DeleteResponse(Ok(_)) -> todo
    DeleteResponse(Error(_)) -> todo
  }
}

fn create_character(model: Model) -> Effect(Msg) {
  let url = "/api/character/"
  rsvp.post(
    url,
    character.character_to_json(model.c),
    rsvp.expect_ok_response(CreateResponse),
  )
}

fn update_character(model: Model) -> Effect(Msg) {
  let url = "/api/character/" <> uuid.to_string(model.c.id)
  rsvp.patch(
    url,
    character.character_to_json(model.c),
    rsvp.expect_ok_response(CreateResponse),
  )
}

fn delete_character(id: uuid.Uuid) -> Effect(Msg) {
  let url = "/api/character/" <> uuid.to_string(id)
  rsvp.delete(url, json.object([]), rsvp.expect_ok_response(DeleteResponse))
}
