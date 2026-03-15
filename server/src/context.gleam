import glogg/logger.{type Logger}
import pog

pub type Context {
  Context(db: pog.Connection, static_dir: String, logger: Logger)
}
