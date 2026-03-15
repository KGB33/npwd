import context.{type Context}
import db
import db/character as character_db
import gleam/dynamic/decode
import gleam/json
import gleam/string
import glogg/logger
import handlers/common.{require_id}
import shared/character
import wisp.{type Request}

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
      logger.warning(ctx.logger, "JSON decode failed", [
        logger.string("error", string.inspect(e)),
      ])
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
      logger.error(ctx.logger, "Failed to list characters", [
        logger.string("error", string.inspect(e)),
      ])
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
    Error(e) -> {
      logger.warning(ctx.logger, "JSON decode failed on update", [
        logger.string("error", string.inspect(e)),
      ])
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
      logger.error(ctx.logger, "Failed to delete character", [
        logger.string("error", string.inspect(e)),
      ])
      wisp.internal_server_error()
    }
  }
}
