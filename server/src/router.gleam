import context.{type Context}
import gleam/http
import glotel/span
import glotel/span_kind
import handlers/characters
import handlers/entries
import handlers/index
import wisp.{type Request, type Response}

pub fn handle_request(req: Request, mk_context: fn() -> Context) {
  let ctx = mk_context()
  use req <- middleware(req, ctx)

  case req.method, wisp.path_segments(req) {
    http.Get, ["api", "characters"] -> characters.handle_list(ctx, req)
    // CRUD
    http.Post, ["api", "character"] -> characters.handle_save(ctx, req)
    http.Patch, ["api", "character", id] ->
      characters.handle_update(ctx, req, id)
    http.Delete, ["api", "character", id] ->
      characters.handle_delete(ctx, req, id)
    // Entries
    http.Get, ["api", "character", id, "entries"] ->
      entries.handle_list(ctx, req, id)
    http.Post, ["api", "entry"] -> entries.handle_save(ctx, req)
    http.Delete, ["api", "entry", id] -> entries.handle_delete(ctx, req, id)
    http.Get, _ -> index.serve(ctx)
    _, _ -> wisp.not_found()
  }
}

fn middleware(
  req: Request,
  ctx: Context,
  next: fn(Request) -> Response,
) -> Response {
  let route = http.method_to_string(req.method) <> " " <> req.path
  use span_ctx <- span.new_of_kind(span_kind.Server, route, [
    #("http.method", http.method_to_string(req.method)),
    #("http.route", req.path),
  ])
  let _propagated = span.extract_values(req.headers)
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  let resp = wisp.rescue_crashes(fn() {
    use req <- wisp.handle_head(req)
    use <- wisp.serve_static(req, under: "/static", from: ctx.static_dir)
    next(req)
  })
  case resp.status >= 500 {
    True -> span.set_error(span_ctx)
    False -> Nil
  }
  resp
}
