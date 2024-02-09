/*
 * db_array_to_index
 * -----------------
 * Index (starting by 1, standard postgres) of the first element in anyarray that is equal to anyelement.
 * Returns NULL when anylement is not present in anyarray.
 */
CREATE OR REPLACE FUNCTION system.db_array_to_index(anyarray anyarray, anyelement anyelement)
	RETURNS integer AS
$BODY$
	SELECT index
		FROM generate_subscripts($1, 1) AS index
		WHERE $1[index] = $2
		ORDER BY index
$BODY$
LANGUAGE sql IMMUTABLE;


/*
 * db_enum_to_index
 * ----------------
 * Index (starting by 1, standard postgres) of anyenum in the type definition of it's enum type.
 */
CREATE OR REPLACE FUNCTION system.db_enum_to_index(anyenum anyenum)
	RETURNS integer AS
$BODY$
	SELECT system.db_array_to_index(enum_range($1), $1);
$BODY$
LANGUAGE sql IMMUTABLE;


/*
 * db_enum_by_index
 * ----------------
 * Anynum on index position (starting by 1, standard postgres) in the type definition of its enum type.
 * Returns NULL when the index is invalid.
 */
CREATE OR REPLACE FUNCTION system.db_enum_by_index(anyenum anyenum, index integer)
	RETURNS anyenum AS
$BODY$
	SELECT (enum_range($1))[$2];
$BODY$
LANGUAGE sql IMMUTABLE;
