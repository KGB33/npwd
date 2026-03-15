import context.{type Context}
import gleam/http
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
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use <- wisp.serve_static(req, under: "/static", from: ctx.static_dir)

  next(req)
}
