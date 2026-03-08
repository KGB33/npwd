UPDATE characters
SET
  name = $2
WHERE id = $1
RETURNING *;
