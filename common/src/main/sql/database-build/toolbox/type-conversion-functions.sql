/*
 * array_to_index
 * -------------- 
 * Index (starting by 1, standard Postgres) of the first element in anyarray that is equal to anyelement.
 * Returns NULL when anylement is not present in anyarray.
 */
CREATE OR REPLACE FUNCTION system.array_to_index(anyarray anyarray, anyelement anyelement)
	RETURNS integer AS
$BODY$
	SELECT index
		FROM generate_subscripts($1, 1) AS index
		WHERE $1[index] = $2
		ORDER BY index
$BODY$
LANGUAGE sql IMMUTABLE;


/*
 * enum_to_index
 * -------------
 * Index (starting by 1, standard Postgres) of anyenum in the type definition of it's enum type.
 */
CREATE OR REPLACE FUNCTION system.enum_to_index(anyenum anyenum)
	RETURNS integer AS
$BODY$
	SELECT system.array_to_index(enum_range($1), $1);
$BODY$
LANGUAGE sql IMMUTABLE;


/*
 * enum_by_index
 * -------------
 * Anynum on index position (starting by 1, standard Postgres) in the type definition of its enum type.
 * Returns NULL when the index is invalid.
 */
CREATE OR REPLACE FUNCTION system.enum_by_index(anyenum anyenum, index integer)
	RETURNS anyenum AS
$BODY$
	SELECT (enum_range($1))[$2];
$BODY$
LANGUAGE sql IMMUTABLE;
