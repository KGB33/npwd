import context.{type Context}
import db
import db/character as character_db
import gleam/dynamic/decode
import gleam/json
import shared/character
import wisp.{type Request}
import youid/uuid

pub fn require_id(
  id: String,
  next: fn(uuid.Uuid) -> wisp.Response,
) -> wisp.Response {
  case uuid.from_string(id) {
    Ok(uuid) -> next(uuid)
    Error(_) -> wisp.bad_request("Invalid UUID")
  }
}

pub fn handle_save(ctx: Context, req: Request) {
  use json <- wisp.require_json(req)

  case decode.run(json, character.character_decoder()) {
    Ok(chara) -> {
      case chara.name {
        "" -> wisp.bad_request("Name cannot be empty")
        _ ->
          case character_db.insert(ctx.db, chara.name) {
            Ok(c) ->
              c
              |> character.character_to_json()
              |> json.to_string()
              |> wisp.json_response(201)
            Error(_) -> wisp.internal_server_error()
          }
      }
    }
    Error(e) -> {
      echo e
      // TODO: Add real logging
      wisp.bad_request("Decode Failed")
    }
  }
}

pub fn handle_list(ctx: Context, _req: Request) {
  case character_db.list(ctx.db) {
    Ok(characters) -> {
      characters
      |> json.array(of: character.character_to_json)
      |> json.to_string
      |> wisp.json_response(200)
    }
    Error(e) -> {
      echo e
      // TODO: Add real logging
      wisp.internal_server_error()
    }
  }
}

pub fn handle_update(ctx: Context, req: Request, id: String) {
  use id <- require_id(id)
  use json <- wisp.require_json(req)

  // TODO: Create update DTO to allow partial updates
  case decode.run(json, character.character_decoder()) {
    Ok(c) -> {
      case character_db.update(ctx.db, id, c.name) {
        Ok(updated) -> {
          updated
          |> character.character_to_json
          |> json.to_string
          |> wisp.json_response(200)
        }
        Error(db.NotFound) -> wisp.not_found()
        Error(_) -> wisp.internal_server_error()
      }
    }
    Error(err) -> {
      echo err
      wisp.bad_request("Decode Failed")
    }
  }
}

pub fn handle_delete(ctx: Context, _req: Request, id: String) {
  use uuid <- require_id(id)

  case character_db.delete(ctx.db, uuid) {
    Ok(Nil) -> wisp.ok()
    Error(db.NotFound) -> wisp.not_found()
    Error(e) -> {
      echo e
      wisp.internal_server_error()
    }
  }
}
