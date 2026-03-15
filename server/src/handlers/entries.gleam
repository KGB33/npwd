import context.{type Context}
import db
import db/entry as entry_db
import gleam/dynamic/decode
import gleam/json
import handlers/common.{require_id}
import shared/entry
import wisp.{type Request}

pub fn handle_list(ctx: Context, _req: Request, character_id: String) {
  use uuid <- require_id(character_id)

  case entry_db.list_by_character(ctx.db, uuid) {
    Ok(entries) -> {
      entries
      |> entry.entry_list_to_json
      |> json.to_string
      |> wisp.json_response(200)
    }
    Error(e) -> {
      echo e
      wisp.internal_server_error()
    }
  }
}

pub fn handle_save(ctx: Context, req: Request) {
  use json_body <- wisp.require_json(req)

  case decode.run(json_body, entry.new_entry_decoder()) {
    Ok(new_entry) -> {
      case new_entry.text {
        "" -> wisp.bad_request("Text cannot be empty")
        _ ->
          case entry_db.insert(ctx.db, new_entry.character_id, new_entry.text) {
            Ok(e) ->
              e
              |> entry.entry_to_json
              |> json.to_string
              |> wisp.json_response(201)
            Error(_) -> wisp.internal_server_error()
          }
      }
    }
    Error(e) -> {
      echo e
      wisp.bad_request("Decode Failed")
    }
  }
}

pub fn handle_delete(ctx: Context, _req: Request, id: String) {
  use uuid <- require_id(id)

  case entry_db.delete(ctx.db, uuid) {
    Ok(Nil) -> wisp.ok()
    Error(db.NotFound) -> wisp.not_found()
    Error(e) -> {
      echo e
      wisp.internal_server_error()
    }
  }
}
