import db.{NotFound, QueryError}
import gleam/list
import pog
import shared/character.{type Character, Character}
import sql
import youid/uuid.{type Uuid}

pub fn insert(db: pog.Connection, name: String) -> Result(Character, db.DbError) {
  case sql.insert_character(db, name) {
    Ok(pog.Returned(_, [row])) -> Ok(Character(id: row.id, name: row.name))
    Ok(_) -> Error(QueryError(pog.UnexpectedResultType([])))
    Error(e) -> Error(QueryError(e))
  }
}

pub fn list(db: pog.Connection) -> Result(List(Character), db.DbError) {
  case sql.list_characters(db) {
    Ok(pog.Returned(_, rows)) ->
      Ok(list.map(rows, fn(row) { Character(id: row.id, name: row.name) }))
    Error(e) -> Error(QueryError(e))
  }
}

pub fn get_by_id(db: pog.Connection, id: Uuid) -> Result(Character, db.DbError) {
  case sql.get_characters_by_id(db, id) {
    Ok(pog.Returned(_, [row])) -> Ok(Character(id: row.id, name: row.name))
    Ok(pog.Returned(_, [])) -> Error(NotFound)
    Ok(_) -> Error(QueryError(pog.UnexpectedResultType([])))
    Error(e) -> Error(QueryError(e))
  }
}

pub fn get_by_name(
  db: pog.Connection,
  name: String,
) -> Result(List(Character), db.DbError) {
  case sql.get_characters_by_name(db, name) {
    Ok(pog.Returned(_, rows)) ->
      Ok(list.map(rows, fn(row) { Character(id: row.id, name: row.name) }))
    Error(e) -> Error(QueryError(e))
  }
}

pub fn update(
  db: pog.Connection,
  id: Uuid,
  name: String,
) -> Result(Character, db.DbError) {
  case sql.update_character(db, id, name) {
    Ok(pog.Returned(_, [row])) -> Ok(Character(id: row.id, name: row.name))
    Ok(pog.Returned(0, _)) -> Error(NotFound)
    Ok(_) -> Error(QueryError(pog.UnexpectedResultType([])))
    Error(e) -> Error(QueryError(e))
  }
}

pub fn delete(db: pog.Connection, id: Uuid) -> Result(Nil, db.DbError) {
  case sql.delete_character(db, id) {
    Ok(pog.Returned(1, _)) -> Ok(Nil)
    Ok(pog.Returned(0, _)) -> Error(NotFound)
    Ok(_) -> Error(QueryError(pog.UnexpectedResultType([])))
    Error(e) -> Error(QueryError(e))
  }
}
