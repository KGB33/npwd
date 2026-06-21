import gleam/dynamic/decode.{type Decoder}
import gleam/http.{Get, Post}
import gleam/result
import server/db
import server/passwords
import server/web
import shared
import wisp.{type Request, type Response}

const cookie = "session"

const max_age = 2_592_000

pub fn current_user(
  req: Request,
  config: db.Config,
) -> Result(shared.User, Nil) {
  use id <- result.try(wisp.get_cookie(req, cookie, wisp.Signed))
  db.get_user(config, id) |> result.replace_error(Nil)
}

pub fn require_user(
  req: Request,
  config: db.Config,
  handler: fn(shared.User) -> Response,
) -> Response {
  case current_user(req, config) {
    Ok(user) -> handler(user)
    Error(_) -> wisp.response(401)
  }
}

pub fn require_owner(
  req: Request,
  config: db.Config,
  universe: String,
  handler: fn(shared.User) -> Response,
) -> Response {
  use user <- require_user(req, config)
  case db.get_universe(config, universe) {
    Ok(u) if u.owner == user.id -> handler(user)
    Ok(_) -> wisp.response(403)
    Error(db.NotFound) -> wisp.not_found()
    Error(db.InvalidInput) -> wisp.bad_request("invalid id")
    Error(_) -> wisp.internal_server_error()
  }
}

pub fn handle(
  config: db.Config,
  req: Request,
  segments: List(String),
) -> Response {
  case segments {
    ["signin"] -> signin(config, req)
    ["signout"] -> signout(req)
    ["users"] -> create_user(config, req)
    _ -> wisp.not_found()
  }
}

pub fn me(config: db.Config, req: Request) -> Response {
  use <- wisp.require_method(req, Get)
  use user <- require_user(req, config)
  web.json(user, shared.user_to_json, 200)
}

type Input {
  Input(email: String, password: String, admin: Bool)
}

fn input_decoder() -> Decoder(Input) {
  use email <- decode.field("email", decode.string)
  use password <- decode.field("password", decode.string)
  use admin <- decode.optional_field("admin", False, decode.bool)
  decode.success(Input(email:, password:, admin:))
}

fn signin(config: db.Config, req: Request) -> Response {
  use <- wisp.require_method(req, Post)
  use body <- wisp.require_json(req)
  case decode.run(body, input_decoder()) {
    Ok(input) ->
      case db.find_credentials(config, input.email) {
        Ok(creds) ->
          case passwords.verify(input.password, creds.hash) {
            True ->
              web.json(creds.user, shared.user_to_json, 200)
              |> wisp.set_cookie(
                req,
                cookie,
                creds.user.id,
                wisp.Signed,
                max_age,
              )
            False -> wisp.response(401)
          }
        Error(_) -> wisp.response(401)
      }
    Error(_) -> wisp.bad_request("invalid credentials")
  }
}

fn signout(req: Request) -> Response {
  use <- wisp.require_method(req, Post)
  wisp.ok() |> wisp.set_cookie(req, cookie, "", wisp.Signed, 0)
}

fn create_user(config: db.Config, req: Request) -> Response {
  use <- wisp.require_method(req, Post)
  use _admin <- require_admin(req, config)
  use body <- wisp.require_json(req)
  case decode.run(body, input_decoder()) {
    Ok(input) ->
      case
        db.create_user(
          config,
          input.email,
          passwords.hash(input.password),
          input.admin,
        )
      {
        Ok(user) -> web.json(user, shared.user_to_json, 201)
        Error(e) -> wisp.response(create_user_status(e))
      }
    Error(_) -> wisp.bad_request("invalid user")
  }
}

fn require_admin(
  req: Request,
  config: db.Config,
  handler: fn(shared.User) -> Response,
) -> Response {
  use user <- require_user(req, config)
  case user.admin {
    True -> handler(user)
    False -> wisp.response(403)
  }
}

pub fn create_user_status(error: db.DbError) -> Int {
  case error {
    db.QueryError(_) -> 409
    _ -> 500
  }
}
