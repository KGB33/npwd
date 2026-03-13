import components/character/model
import components/character/update.{type Msg, update}
import components/character/view.{view}
import lustre
import lustre/element.{type Element}

const component_name = "character"

pub fn register() -> Result(Nil, lustre.Error) {
  let component = lustre.simple(model.init, update, view)
  lustre.register(component, component_name)
}

pub fn element() -> Element(Msg) {
  element.element(component_name, [], [])
}
