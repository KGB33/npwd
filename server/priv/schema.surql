DEFINE TABLE IF NOT EXISTS universe SCHEMALESS;
DEFINE FIELD IF NOT EXISTS name ON universe TYPE string;
DEFINE FIELD IF NOT EXISTS description ON universe TYPE string;

DEFINE TABLE IF NOT EXISTS node SCHEMALESS;
DEFINE FIELD IF NOT EXISTS universe ON node TYPE record<universe>;
DEFINE FIELD IF NOT EXISTS kind ON node TYPE string;
DEFINE FIELD IF NOT EXISTS name ON node TYPE string;
REMOVE FIELD IF EXISTS description ON TABLE node;
DEFINE INDEX IF NOT EXISTS node_universe ON node FIELDS universe;
DEFINE INDEX IF NOT EXISTS node_kind ON node FIELDS kind;

DEFINE TABLE IF NOT EXISTS description SCHEMALESS;
DEFINE FIELD IF NOT EXISTS node ON description TYPE record<node>;
DEFINE FIELD IF NOT EXISTS position ON description TYPE int;
DEFINE FIELD IF NOT EXISTS body ON description TYPE string;
DEFINE INDEX IF NOT EXISTS description_node ON description FIELDS node;

DEFINE TABLE IF NOT EXISTS relationship TYPE RELATION SCHEMALESS;
DEFINE FIELD IF NOT EXISTS universe ON relationship TYPE record<universe>;
DEFINE FIELD IF NOT EXISTS relationship ON relationship TYPE string;
DEFINE INDEX IF NOT EXISTS relationship_universe ON relationship FIELDS universe;
