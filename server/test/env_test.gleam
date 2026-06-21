import gleam/dict
import gleam/list
import server/env

fn getter(vars: List(#(String, String))) -> fn(String) -> Result(String, Nil) {
  let d = dict.from_list(vars)
  fn(name) { dict.get(d, name) }
}

fn all() -> List(#(String, String)) {
  [
    #("SURREAL_HOST", "127.0.0.1"),
    #("SURREAL_PORT", "8000"),
    #("SURREAL_NAMESPACE", "npwd"),
    #("SURREAL_DATABASE", "npwd"),
    #("SURREAL_USER", "root"),
    #("SURREAL_PASSWORD", "root"),
    #("SECRET_KEY_BASE", "dev-secret"),
    #("PORT", "3000"),
  ]
}

pub fn load_with_all_vars_succeeds_test() {
  let assert Ok(e) = env.load(getter(all()))
  assert e.config.host == "127.0.0.1"
  assert e.config.port == 8000
  assert e.config.namespace == "npwd"
  assert e.config.user == "root"
  assert e.secret_key_base == "dev-secret"
  assert e.port == 3000
}

pub fn missing_var_reports_it_test() {
  let without = list.filter(all(), fn(p) { p.0 != "SECRET_KEY_BASE" })
  assert env.load(getter(without)) == Error("SECRET_KEY_BASE is required")
}

pub fn non_integer_surreal_port_is_error_test() {
  let bad =
    list.map(all(), fn(p) {
      case p.0 {
        "SURREAL_PORT" -> #(p.0, "abc")
        _ -> p
      }
    })
  assert env.load(getter(bad)) == Error("SURREAL_PORT must be an integer")
}

pub fn empty_var_is_treated_as_missing_test() {
  let blank =
    list.map(all(), fn(p) {
      case p.0 {
        "SECRET_KEY_BASE" -> #(p.0, "")
        _ -> p
      }
    })
  assert env.load(getter(blank)) == Error("SECRET_KEY_BASE is required")
}
