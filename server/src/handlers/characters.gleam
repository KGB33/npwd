import context.{type Context}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import pog
import shared/character
import sql
import wisp.{type Request}

pub fn handle_save(ctx: Context, req: Request) {
  use json <- wisp.require_json(req)

  case decode.run(json, character.character_decoder()) {
    Ok(chara) -> {
      case sql.insert_character(ctx.db, chara.name) {
        Ok(pog.Returned(_, [sql.InsertCharacterRow(id, name)])) ->
          character.Character(id, name)
          |> character.character_to_json()
          |> json.to_string()
          |> wisp.json_response(201)
        _ -> wisp.internal_server_error()
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
