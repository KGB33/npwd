import db.{NotFound, QueryError}
import gleam/list
import pog
import shared/entry.{type Entry, Entry}
import sql
import youid/uuid.{type Uuid}

pub fn list_by_character(
  db: pog.Connection,
  character_id: Uuid,
) -> Result(List(Entry), db.DbError) {
  case sql.list_entries_by_character(db, character_id) {
    Ok(pog.Returned(_, rows)) ->
      Ok(
        list.map(rows, fn(row) {
          Entry(id: row.id, character_id: row.character_id, text: row.text)
        }),
      )
    Error(e) -> Error(QueryError(e))
  }
}

pub fn insert(
  db: pog.Connection,
  character_id: Uuid,
  text: String,
) -> Result(Entry, db.DbError) {
  case sql.insert_entry(db, character_id, text) {
    Ok(pog.Returned(_, [row])) ->
      Ok(Entry(id: row.id, character_id: row.character_id, text: row.text))
    Ok(_) -> Error(QueryError(pog.UnexpectedResultType([])))
    Error(e) -> Error(QueryError(e))
  }
}

pub fn delete(db: pog.Connection, id: Uuid) -> Result(Nil, db.DbError) {
  case sql.delete_entry(db, id) {
    Ok(pog.Returned(1, _)) -> Ok(Nil)
    Ok(pog.Returned(0, _)) -> Error(NotFound)
    Ok(_) -> Error(QueryError(pog.UnexpectedResultType([])))
    Error(e) -> Error(QueryError(e))
  }
}
