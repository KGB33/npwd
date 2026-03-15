CREATE TABLE characters (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  name VARCHAR(50) NOT NULL
);

CREATE TABLE entries (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
  text TEXT NOT NULL
);
