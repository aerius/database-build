/*
 * validation_runs
 * ---------------
 * Table to track validation runs.
 * Each validation run ends up as a record in this table.
 * A validation run always correponds to a specific backend connection.
 * When running the validations in a fresh connection, a new validation-run_id should be used.
 * This is automatically done by the validation logger function (perform_and_report_validation).
 */
CREATE TABLE system.validation_runs (
	validation_run_id serial NOT NULL,
	transaction_id bigint NOT NULL,

	CONSTRAINT validation_runs_pkey PRIMARY KEY (validation_run_id)
);


/*
 * validation_results
 * ------------------
 * Table to track validation run results.
 * Each validation executed ends up as a record in this table, along with the validation result.
 */
CREATE TABLE system.validation_results (
	validaton_result_id serial NOT NULL,
	validation_run_id integer NOT NULL,
	name regproc NOT NULL,
	result system.validation_result_type NOT NULL,

	CONSTRAINT validation_results_pkey PRIMARY KEY (validaton_result_id),
	CONSTRAINT validation_results_fkey_validaton_runs FOREIGN KEY (validation_run_id) REFERENCES system.validation_runs,
	CONSTRAINT validation_results_unique_combination UNIQUE (validation_run_id, name)
);


/*
 * validation_logs
 * ---------------
 * Table for saving the validaton logs.
 * Each test executed within a validation ends up as a record in this table, along with the result.
 */
CREATE TABLE system.validation_logs (
	validation_log_id serial NOT NULL,
	validation_run_id integer NOT NULL,
	name regproc NOT NULL,
	result system.validation_result_type NOT NULL,
	object text,
	message text NOT NULL,

	CONSTRAINT validation_logs_pkey PRIMARY KEY (validation_log_id),
	CONSTRAINT validation_logs_fkey_validaton_runs FOREIGN KEY (validation_run_id) REFERENCES system.validation_runs
);


/*
 * last_validation_run_results_view
 * --------------------------------
 * View returning the validation results of the last validation run.
 */
CREATE OR REPLACE VIEW system.last_validation_run_results_view AS
SELECT
	validation_run_id,
	name,
	result

	FROM system.validation_results
		INNER JOIN (SELECT validation_run_id FROM system.validation_runs ORDER BY validation_run_id DESC LIMIT 1) AS last_run_id USING (validation_run_id)

	ORDER BY validation_run_id, result DESC, name
;


/*
 * last_validation_logs_view
 * -------------------------
 * View returning the validation logs of the last validation run.
 */
CREATE OR REPLACE VIEW system.last_validation_logs_view AS
SELECT
	validation_run_id,
	name,
	run_results.result AS run_result,
	logs.result AS log_result,
	object,
	message

	FROM system.last_validation_run_results_view AS run_results
		INNER JOIN system.validation_logs AS logs USING (validation_run_id, name)

	ORDER BY validation_run_id, run_result DESC, log_result DESC, name, object
;


/*
 * last_validation_run_view
 * ------------------------
 * View returning the validation statistics of the last validation run.
 * The result of the validations within the run are aggregated by result type.
 */
CREATE OR REPLACE VIEW system.last_validation_run_view AS
SELECT
	validation_run_id,
	result,
	COALESCE(COUNT(name), 0) AS number_of_tests

	FROM (SELECT validation_run_id FROM system.validation_runs ORDER BY validation_run_id DESC LIMIT 1) AS last_run_id
		CROSS JOIN (SELECT unnest(enum_range(null::system.validation_result_type)) AS result) AS result_types
		LEFT JOIN system.validation_results USING (validation_run_id, result)

	GROUP BY validation_run_id, result

	ORDER BY validation_run_id, result DESC
;


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
 * perform_and_report_test
 * -----------------------
 * Functon to execute a unittest function, logging the information in the appropriate validation tables.
 */
CREATE OR REPLACE FUNCTION system.perform_and_report_test(function_name regproc, params text = NULL)
	 RETURNS void AS
$BODY$
DECLARE
	rec record;
	validation_result system.validation_result_type = 'success';
BEGIN
	BEGIN
		EXECUTE 'SELECT ' || function_name || '(' || COALESCE(params, '') || ')';
	EXCEPTION WHEN OTHERS THEN
		validation_result := 'error';
		INSERT INTO system.validation_logs(validation_run_id, name, result, object, message)
			VALUES(system.current_validation_run_id(), function_name, validation_result, NULL::text, SQLERRM);
	END;
	INSERT INTO system.validation_results(validation_run_id, name, result)
		VALUES(system.current_validation_run_id(), function_name, validation_result);
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
	-- Text fields containing the string \N indicate that NULL values were incorrectly imported
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
