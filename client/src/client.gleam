import gleam/dict
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import shared

pub type Remote(a) {
  Loading
  Loaded(a)
  Failed
}

pub type Form {
  Form(name: String, description: String)
}

pub type KindForm {
  PersonForm(year: String, month: String, day: String, gender: String)
  PlaceForm
  EventForm(year: String, month: String, day: String)
  GenericForm(fields: List(#(String, String)))
}

pub type NodeForm {
  NodeForm(name: String, description: String, kind: KindForm)
}

pub type Model {
  Model(
    universes: Remote(List(shared.Universe)),
    form: Form,
    editing: Option(String),
    selected: Option(shared.Universe),
    nodes: Remote(List(shared.Node)),
    node_form: NodeForm,
    editing_node: Option(String),
  )
}

pub type Msg {
  UniversesLoaded(Result(List(shared.Universe), rsvp.Error(String)))
  NameChanged(String)
  DescriptionChanged(String)
  Submitted
  Saved(Result(shared.Universe, rsvp.Error(String)))
  EditStarted(shared.Universe)
  EditCancelled
  DeleteRequested(String)
  DeleteResolved(Result(String, rsvp.Error(String)))
  UniverseSelected(shared.Universe)
  UniverseDeselected
  NodesLoaded(Result(List(shared.Node), rsvp.Error(String)))
  NodeNameChanged(String)
  NodeDescriptionChanged(String)
  KindSelected(String)
  YearChanged(String)
  MonthChanged(String)
  DayChanged(String)
  GenderChanged(String)
  GenericKeyChanged(Int, String)
  GenericValueChanged(Int, String)
  GenericFieldAdded
  GenericFieldRemoved(Int)
  NodeSubmitted
  NodeSaved(Result(shared.Node, rsvp.Error(String)))
  NodeEditStarted(shared.Node)
  NodeEditCancelled
  NodeDeleteRequested(String)
  NodeDeleteResolved(Result(String, rsvp.Error(String)))
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub fn init(_args) -> #(Model, Effect(Msg)) {
  #(
    Model(
      universes: Loading,
      form: empty_form,
      editing: None,
      selected: None,
      nodes: Loading,
      node_form: empty_node_form,
      editing_node: None,
    ),
    load_universes(),
  )
}

const empty_form = Form(name: "", description: "")

const empty_node_form = NodeForm(name: "", description: "", kind: PlaceForm)

fn load_universes() -> Effect(Msg) {
  rsvp.get(
    "/universes",
    rsvp.expect_json(decode.list(shared.universe_decoder()), UniversesLoaded),
  )
}

fn load_nodes(universe: String) -> Effect(Msg) {
  rsvp.get(
    "/universes/" <> universe <> "/nodes",
    rsvp.expect_json(decode.list(shared.node_decoder()), NodesLoaded),
  )
}

fn save(model: Model) -> Effect(Msg) {
  let body =
    json.object([
      #("name", json.string(model.form.name)),
      #("description", json.string(model.form.description)),
    ])
  let handler = rsvp.expect_json(shared.universe_decoder(), Saved)
  case model.editing {
    None -> rsvp.post("/universes", body, handler)
    Some(id) -> rsvp.put("/universes/" <> id, body, handler)
  }
}

fn delete(id: String) -> Effect(Msg) {
  rsvp.delete(
    "/universes/" <> id,
    json.null(),
    rsvp.expect_text(DeleteResolved),
  )
}

fn save_node(model: Model) -> Effect(Msg) {
  case model.selected {
    None -> effect.none()
    Some(universe) -> {
      let body = node_body(model.node_form)
      let handler = rsvp.expect_json(shared.node_decoder(), NodeSaved)
      let base = "/universes/" <> universe.id <> "/nodes"
      case model.editing_node {
        None -> rsvp.post(base, body, handler)
        Some(id) -> rsvp.put(base <> "/" <> id, body, handler)
      }
    }
  }
}

fn delete_node(model: Model, id: String) -> Effect(Msg) {
  case model.selected {
    None -> effect.none()
    Some(universe) ->
      rsvp.delete(
        "/universes/" <> universe.id <> "/nodes/" <> id,
        json.null(),
        rsvp.expect_text(NodeDeleteResolved),
      )
  }
}

pub fn node_body(form: NodeForm) -> Json {
  json.object([
    #("name", json.string(form.name)),
    #("description", json.string(form.description)),
    ..kind_fields(form.kind)
  ])
}

fn kind_fields(kind: KindForm) -> List(#(String, Json)) {
  case kind {
    PlaceForm -> [#("kind", json.string("Place"))]
    PersonForm(year, month, day, gender) -> [
      #("kind", json.string("Person")),
      #("dob", date_json(year, month, day)),
      #("gender", json.string(gender)),
    ]
    EventForm(year, month, day) -> [
      #("kind", json.string("Event")),
      #("when", date_json(year, month, day)),
    ]
    GenericForm(fields) -> [
      #("kind", json.string("Generic")),
      #(
        "fields",
        json.object(
          fields
          |> list.filter(fn(f) { f.0 != "" })
          |> list.map(fn(f) { #(f.0, json.string(f.1)) }),
        ),
      ),
    ]
  }
}

fn date_json(year: String, month: String, day: String) -> Json {
  json.object([
    #("year", json.int(parse_int(year))),
    #("month", json.int(parse_int(month))),
    #("day", json.int(parse_int(day))),
  ])
}

fn parse_int(s: String) -> Int {
  case int.parse(s) {
    Ok(n) -> n
    Error(_) -> 0
  }
}

fn default_kind(name: String) -> KindForm {
  case name {
    "Person" -> PersonForm("", "", "", "")
    "Event" -> EventForm("", "", "")
    "Generic" -> GenericForm([#("", "")])
    _ -> PlaceForm
  }
}

fn node_to_form(node: shared.Node) -> NodeForm {
  NodeForm(node.name, node.description, kind_to_form(node.kind))
}

fn kind_to_form(kind: shared.NodeKind) -> KindForm {
  case kind {
    shared.Person(dob, gender) ->
      PersonForm(
        int.to_string(dob.year),
        int.to_string(dob.month),
        int.to_string(dob.day),
        gender,
      )
    shared.Place -> PlaceForm
    shared.Event(when) ->
      EventForm(
        int.to_string(when.year),
        int.to_string(when.month),
        int.to_string(when.day),
      )
    shared.Generic(fields) ->
      GenericForm(
        fields
        |> dict.to_list
        |> list.map(fn(f) { #(f.0, field_value_to_string(f.1)) }),
      )
  }
}

fn field_value_to_string(v: shared.FieldValue) -> String {
  case v {
    shared.StringValue(s) -> s
    shared.IntValue(i) -> int.to_string(i)
    shared.FloatValue(f) -> float.to_string(f)
    shared.BoolValue(b) ->
      case b {
        True -> "true"
        False -> "false"
      }
  }
}

fn set_date(
  model: Model,
  year: Option(String),
  month: Option(String),
  day: Option(String),
) -> Model {
  let pick = fn(new, old) { option.unwrap(new, old) }
  case model.node_form.kind {
    PersonForm(y, m, d, gender) ->
      set_kind(
        model,
        PersonForm(pick(year, y), pick(month, m), pick(day, d), gender),
      )
    EventForm(y, m, d) ->
      set_kind(model, EventForm(pick(year, y), pick(month, m), pick(day, d)))
    _ -> model
  }
}

fn update_at(items: List(a), index: Int, f: fn(a) -> a) -> List(a) {
  list.index_map(items, fn(item, i) {
    case i == index {
      True -> f(item)
      False -> item
    }
  })
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UniversesLoaded(Ok(universes)) -> #(
      Model(..model, universes: Loaded(universes)),
      effect.none(),
    )
    UniversesLoaded(Error(_)) -> #(
      Model(..model, universes: Failed),
      effect.none(),
    )
    NameChanged(name) -> #(
      Model(..model, form: Form(..model.form, name:)),
      effect.none(),
    )
    DescriptionChanged(description) -> #(
      Model(..model, form: Form(..model.form, description:)),
      effect.none(),
    )
    Submitted -> #(model, save(model))
    Saved(Ok(_)) -> #(
      Model(..model, form: empty_form, editing: None),
      load_universes(),
    )
    Saved(Error(_)) -> #(model, effect.none())
    EditStarted(universe) -> #(
      Model(
        ..model,
        editing: Some(universe.id),
        form: Form(universe.name, universe.description),
      ),
      effect.none(),
    )
    EditCancelled -> #(
      Model(..model, editing: None, form: empty_form),
      effect.none(),
    )
    DeleteRequested(id) -> #(model, delete(id))
    DeleteResolved(_) -> #(model, load_universes())
    UniverseSelected(universe) -> #(
      Model(
        ..model,
        selected: Some(universe),
        nodes: Loading,
        node_form: empty_node_form,
        editing_node: None,
      ),
      load_nodes(universe.id),
    )
    UniverseDeselected -> #(
      Model(..model, selected: None, nodes: Loading),
      effect.none(),
    )
    NodesLoaded(Ok(nodes)) -> #(
      Model(..model, nodes: Loaded(nodes)),
      effect.none(),
    )
    NodesLoaded(Error(_)) -> #(Model(..model, nodes: Failed), effect.none())
    NodeNameChanged(name) -> #(
      Model(..model, node_form: NodeForm(..model.node_form, name:)),
      effect.none(),
    )
    NodeDescriptionChanged(description) -> #(
      Model(..model, node_form: NodeForm(..model.node_form, description:)),
      effect.none(),
    )
    KindSelected(name) -> #(
      Model(
        ..model,
        node_form: NodeForm(..model.node_form, kind: default_kind(name)),
      ),
      effect.none(),
    )
    YearChanged(year) -> #(
      set_date(model, Some(year), None, None),
      effect.none(),
    )
    MonthChanged(month) -> #(
      set_date(model, None, Some(month), None),
      effect.none(),
    )
    DayChanged(day) -> #(set_date(model, None, None, Some(day)), effect.none())
    GenderChanged(gender) ->
      case model.node_form.kind {
        PersonForm(y, m, d, _) -> #(
          set_kind(model, PersonForm(y, m, d, gender)),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    GenericKeyChanged(index, key) ->
      case model.node_form.kind {
        GenericForm(fields) -> #(
          set_kind(
            model,
            GenericForm(update_at(fields, index, fn(f) { #(key, f.1) })),
          ),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    GenericValueChanged(index, value) ->
      case model.node_form.kind {
        GenericForm(fields) -> #(
          set_kind(
            model,
            GenericForm(update_at(fields, index, fn(f) { #(f.0, value) })),
          ),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    GenericFieldAdded ->
      case model.node_form.kind {
        GenericForm(fields) -> #(
          set_kind(model, GenericForm(list.append(fields, [#("", "")]))),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    GenericFieldRemoved(index) ->
      case model.node_form.kind {
        GenericForm(fields) -> #(
          set_kind(
            model,
            GenericForm(
              list.index_fold(fields, [], fn(acc, f, i) {
                case i == index {
                  True -> acc
                  False -> list.append(acc, [f])
                }
              }),
            ),
          ),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    NodeSubmitted -> #(model, save_node(model))
    NodeSaved(Ok(_)) ->
      case model.selected {
        Some(universe) -> #(
          Model(..model, node_form: empty_node_form, editing_node: None),
          load_nodes(universe.id),
        )
        None -> #(model, effect.none())
      }
    NodeSaved(Error(_)) -> #(model, effect.none())
    NodeEditStarted(node) -> #(
      Model(..model, editing_node: Some(node.id), node_form: node_to_form(node)),
      effect.none(),
    )
    NodeEditCancelled -> #(
      Model(..model, editing_node: None, node_form: empty_node_form),
      effect.none(),
    )
    NodeDeleteRequested(id) -> #(model, delete_node(model, id))
    NodeDeleteResolved(_) ->
      case model.selected {
        Some(universe) -> #(model, load_nodes(universe.id))
        None -> #(model, effect.none())
      }
  }
}

fn set_kind(model: Model, kind: KindForm) -> Model {
  Model(..model, node_form: NodeForm(..model.node_form, kind:))
}

pub fn view(model: Model) -> Element(Msg) {
  case model.selected {
    None ->
      html.div([], [
        html.h1([], [element.text("NPWD")]),
        form_view(model),
        universes_view(model.universes),
      ])
    Some(universe) ->
      html.div([], [
        html.h1([], [element.text(universe.name)]),
        html.button(
          [
            attribute.attribute("data-test-id", "back"),
            event.on_click(UniverseDeselected),
          ],
          [element.text("Back")],
        ),
        node_form_view(model),
        nodes_view(model.nodes),
      ])
  }
}

fn form_view(model: Model) -> Element(Msg) {
  let editing = model.editing != None
  let submit_label = case editing {
    True -> "Save"
    False -> "Create"
  }
  html.div([attribute.attribute("data-test-id", "form")], [
    html.input([
      attribute.attribute("data-test-id", "name-input"),
      attribute.placeholder("Name"),
      attribute.value(model.form.name),
      event.on_input(NameChanged),
    ]),
    html.input([
      attribute.attribute("data-test-id", "description-input"),
      attribute.placeholder("Description"),
      attribute.value(model.form.description),
      event.on_input(DescriptionChanged),
    ]),
    html.button(
      [attribute.attribute("data-test-id", "submit"), event.on_click(Submitted)],
      [element.text(submit_label)],
    ),
    ..case editing {
      True -> [
        html.button([event.on_click(EditCancelled)], [element.text("Cancel")]),
      ]
      False -> []
    }
  ])
}

fn universes_view(universes: Remote(List(shared.Universe))) -> Element(Msg) {
  case universes {
    Loading -> status("Loading universes…")
    Failed -> status("Could not load universes")
    Loaded([]) -> status("No universes yet")
    Loaded(list) ->
      html.ul(
        [attribute.attribute("data-test-id", "universe-list")],
        list.map(list, universe_row),
      )
  }
}

fn universe_row(universe: shared.Universe) -> Element(Msg) {
  html.li([attribute.attribute("data-test-id", "universe")], [
    html.span([attribute.attribute("data-test-id", "universe-name")], [
      element.text(universe.name),
    ]),
    html.button(
      [
        attribute.attribute("data-test-id", "open"),
        event.on_click(UniverseSelected(universe)),
      ],
      [element.text("Open")],
    ),
    html.button([event.on_click(EditStarted(universe))], [element.text("Edit")]),
    html.button([event.on_click(DeleteRequested(universe.id))], [
      element.text("Delete"),
    ]),
  ])
}

fn node_form_view(model: Model) -> Element(Msg) {
  let editing = model.editing_node != None
  let submit_label = case editing {
    True -> "Save"
    False -> "Create"
  }
  html.div([attribute.attribute("data-test-id", "node-form")], [
    html.input([
      attribute.attribute("data-test-id", "node-name-input"),
      attribute.placeholder("Name"),
      attribute.value(model.node_form.name),
      event.on_input(NodeNameChanged),
    ]),
    html.input([
      attribute.attribute("data-test-id", "node-description-input"),
      attribute.placeholder("Description"),
      attribute.value(model.node_form.description),
      event.on_input(NodeDescriptionChanged),
    ]),
    kind_select(model.node_form.kind),
    kind_fields_view(model.node_form.kind),
    html.button(
      [
        attribute.attribute("data-test-id", "node-submit"),
        event.on_click(NodeSubmitted),
      ],
      [element.text(submit_label)],
    ),
    ..case editing {
      True -> [
        html.button([event.on_click(NodeEditCancelled)], [
          element.text("Cancel"),
        ]),
      ]
      False -> []
    }
  ])
}

fn kind_select(kind: KindForm) -> Element(Msg) {
  let current = kind_name(kind)
  html.select(
    [
      attribute.attribute("data-test-id", "kind-select"),
      event.on_change(KindSelected),
    ],
    list.map(["Person", "Place", "Event", "Generic"], fn(name) {
      html.option(
        [attribute.value(name), attribute.selected(name == current)],
        name,
      )
    }),
  )
}

fn kind_name(kind: KindForm) -> String {
  case kind {
    PersonForm(..) -> "Person"
    PlaceForm -> "Place"
    EventForm(..) -> "Event"
    GenericForm(..) -> "Generic"
  }
}

fn kind_fields_view(kind: KindForm) -> Element(Msg) {
  case kind {
    PlaceForm -> html.div([], [])
    PersonForm(year, month, day, gender) ->
      html.div([], [
        date_inputs(year, month, day),
        html.input([
          attribute.attribute("data-test-id", "gender-input"),
          attribute.placeholder("Gender"),
          attribute.value(gender),
          event.on_input(GenderChanged),
        ]),
      ])
    EventForm(year, month, day) -> date_inputs(year, month, day)
    GenericForm(fields) ->
      html.div(
        [attribute.attribute("data-test-id", "generic-fields")],
        list.append(list.index_map(fields, generic_row), [
          html.button(
            [
              attribute.attribute("data-test-id", "generic-add"),
              event.on_click(GenericFieldAdded),
            ],
            [element.text("Add field")],
          ),
        ]),
      )
  }
}

fn date_inputs(year: String, month: String, day: String) -> Element(Msg) {
  html.div([], [
    html.input([
      attribute.attribute("data-test-id", "year-input"),
      attribute.placeholder("Year"),
      attribute.value(year),
      event.on_input(YearChanged),
    ]),
    html.input([
      attribute.attribute("data-test-id", "month-input"),
      attribute.placeholder("Month"),
      attribute.value(month),
      event.on_input(MonthChanged),
    ]),
    html.input([
      attribute.attribute("data-test-id", "day-input"),
      attribute.placeholder("Day"),
      attribute.value(day),
      event.on_input(DayChanged),
    ]),
  ])
}

fn generic_row(field: #(String, String), index: Int) -> Element(Msg) {
  html.div([attribute.attribute("data-test-id", "generic-row")], [
    html.input([
      attribute.attribute("data-test-id", "generic-key"),
      attribute.placeholder("Key"),
      attribute.value(field.0),
      event.on_input(GenericKeyChanged(index, _)),
    ]),
    html.input([
      attribute.attribute("data-test-id", "generic-value"),
      attribute.placeholder("Value"),
      attribute.value(field.1),
      event.on_input(GenericValueChanged(index, _)),
    ]),
    html.button([event.on_click(GenericFieldRemoved(index))], [
      element.text("Remove"),
    ]),
  ])
}

fn nodes_view(nodes: Remote(List(shared.Node))) -> Element(Msg) {
  case nodes {
    Loading -> status("Loading nodes…")
    Failed -> status("Could not load nodes")
    Loaded([]) -> status("No nodes yet")
    Loaded(list) ->
      html.ul(
        [attribute.attribute("data-test-id", "node-list")],
        list.map(list, node_row),
      )
  }
}

fn node_row(node: shared.Node) -> Element(Msg) {
  html.li([attribute.attribute("data-test-id", "node")], [
    html.span([attribute.attribute("data-test-id", "node-name")], [
      element.text(node.name),
    ]),
    html.span([attribute.attribute("data-test-id", "node-kind")], [
      element.text(kind_label(node.kind)),
    ]),
    html.button([event.on_click(NodeEditStarted(node))], [element.text("Edit")]),
    html.button([event.on_click(NodeDeleteRequested(node.id))], [
      element.text("Delete"),
    ]),
  ])
}

fn kind_label(kind: shared.NodeKind) -> String {
  case kind {
    shared.Person(..) -> "Person"
    shared.Place -> "Place"
    shared.Event(..) -> "Event"
    shared.Generic(..) -> "Generic"
  }
}

fn status(text: String) -> Element(Msg) {
  html.p([attribute.attribute("data-test-id", "status")], [element.text(text)])
}
