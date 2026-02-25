import context.{type Context}
import gleam/dynamic/decode
import gleam/list
import gleam/result
import shared/character
import sql
import wisp.{type Request}

pub fn handle_save(ctx: Context, req: Request) {
  use json <- wisp.require_json(req)

  case decode.run(json, decode.list(character.character_decoder())) {
    Ok(chars) -> {
      case
        {
          chars
          |> list.map(fn(c) { c.name })
          |> list.map(sql.insert_character(ctx.db, _))
          |> result.all
        }
      {
        Ok(_) -> wisp.ok()
        Error(_) -> wisp.internal_server_error()
      }
    }
    Error(_) -> wisp.bad_request("Decode Failed")
  }
}
