import components/character/model.{type Model}
import components/character/update.{type Msg}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.styles([#("display", "flex"), #("gap", "1em")])], [
    html.button(
      [
        event.on_click(update.Delete(model.c.id)),
        attribute.disabled(model.io_wait),
      ],
      [
        html.text(case model.io_wait {
          True -> "..."
          False -> "🗑️"
        }),
      ],
    ),
    html.span([attribute.style("flex", "1")], [
      html.text(model.c.name),
    ]),
  ])
}
