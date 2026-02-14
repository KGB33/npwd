import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import lustre/element
import lustre/element/html.{html}
import mist.{type Connection, type ResponseData}

pub fn main() -> Nil {
  let empty_body = mist.Bytes(bytes_tree.new())
  let not_found = response.set_body(response.new(404), empty_body)

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        ["greet", name] -> greet(name)
        _ -> not_found
      }
    }
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}

fn greet(name: String) -> Response(ResponseData) {
  let res = response.new(200)
  let html =
    html([], [
      html.head([], [html.title([], "Greetings!")]),
      html.body([], [html.h1([], [html.text("Hi " <> name <> "!")])]),
    ])

  response.set_body(
    res,
    html |> element.to_document_string |> bytes_tree.from_string |> mist.Bytes,
  )
}
