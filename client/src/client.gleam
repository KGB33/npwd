import gleam/dict
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
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

pub type EdgeForm {
  EdgeForm(relationship: String, from: String, to: String)
}

pub type GraphFilter {
  GraphFilter(kind: String, relationship: String, field: String, value: String)
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
    edges: Remote(List(shared.Edge)),
    edge_form: EdgeForm,
    graph: Remote(shared.Graph),
    graph_filter: GraphFilter,
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
  EdgesLoaded(Result(List(shared.Edge), rsvp.Error(String)))
  EdgeRelationshipChanged(String)
  EdgeFromSelected(String)
  EdgeToSelected(String)
  EdgeSubmitted
  EdgeSaved(Result(shared.Edge, rsvp.Error(String)))
  EdgeDeleteRequested(String)
  EdgeDeleteResolved(Result(String, rsvp.Error(String)))
  GraphLoaded(Result(shared.Graph, rsvp.Error(String)))
  GraphKindChanged(String)
  GraphRelationshipChanged(String)
  GraphFieldChanged(String)
  GraphValueChanged(String)
  GraphFilterApplied
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
      edges: Loading,
      edge_form: empty_edge_form,
      graph: Loading,
      graph_filter: empty_graph_filter,
    ),
    load_universes(),
  )
}

const empty_form = Form(name: "", description: "")

const empty_node_form = NodeForm(name: "", description: "", kind: PlaceForm)

const empty_edge_form = EdgeForm(relationship: "", from: "", to: "")

const empty_graph_filter = GraphFilter(
  kind: "",
  relationship: "",
  field: "",
  value: "",
)

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

fn load_edges(universe: String) -> Effect(Msg) {
  rsvp.get(
    "/universes/" <> universe <> "/edges",
    rsvp.expect_json(decode.list(shared.edge_decoder()), EdgesLoaded),
  )
}

fn save_edge(model: Model) -> Effect(Msg) {
  case model.selected {
    None -> effect.none()
    Some(universe) ->
      rsvp.post(
        "/universes/" <> universe.id <> "/edges",
        edge_body(model.edge_form),
        rsvp.expect_json(shared.edge_decoder(), EdgeSaved),
      )
  }
}

fn delete_edge(model: Model, id: String) -> Effect(Msg) {
  case model.selected {
    None -> effect.none()
    Some(universe) ->
      rsvp.delete(
        "/universes/" <> universe.id <> "/edges/" <> id,
        json.null(),
        rsvp.expect_text(EdgeDeleteResolved),
      )
  }
}

fn load_graph(universe: String, filter: GraphFilter) -> Effect(Msg) {
  rsvp.get(
    "/universes/" <> universe <> "/graph" <> graph_query(filter),
    rsvp.expect_json(shared.graph_decoder(), GraphLoaded),
  )
}

pub fn graph_query(filter: GraphFilter) -> String {
  let pairs =
    [
      #("kind", filter.kind),
      #("relationship", filter.relationship),
      #("field", filter.field),
      #("value", filter.value),
    ]
    |> list.filter(fn(p) { p.1 != "" })
    |> list.map(fn(p) { p.0 <> "=" <> p.1 })
  case pairs {
    [] -> ""
    _ -> "?" <> string.join(pairs, "&")
  }
}

fn render_graph(graph: shared.Graph) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    do_render_graph(json.to_string(shared.graph_to_json(graph)))
  })
}

@external(javascript, "./graph_ffi.mjs", "render")
fn do_render_graph(_data: String) -> Nil {
  Nil
}

pub fn edge_body(form: EdgeForm) -> Json {
  json.object([
    #("relationship", json.string(form.relationship)),
    #("from", json.string(form.from)),
    #("to", json.string(form.to)),
  ])
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
        edges: Loading,
        edge_form: empty_edge_form,
        graph: Loading,
        graph_filter: empty_graph_filter,
      ),
      effect.batch([
        load_nodes(universe.id),
        load_edges(universe.id),
        load_graph(universe.id, empty_graph_filter),
      ]),
    )
    UniverseDeselected -> #(
      Model(..model, selected: None, nodes: Loading, edges: Loading, graph: Loading),
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
    EdgesLoaded(Ok(edges)) -> #(
      Model(..model, edges: Loaded(edges)),
      effect.none(),
    )
    EdgesLoaded(Error(_)) -> #(Model(..model, edges: Failed), effect.none())
    EdgeRelationshipChanged(relationship) -> #(
      Model(..model, edge_form: EdgeForm(..model.edge_form, relationship:)),
      effect.none(),
    )
    EdgeFromSelected(from) -> #(
      Model(..model, edge_form: EdgeForm(..model.edge_form, from:)),
      effect.none(),
    )
    EdgeToSelected(to) -> #(
      Model(..model, edge_form: EdgeForm(..model.edge_form, to:)),
      effect.none(),
    )
    EdgeSubmitted -> #(model, save_edge(model))
    EdgeSaved(Ok(_)) ->
      case model.selected {
        Some(universe) -> #(
          Model(..model, edge_form: empty_edge_form),
          load_edges(universe.id),
        )
        None -> #(model, effect.none())
      }
    EdgeSaved(Error(_)) -> #(model, effect.none())
    EdgeDeleteRequested(id) -> #(model, delete_edge(model, id))
    EdgeDeleteResolved(_) ->
      case model.selected {
        Some(universe) -> #(model, load_edges(universe.id))
        None -> #(model, effect.none())
      }
    GraphLoaded(Ok(graph)) -> #(
      Model(..model, graph: Loaded(graph)),
      render_graph(graph),
    )
    GraphLoaded(Error(_)) -> #(Model(..model, graph: Failed), effect.none())
    GraphKindChanged(kind) -> #(
      Model(..model, graph_filter: GraphFilter(..model.graph_filter, kind:)),
      effect.none(),
    )
    GraphRelationshipChanged(relationship) -> #(
      Model(
        ..model,
        graph_filter: GraphFilter(..model.graph_filter, relationship:),
      ),
      effect.none(),
    )
    GraphFieldChanged(field) -> #(
      Model(..model, graph_filter: GraphFilter(..model.graph_filter, field:)),
      effect.none(),
    )
    GraphValueChanged(value) -> #(
      Model(..model, graph_filter: GraphFilter(..model.graph_filter, value:)),
      effect.none(),
    )
    GraphFilterApplied ->
      case model.selected {
        Some(universe) -> #(
          Model(..model, graph: Loading),
          load_graph(universe.id, model.graph_filter),
        )
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
        edge_form_view(model),
        edges_view(model.edges, model.nodes),
        graph_filter_view(model.graph_filter),
        graph_view(model.graph),
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

fn edge_form_view(model: Model) -> Element(Msg) {
  html.div([attribute.attribute("data-test-id", "edge-form")], [
    html.input([
      attribute.attribute("data-test-id", "edge-relationship-input"),
      attribute.placeholder("Relationship"),
      attribute.value(model.edge_form.relationship),
      event.on_input(EdgeRelationshipChanged),
    ]),
    node_select(
      "edge-from-select",
      model.edge_form.from,
      model.nodes,
      EdgeFromSelected,
    ),
    node_select("edge-to-select", model.edge_form.to, model.nodes, EdgeToSelected),
    html.button(
      [
        attribute.attribute("data-test-id", "edge-submit"),
        event.on_click(EdgeSubmitted),
      ],
      [element.text("Add edge")],
    ),
  ])
}

fn node_select(
  test_id: String,
  current: String,
  nodes: Remote(List(shared.Node)),
  msg: fn(String) -> Msg,
) -> Element(Msg) {
  let options = case nodes {
    Loaded(list) ->
      list.map(list, fn(n) {
        html.option(
          [attribute.value(n.id), attribute.selected(n.id == current)],
          n.name,
        )
      })
    _ -> []
  }
  html.select(
    [attribute.attribute("data-test-id", test_id), event.on_change(msg)],
    options,
  )
}

fn edges_view(
  edges: Remote(List(shared.Edge)),
  nodes: Remote(List(shared.Node)),
) -> Element(Msg) {
  case edges {
    Loading -> status("Loading edges…")
    Failed -> status("Could not load edges")
    Loaded([]) -> status("No edges yet")
    Loaded(list) ->
      html.ul(
        [attribute.attribute("data-test-id", "edge-list")],
        list.map(list, fn(e) { edge_row(e, nodes) }),
      )
  }
}

fn edge_row(
  edge: shared.Edge,
  nodes: Remote(List(shared.Node)),
) -> Element(Msg) {
  html.li([attribute.attribute("data-test-id", "edge")], [
    html.span([attribute.attribute("data-test-id", "edge-from")], [
      element.text(node_name(nodes, edge.from)),
    ]),
    html.span([attribute.attribute("data-test-id", "edge-relationship")], [
      element.text(edge.relationship),
    ]),
    html.span([attribute.attribute("data-test-id", "edge-to")], [
      element.text(node_name(nodes, edge.to)),
    ]),
    html.button([event.on_click(EdgeDeleteRequested(edge.id))], [
      element.text("Delete"),
    ]),
  ])
}

fn node_name(nodes: Remote(List(shared.Node)), id: String) -> String {
  case nodes {
    Loaded(list) ->
      case list.find(list, fn(n) { n.id == id }) {
        Ok(n) -> n.name
        Error(_) -> id
      }
    _ -> id
  }
}

fn graph_filter_view(filter: GraphFilter) -> Element(Msg) {
  html.div([attribute.attribute("data-test-id", "graph-filter")], [
    filter_input("graph-kind-input", "Kind", filter.kind, GraphKindChanged),
    filter_input(
      "graph-relationship-input",
      "Relationship",
      filter.relationship,
      GraphRelationshipChanged,
    ),
    filter_input("graph-field-input", "Field", filter.field, GraphFieldChanged),
    filter_input("graph-value-input", "Value", filter.value, GraphValueChanged),
    html.button(
      [
        attribute.attribute("data-test-id", "graph-apply"),
        event.on_click(GraphFilterApplied),
      ],
      [element.text("Apply")],
    ),
  ])
}

fn filter_input(
  test_id: String,
  placeholder: String,
  value: String,
  msg: fn(String) -> Msg,
) -> Element(Msg) {
  html.input([
    attribute.attribute("data-test-id", test_id),
    attribute.placeholder(placeholder),
    attribute.value(value),
    event.on_input(msg),
  ])
}

fn graph_view(graph: Remote(shared.Graph)) -> Element(Msg) {
  let summary = case graph {
    Loading -> "Loading graph…"
    Failed -> "Could not load graph"
    Loaded(g) ->
      int.to_string(list.length(g.nodes))
      <> " nodes, "
      <> int.to_string(list.length(g.edges))
      <> " edges"
  }
  html.div([], [
    html.p([attribute.attribute("data-test-id", "graph-summary")], [
      element.text(summary),
    ]),
    html.div([attribute.attribute("data-test-id", "graph"), attribute.id("graph-canvas")], []),
  ])
}

fn status(text: String) -> Element(Msg) {
  html.p([attribute.attribute("data-test-id", "status")], [element.text(text)])
}
