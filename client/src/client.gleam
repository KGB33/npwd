import client/model.{
  type GraphFilter, type Model, type Msg, DayChanged, DeleteRequested,
  DeleteResolved, DescriptionChanged, EdgeDeleteRequested, EdgeDeleteResolved,
  EdgeForm, EdgeFromSelected, EdgeRelationshipChanged, EdgeSaved, EdgeSubmitted,
  EdgeToSelected, EdgesLoaded, EditCancelled, EditStarted, Failed, Form,
  GenderChanged, GenericFieldAdded, GenericFieldRemoved, GenericForm,
  GenericKeyChanged, GenericValueChanged, GraphFieldChanged, GraphFilter,
  GraphFilterApplied, GraphFilterCleared, GraphFromChanged, GraphLoaded,
  GraphRelationshipChanged, GraphToChanged, GraphValueChanged, KindSelected,
  Loaded, Loading, Model, MonthChanged, NameChanged, NodeDeleteRequested,
  NodeDeleteResolved, NodeDescriptionChanged, NodeEditCancelled, NodeEditStarted,
  NodeForm, NodeNameChanged, NodeSaved, NodeSubmitted, NodesLoaded, PersonForm,
  Saved, Submitted, TimelineLoaded, UniverseDeselected, UniverseSelected,
  UniversesLoaded, YearChanged, default_kind, edge_body, edge_submittable,
  empty_edge_form, empty_form, empty_graph_filter, empty_node_form, graph_query,
  node_body, node_to_form, set_date, set_kind, update_at,
}
import client/view
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import lustre
import lustre/effect.{type Effect}
import rsvp
import shared

pub fn main() -> Nil {
  let app = lustre.application(init, update, view.view)
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
      timeline: Loading,
    ),
    load_universes(),
  )
}

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

fn load_timeline(universe: String) -> Effect(Msg) {
  rsvp.get(
    "/universes/" <> universe <> "/timeline",
    rsvp.expect_json(shared.graph_decoder(), TimelineLoaded),
  )
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
        timeline: Loading,
      ),
      effect.batch([
        load_nodes(universe.id),
        load_edges(universe.id),
        load_graph(universe.id, empty_graph_filter),
        load_timeline(universe.id),
      ]),
    )
    UniverseDeselected -> #(
      Model(
        ..model,
        selected: None,
        nodes: Loading,
        edges: Loading,
        graph: Loading,
        timeline: Loading,
      ),
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
    EdgeSubmitted ->
      case edge_submittable(model.edge_form) {
        True -> #(model, save_edge(model))
        False -> #(model, effect.none())
      }
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
    GraphFromChanged(from) -> #(
      Model(..model, graph_filter: GraphFilter(..model.graph_filter, from:)),
      effect.none(),
    )
    GraphRelationshipChanged(relationship) -> #(
      Model(
        ..model,
        graph_filter: GraphFilter(..model.graph_filter, relationship:),
      ),
      effect.none(),
    )
    GraphToChanged(to) -> #(
      Model(..model, graph_filter: GraphFilter(..model.graph_filter, to:)),
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
    GraphFilterCleared ->
      case model.selected {
        Some(universe) -> #(
          Model(..model, graph: Loading, graph_filter: empty_graph_filter),
          load_graph(universe.id, empty_graph_filter),
        )
        None -> #(
          Model(..model, graph_filter: empty_graph_filter),
          effect.none(),
        )
      }
    TimelineLoaded(Ok(timeline)) -> #(
      Model(..model, timeline: Loaded(timeline)),
      effect.none(),
    )
    TimelineLoaded(Error(_)) -> #(
      Model(..model, timeline: Failed),
      effect.none(),
    )
  }
}
