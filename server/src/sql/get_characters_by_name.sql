-- Get A list of characters by name

select
    *
from
    characters
where
    name ilike $1
;
