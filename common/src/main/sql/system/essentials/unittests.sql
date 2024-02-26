/*
 * list_unittest_functions
 * -----------------------
 * Function that returns a list of all functions starting with the supplied prefix.
 * Functions that are part of an extension or part of the PostgreSQL catalog are not returned.
 * Returns the function name (including schema), the arguments and the return value of the function.
 *
 * Called during build by ruby build script.
 */
CREATE OR REPLACE FUNCTION system.list_unittest_functions(v_prefix text)
	RETURNS TABLE(name regproc, args text, returns text) AS
$BODY$
DECLARE
	data_table regclass;
	noncatalog_objects oid[];
	extension_objects oid[];
BEGIN
	noncatalog_objects := (SELECT array_agg(objid) || array_agg(DISTINCT pg_namespace.oid) FROM pg_depend INNER JOIN pg_namespace ON (refobjid = pg_namespace.oid) WHERE pg_namespace.oid <> pg_my_temp_schema() AND NOT pg_is_other_temp_schema(pg_namespace.oid) AND NOT nspname IN ('information_schema', 'pg_catalog', 'pg_toast'));
	extension_objects := (SELECT array_agg(objid) || array_agg(DISTINCT pg_extension.oid) FROM pg_depend INNER JOIN pg_extension ON (refobjid = pg_extension.oid));

	RETURN QUERY SELECT
		pg_proc.oid::regproc AS name,
		pg_get_function_arguments(pg_proc.oid),
		pg_get_function_result(pg_proc.oid)

		FROM pg_proc

		WHERE
			proname ILIKE (replace(v_prefix, '_', '\_') || '%')
			AND pg_proc.oid NOT IN (SELECT aggfnoid FROM pg_aggregate)
			AND pg_proc.oid = ANY(noncatalog_objects)
			AND NOT pg_proc.oid = ANY(extension_objects)
	;
	RETURN;
END;
$BODY$
LANGUAGE plpgsql STABLE;


/*
 * execute_unittest
 * ----------------
 * Function to execute the supplied (unit test) function.
 * In case of an exception (which should be the case when an assert in the unit test fails), the exception is caught, parsed,
 * and the exception message, line number and first context line number are all returned in a record.
 * A unit test should fail on the first exception, so this function should never return more than 1 record.
 * When no records are returned, the unit test was succesfull.
 *
 * Called during build by ruby build script to execute a unittest.
 */
CREATE OR REPLACE FUNCTION system.execute_unittest(v_function regproc)
	RETURNS TABLE(errcode text, message text, linenr integer, context text) AS
$BODY$
DECLARE
	v_context text;
	v_line integer;
BEGIN
	EXECUTE 'SELECT ' || v_function || '()';
	RETURN;
EXCEPTION WHEN OTHERS THEN
	GET STACKED DIAGNOSTICS v_context = PG_EXCEPTION_CONTEXT;
	v_line = substring(v_context from 'line (\d+) at')::integer;
	RETURN QUERY SELECT SQLSTATE, SQLERRM, v_line, (string_to_array(v_context, E'\n'))[1];
END;
$BODY$
LANGUAGE plpgsql VOLATILE;
