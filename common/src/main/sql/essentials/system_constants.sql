/*
 * constants
 * ---------
 * System table for constants used by the web application.
 */
CREATE TABLE system.constants (
	key text NOT NULL,
	value text NOT NULL,
	description text,
	type text,

	CONSTRAINT constants_pkey PRIMARY KEY (key)
);


/*
 * db_constant
 * -----------
 * Function returning the value of a database or web application constant.
 * When the constant does not exist in the view system.constants_view, an exception is raised.
 */
CREATE OR REPLACE FUNCTION system.db_constant(constant_key text)
	RETURNS text AS
$BODY$
DECLARE
	constant_value text;
BEGIN
	SELECT value INTO constant_value FROM system.constants_view WHERE key = constant_key;
	IF constant_value IS NULL THEN
		RAISE EXCEPTION 'Could not find a public or system constant value for ''%''!', constant_key;
	END IF;
	RETURN constant_value;
END;
$BODY$
LANGUAGE plpgsql STABLE;


/*
 * db_set_constant
 * ---------------
 * Function to change the value of a web application constant.
 * When the constant does not yet exist in the system.constants table, an exception is raised.
 */
CREATE OR REPLACE FUNCTION system.db_set_constant(constant_key text, constant_value text)
	RETURNS void AS
$BODY$
BEGIN
	IF NOT EXISTS(SELECT value FROM system.constants WHERE key = constant_key) THEN
		RAISE EXCEPTION 'Could not find a system constant value for ''%''!', constant_key;
	END IF;

	UPDATE system.constants SET value = constant_value WHERE key = constant_key;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;


/*
 * db_get_git_revision
 * -------------------
 * Function returning the revision value, which is stored as a web application constant.
 */
CREATE OR REPLACE FUNCTION system.db_get_git_revision()
	RETURNS text AS
$BODY$
	SELECT CASE
	WHEN EXISTS (SELECT 1 FROM system.constants WHERE key = 'CURRENT_GIT_REVISION') THEN
		system.db_constant('CURRENT_GIT_REVISION')
	WHEN EXISTS (SELECT 1 FROM system.constants WHERE key = 'CURRENT_DATABASE_VERSION') THEN
		reverse(split_part(reverse(system.db_constant('CURRENT_DATABASE_VERSION')), '_', 1))
	ELSE
		reverse(split_part(reverse(system.db_constant('CURRENT_DATABASE_NAME')), '_', 1))
	END;
$BODY$
LANGUAGE SQL STABLE;
