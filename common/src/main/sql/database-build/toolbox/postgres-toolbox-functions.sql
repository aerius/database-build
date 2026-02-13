/*
 * protect_table
 * -------------
 * Generic trigger function that protects a table from operations.
 * Protects from whatever operations the trigger is defined for (INSERT, UPDATE, DELETE, or any combination).
 * When attached via a BEFORE trigger, raises an exception for any matching operation attempt.
 * Useful for abstract base tables or any table where direct operations should be prevented.
 */
CREATE OR REPLACE FUNCTION system.protect_table()
	RETURNS trigger AS
$BODY$
BEGIN
	RAISE EXCEPTION '%.% is a protected table where % statements are not allowed!', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP;
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
