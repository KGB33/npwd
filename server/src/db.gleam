import pog

pub type DbError {
  NotFound
  QueryError(pog.QueryError)
}
