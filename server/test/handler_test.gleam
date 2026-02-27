import context
import gleam/erlang/process
import gleam/http
import gleam/json
import pog
import router
import shared/character
import sql
import wisp
import wisp/simulate
import youid/uuid

fn create_test_context() {
  let name = process.new_name("db-pool")
  let assert Ok(actor) =
    pog.default_config(name)
    |> pog.host("localhost")
    |> pog.database("test")
    |> pog.user("kgb33")
    |> pog.pool_size(15)
    |> pog.start

  let assert Ok(priv_dir) = wisp.priv_directory("server")
  let static_dir = priv_dir <> "/static"
  context.Context(db: actor.data, static_dir: static_dir)
}

pub fn save_character_test() {
  let test_name = "A Test Name"
  let payload =
    json.object([
      #("name", json.string(test_name)),
      #("id", json.string(uuid.to_string(uuid.nil))),
    ])
  let response =
    simulate.browser_request(http.Post, "/api/character")
    |> simulate.json_body(payload)
    |> router.handle_request(create_test_context)

  assert response.status == 201
  let assert Ok(resp_chara) =
    response
    |> simulate.read_body()
    |> json.parse(character.character_decoder())
  assert resp_chara.name == test_name

  let ctx = create_test_context()
  let assert Ok(characters) = sql.get_characters_by_id(ctx.db, resp_chara.id)
  assert characters.count == 1
  assert characters.rows == [sql.GetCharactersByIdRow(resp_chara.id, test_name)]
}
