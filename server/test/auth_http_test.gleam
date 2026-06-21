import gleam/http
import gleam/json.{type Json}
import helpers
import server/db
import server/passwords
import server/router
import shared
import wisp/simulate

fn seed(
  config: db.Config,
  email: String,
  password: String,
  admin: Bool,
) -> shared.User {
  let assert Ok(user) =
    db.create_user(config, email, passwords.hash(password), admin)
  user
}

fn creds(email: String, password: String) -> Json {
  json.object([
    #("email", json.string(email)),
    #("password", json.string(password)),
  ])
}

pub fn signin_success_returns_user_test() {
  let config = helpers.fresh_db()
  let _ = seed(config, "frodo@shire.test", "ring", False)
  let response =
    simulate.request(http.Post, "/auth/signin")
    |> simulate.json_body(creds("frodo@shire.test", "ring"))
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(user) =
    json.parse(simulate.read_body(response), shared.user_decoder())
  assert user.email == "frodo@shire.test"
}

pub fn signin_wrong_password_is_401_test() {
  let config = helpers.fresh_db()
  let _ = seed(config, "frodo@shire.test", "ring", False)
  let response =
    simulate.request(http.Post, "/auth/signin")
    |> simulate.json_body(creds("frodo@shire.test", "nope"))
    |> router.handle_request(config, _)
  assert response.status == 401
}

pub fn signin_unknown_email_is_401_test() {
  let config = helpers.fresh_db()
  let response =
    simulate.request(http.Post, "/auth/signin")
    |> simulate.json_body(creds("nobody@shire.test", "ring"))
    |> router.handle_request(config, _)
  assert response.status == 401
}

pub fn me_without_session_is_401_test() {
  let config = helpers.fresh_db()
  let response =
    simulate.request(http.Get, "/me")
    |> router.handle_request(config, _)
  assert response.status == 401
}

pub fn signin_then_me_returns_user_test() {
  let config = helpers.fresh_db()
  let _ = seed(config, "sam@shire.test", "taters", False)
  let signin_req =
    simulate.request(http.Post, "/auth/signin")
    |> simulate.json_body(creds("sam@shire.test", "taters"))
  let signin_res = router.handle_request(config, signin_req)
  assert signin_res.status == 200

  let me_res =
    simulate.session(simulate.request(http.Get, "/me"), signin_req, signin_res)
    |> router.handle_request(config, _)
  assert me_res.status == 200
  let assert Ok(user) =
    json.parse(simulate.read_body(me_res), shared.user_decoder())
  assert user.email == "sam@shire.test"
}

pub fn signout_clears_session_test() {
  let config = helpers.fresh_db()
  let _ = seed(config, "sam@shire.test", "taters", False)
  let signin_req =
    simulate.request(http.Post, "/auth/signin")
    |> simulate.json_body(creds("sam@shire.test", "taters"))
  let signin_res = router.handle_request(config, signin_req)

  let signout_req =
    simulate.session(
      simulate.request(http.Post, "/auth/signout"),
      signin_req,
      signin_res,
    )
  let signout_res = router.handle_request(config, signout_req)
  assert signout_res.status == 200

  let me_res =
    simulate.session(
      simulate.request(http.Get, "/me"),
      signout_req,
      signout_res,
    )
    |> router.handle_request(config, _)
  assert me_res.status == 401
}

pub fn admin_can_invite_user_test() {
  let config = helpers.fresh_db()
  let admin = seed(config, "gandalf@white.test", "staff", True)
  let response =
    simulate.request(http.Post, "/auth/users")
    |> simulate.json_body(creds("pippin@shire.test", "fool"))
    |> helpers.auth(admin)
    |> router.handle_request(config, _)
  assert response.status == 201
  let assert Ok(user) =
    json.parse(simulate.read_body(response), shared.user_decoder())
  assert user.email == "pippin@shire.test"
  assert user.admin == False

  let signin =
    simulate.request(http.Post, "/auth/signin")
    |> simulate.json_body(creds("pippin@shire.test", "fool"))
    |> router.handle_request(config, _)
  assert signin.status == 200
}

pub fn non_admin_cannot_invite_test() {
  let config = helpers.fresh_db()
  let plain = seed(config, "merry@shire.test", "ale", False)
  let response =
    simulate.request(http.Post, "/auth/users")
    |> simulate.json_body(creds("pippin@shire.test", "fool"))
    |> helpers.auth(plain)
    |> router.handle_request(config, _)
  assert response.status == 403
}

pub fn invite_requires_auth_test() {
  let config = helpers.fresh_db()
  let response =
    simulate.request(http.Post, "/auth/users")
    |> simulate.json_body(creds("pippin@shire.test", "fool"))
    |> router.handle_request(config, _)
  assert response.status == 401
}

pub fn duplicate_email_is_409_test() {
  let config = helpers.fresh_db()
  let admin = seed(config, "gandalf@white.test", "staff", True)
  let _ = seed(config, "pippin@shire.test", "fool", False)
  let response =
    simulate.request(http.Post, "/auth/users")
    |> simulate.json_body(creds("pippin@shire.test", "again"))
    |> helpers.auth(admin)
    |> router.handle_request(config, _)
  assert response.status == 409
}
