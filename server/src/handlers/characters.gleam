import context.{type Context}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import pog
import shared/character
import sql
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

pub fn handle_list(ctx: Context, _req: Request) {
  case sql.list_characters(ctx.db) {
    Ok(pog.Returned(_, characters)) -> {
      characters
      |> list.map(fn(row) { character.Character(id: row.id, name: row.name) })
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
      case sql.update_character(ctx.db, id, c.name) {
        Ok(pog.Returned(1, [chara])) -> {
          character.Character(id: chara.id, name: chara.name)
          |> character.character_to_json
          |> json.to_string
          |> wisp.json_response(200)
        }
        Ok(_) -> wisp.not_found()
        Error(_) -> {
          wisp.internal_server_error()
        }
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

  case sql.delete_character(ctx.db, uuid) {
    Ok(pog.Returned(1, [_])) -> wisp.ok()
    Ok(pog.Returned(0, [])) -> wisp.not_found()
    Ok(shouldnt_happen) -> {
      echo shouldnt_happen
      // Only one character should exist per uuid
      wisp.internal_server_error()
    }
    Error(err) -> {
      echo err
      wisp.internal_server_error()
    }
  }
}
