/**
 * get_search_path
 * ---------------
 * Returns the current PostgreSQL search_path as a text string.
 */
CREATE OR REPLACE FUNCTION system.get_search_path()
	RETURNS text AS
$BODY$
BEGIN
	RETURN current_setting('search_path');
END;
$BODY$
LANGUAGE plpgsql VOLATILE;


/**
 * set_search_path
 * ---------------
 * Sets the PostgreSQL search_path for the current session. Applies only to the current session.
 *
 * @param path A comma-separated list of schemas to set as the new search_path.
 */
CREATE OR REPLACE FUNCTION system.set_search_path(path text)
	RETURNS void AS
$BODY$
BEGIN
	RAISE NOTICE 'Set search_path to %', path;

	PERFORM set_config('search_path', path, FALSE);
END;
$BODY$
LANGUAGE plpgsql VOLATILE;


/**
 * get_search_path_schema
 * ----------------------
 * Returns the schema at a specific index within the current search_path, or NULL if out of range.
 *
 * @param index 1-based index (standard Postgres) of the schema to retrieve.
 * @param return_user If TRUE, resolves '$user' to current_user; if FALSE, skips '$user' and returns the next schema.
 */
CREATE OR REPLACE FUNCTION system.get_search_path_schema(index int, return_user boolean = FALSE)
	RETURNS text AS
$BODY$
DECLARE
	schemas text[];
	schema text;
BEGIN
	schemas := regexp_split_to_array(system.get_search_path(), '\s*,\s*');

	IF index < 1 OR index > array_length(schemas, 1) THEN
		RETURN NULL;
	END IF;

	schema := replace(schemas[index], '"', '');

	IF schema = '$user' THEN
		IF return_user THEN
			schema := current_user;
		ELSE
			RETURN get_search_path_schema(index + 1, return_user);
		END IF;
	END IF;

	RETURN schema;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;
