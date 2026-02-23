import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import lustre/attribute
import lustre/element
import lustre/element/html
import mist
import pog
import sql
import wisp.{type Request, type Response}
import wisp/wisp_mist

import shared/character

fn setup_pog() {
  let name = process.new_name("db-pool")
  let assert Ok(actor) =
    pog.default_config(name)
    |> pog.host("localhost")
    |> pog.database("dev")
    |> pog.user("kgb33")
    |> pog.pool_size(15)
    |> pog.start

  actor.data
}

pub fn main() -> Nil {
  wisp.configure_logger()
  let secret_key = wisp.random_string(64)
  let db = setup_pog()

  let assert Ok(priv_dir) = wisp.priv_directory("server")
  let static_dir = priv_dir <> "/static"

  let assert Ok(_) =
    handle_request(db, static_dir, _)
    |> wisp_mist.handler(secret_key)
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}

fn app_middleware(
  req: Request,
  static_dir: String,
  next: fn(Request) -> Response,
) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use <- wisp.serve_static(req, under: "/static", from: static_dir)

  next(req)
}

fn handle_request(db: pog.Connection, static_dir: String, req: Request) {
  use req <- app_middleware(req, static_dir)

  case req.method, wisp.path_segments(req) {
    http.Get, _ -> serve_index(db)
    http.Post, ["api", "characters"] -> handle_save_characters(db, req)
    _, _ -> wisp.not_found()
  }
}

fn serve_index(db: pog.Connection) {
  let assert Ok(chars) =
    sql.list_characters(db)
    |> result.map(fn(returned) {
      returned.rows
      |> list.map(fn(row) { character.Character(row.id, row.name) })
    })

  let html =
    html.html([], [
      html.head([], [
        html.title([], "NPWD"),
        html.script(
          [attribute.type_("module"), attribute.src("/static/client.js")],
          "",
        ),
      ]),
      html.script(
        [attribute.type_("application/json"), attribute.id("model")],
        json.to_string(character.character_list_to_json(chars)),
      ),
      html.body([], [html.div([attribute.id("app")], [])]),
    ])

  html |> element.to_document_string |> wisp.html_response(200)
}

fn handle_save_characters(db: pog.Connection, req: Request) {
  use json <- wisp.require_json(req)

  case decode.run(json, decode.list(character.character_decoder())) {
    Ok(chars) -> {
      case
        {
          chars
          |> list.map(fn(c) { c.name })
          |> list.map(sql.insert_character(db, _))
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
