-- Get A character by id

select
    *
from
    characters
where
    id = $1
;
