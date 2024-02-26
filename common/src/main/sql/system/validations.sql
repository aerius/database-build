/*
 * perform_and_report_validation
 * -----------------------------
 * Function to execute a validation function, logging the information in the appropriate validation tables.
 */
CREATE OR REPLACE FUNCTION system.perform_and_report_validation(function_name regproc, params text = NULL)
	 RETURNS void AS
$BODY$
DECLARE
	rec record;
	validation_result system.validation_result_type = 'success';
BEGIN
	FOR rec IN
		EXECUTE 'SELECT result, object, message FROM ' || function_name || '(' || COALESCE(params, '') || ')'
	LOOP
		validation_result := GREATEST(validation_result, rec.result);
		INSERT INTO system.validation_logs(validation_run_id, name, result, object, message)
			VALUES(system.current_validation_run_id(), function_name, rec.result, rec.object, rec.message);
	END LOOP;
	INSERT INTO system.validation_results(validation_run_id, name, result)
		VALUES(system.current_validation_run_id(), function_name, validation_result);
END;
$BODY$
LANGUAGE plpgsql VOLATILE;


/*
 * current_validation_run_id
 * -------------------------
 * Function to determine the current validation_run_id.
 * A new validation run is created if this ID does not exist yet.
 */
CREATE OR REPLACE FUNCTION system.current_validation_run_id()
	 RETURNS integer AS
$BODY$
DECLARE
	v_validation_run_id integer;
BEGIN
	v_validation_run_id := (
		SELECT validation_run_id
			FROM system.validation_runs
			WHERE transaction_id = txid_current()
	);

	IF v_validation_run_id IS NULL THEN
		INSERT INTO system.validation_runs(transaction_id)
			SELECT txid_current()
			RETURNING validation_run_id INTO v_validation_run_id;
	END IF;

	RETURN v_validation_run_id;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;


/*
 * to_validation_result
 * --------------------
 * Function to transform separate validation result variables into a validation result type (system.validation_result).
 * Variation where the object being tested is supplied as text.
 */
CREATE OR REPLACE FUNCTION system.to_validation_result(v_result system.validation_result_type, v_object text, v_message text)
	 RETURNS system.validation_result AS
$BODY$
BEGIN
	RETURN (v_result, v_object, v_message);
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;


/*
 * to_validation_result
 * --------------------
 * Function to transform separate validation result variables into a validation result type (system.validation_result).
 * Variation where the object being tested is supplied as a regclass (database reference).
 */
CREATE OR REPLACE FUNCTION system.to_validation_result(v_result system.validation_result_type, v_object regclass, v_message text)
	 RETURNS system.validation_result AS
$BODY$
BEGIN
	RETURN (v_result, v_object::text, v_message);
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;


/*
 * validate_tables_not_empty
 * -------------------------
 * Function to list tables that are empty; exception for those that shouldn't be.
 */
CREATE OR REPLACE FUNCTION system.validate_tables_not_empty()
	 RETURNS SETOF system.validation_result AS
$BODY$
DECLARE
	rec record;
	rec_in_table record;
BEGIN
	RAISE NOTICE '* Listing empty tables...';
	FOR rec IN
		SELECT (table_schema || '.' || table_name)::regclass AS tablename
			FROM information_schema.tables
		WHERE table_type = 'BASE TABLE' AND table_schema NOT IN ('pg_catalog', 'information_schema')
		ORDER BY table_schema, table_name
	LOOP
		EXECUTE 'SELECT 1 FROM ' || rec.tablename || ' LIMIT 1' INTO rec_in_table;
		IF rec_in_table IS NULL THEN
			RETURN NEXT system.to_validation_result('hint', rec.tablename, 'Table is empty');
		END IF;
	END LOOP;
	RETURN;
END;
$BODY$
LANGUAGE plpgsql STABLE;


/*
 * validate_incorrect_imports
 * --------------------------
 * Function to validat if there are tables that contain '\N' in a text(like) column.
 * This is an indication that something failed on import.
 */
CREATE OR REPLACE FUNCTION system.validate_incorrect_imports()
	 RETURNS SETOF system.validation_result AS
$BODY$
DECLARE
	rec record;
	num_records integer;
BEGIN
	-->> Text fields containing the string \N indicate that NULL values were incorrectly imported
	RAISE NOTICE '* Searching for incorrect COPY FROM imports: NULL values...';
	FOR rec IN
		SELECT (table_schema || '.' || table_name)::regclass AS tablename, column_name
		FROM information_schema.columns
		WHERE is_updatable = 'YES' AND table_schema NOT IN ('pg_catalog', 'information_schema') AND (data_type = 'text' OR data_type = 'character' OR data_type = 'character varying')
		ORDER BY table_schema, table_name, ordinal_position
	LOOP
		EXECUTE 'SELECT COUNT(*) FROM ' || rec.tablename || ' WHERE "' || rec.column_name || E'" = E''\\\\N''' INTO num_records;
		IF num_records > 0 THEN
			RETURN NEXT system.to_validation_result('error', rec.tablename,
				format(E'Column "%s" has %s records containing \\N', rec.column_name, num_records));
		END IF;
	END LOOP;
	RETURN;
END;
$BODY$
LANGUAGE plpgsql STABLE;
