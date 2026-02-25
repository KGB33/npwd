import context.{type Context}
import gleam/json
import gleam/list
import gleam/result
import lustre/attribute
import lustre/element
import lustre/element/html
import shared/character
import sql
import wisp

pub fn serve(ctx: Context) {
  let assert Ok(chars) =
    sql.list_characters(ctx.db)
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
