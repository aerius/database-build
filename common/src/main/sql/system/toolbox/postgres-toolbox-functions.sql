/*
 * protect_table
 * -------------
 * Simple trigger function to make a table readonly.
 * Useful for 'abstract base tables'.
 */
CREATE OR REPLACE FUNCTION system.protect_table()
	RETURNS trigger AS
$BODY$
BEGIN
	RAISE EXCEPTION '%.% is a protected/readonly table!', TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$BODY$
LANGUAGE plpgsql;


/*
 * raise_notice
 * ------------
 * Function for showing report messages, mainly during a database build.
 * This is a wrapper around the plpgsql notice function, so this can be called from normal SQL (outside a function).
 */
CREATE OR REPLACE FUNCTION system.raise_notice(message text)
	RETURNS void AS
$BODY$
DECLARE
BEGIN
	RAISE NOTICE '%', message;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;
