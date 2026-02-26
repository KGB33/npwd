import context.{type Context}
import gleam/dynamic/decode
import gleam/list
import gleam/result
import shared/character
import sql
import wisp.{type Request}

pub fn handle_save(ctx: Context, req: Request) {
  use json <- wisp.require_json(req)

  case decode.run(json, character.character_decoder()) {
    Ok(chara) -> {
      case sql.insert_character(ctx.db, chara.name) {
        Ok(_) -> wisp.created()
        Error(_) -> wisp.internal_server_error()
      }
    }
    Error(e) -> {
      echo e
      // TODO: Add real logging
      wisp.bad_request("Decode Failed")
    }
  }
}

pub fn handle_list(ctx: Context, req: Request) {
  todo
}

pub fn handle_update(ctx: Context, req: Request, id: String) {
  todo
}

pub fn handle_delete(ctx: Context, req: Request, id: String) {
  todo
}
