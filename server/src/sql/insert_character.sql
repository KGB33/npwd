-- Create a new Character
insert into characters
    (name)
VALUES
    ($1)
returning *
;
