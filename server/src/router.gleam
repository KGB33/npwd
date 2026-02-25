import context.{type Context}
import gleam/http
import handlers/characters
import handlers/index
import wisp.{type Request, type Response}

pub fn handle_request(req: Request, mk_context: fn() -> Context) {
  let ctx = mk_context()
  use req <- middleware(req, ctx)

  case req.method, wisp.path_segments(req) {
    http.Get, _ -> index.serve(ctx)
    http.Post, ["api", "characters"] -> characters.handle_save(ctx, req)
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
