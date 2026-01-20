/*
 * load_table_logs
 * ---------------
 * Table which stores metadata from a load_table action for verifying the loading of the table and the loaded data.
 * - @column timestamp The date/time of the import, is filled by the load_table function.
 * - @column filename The filename of the import file imported via the load_table function (which has been extended for this purpose with this functionality).
 * - @column checksum The checksum of the table after import, is filled by the load_table function. If it's '0', the table contains no data.
 * - @column checksum_before The checksum of the table before import, is filled by the load_table function. If it's '0', the table contains no data.
  */
CREATE TABLE system.load_table_logs (
	tablename regclass NOT NULL,
	timestamp timestamp NOT NULL,
	filename text NOT NULL,
	checksum bigint NOT NULL,
	checksum_before bigint,
	
	CONSTRAINT load_table_logs_pkey PRIMARY KEY (tablename, timestamp)
);


/*
 * determine_checksum_table
 * ------------------------
 * Function that returns a checksum value for a given tablename. 
 * Used by the function that populates the checksum in the load_table_logs table, allowing table content comparisons between databases in different locations.
 * @param v_tablename The table name for which the checksum is generated.
 */
CREATE OR REPLACE FUNCTION system.determine_checksum_table(v_tablename text)
	RETURNS SETOF bigint AS
$BODY$
DECLARE v_sql text;
BEGIN
	v_sql := 'SELECT COALESCE(SUM(hashtext((checksum_table.*)::text)), 0)::bigint AS checksum FROM ' || v_tablename || ' AS checksum_table;';
	RETURN QUERY EXECUTE v_sql;
END;
	
$BODY$
LANGUAGE plpgsql IMMUTABLE;


/*
 * register_load_table
 * -------------------
 * Function that registers the load_table action and stores metadata in the system.load_table_logs.
 * Each import is logged, regardless if the table already exists.
 * @param v_tablename The table name for which the checksum is generated.
 * @param v_filename The filename that is used for the import.
 * @param v_checksum_before The checksum of the table before the data is inserted.
 */
CREATE OR REPLACE FUNCTION system.register_load_table(v_tablename text, v_filename text, v_checksum_before bigint)
	RETURNS void AS
$BODY$
DECLARE
	v_checksum bigint;
BEGIN
	RAISE NOTICE '% Insert imported file in load_table_logs table @ %', v_tablename, timeofday();

	v_checksum := system.determine_checksum_table(v_tablename);
	
	INSERT INTO system.load_table_logs (tablename, timestamp, filename, checksum, checksum_before) 
		VALUES (
			v_tablename::regclass,
			clock_timestamp()::timestamp,
			SPLIT_PART(v_filename, '/', -1),
			v_checksum,
			v_checksum_before
	); 
	
END;
$BODY$
LANGUAGE plpgsql VOLATILE;


/*
 * prevailing_load_table_logs_view
 * -------------------------------
 * Returns the table log information of all imported import-files from the latest import-batch per table.
 */
CREATE OR REPLACE VIEW system.prevailing_load_table_logs_view AS
WITH empty_checksums AS (
	SELECT 
		tablename, 
		MAX(timestamp) AS latest_empty_checksum
	
		FROM system.load_table_logs 
		
		WHERE checksum_before = 0
		
		GROUP BY tablename
)
SELECT 
	tablename,
	timestamp,
	filename,
	checksum,
	checksum_before

	FROM system.load_table_logs 
		INNER JOIN empty_checksums USING (tablename)

	WHERE timestamp >= empty_checksums.latest_empty_checksum

	ORDER BY tablename, timestamp
;


/*
 * current_load_table_data_checksums_view
 * --------------------------------------
 * Returns the table log information of the last imported import-file per table from the load_table_logs table.
 * 
 */
CREATE OR REPLACE VIEW system.current_load_table_data_checksums_view AS
WITH latest_timestamp AS (
SELECT
	tablename,
	MAX(timestamp) AS timestamp
	
	FROM system.prevailing_load_table_logs_view

	GROUP BY tablename
)
SELECT 
	tablename,
	timestamp,
	checksum

	FROM latest_timestamp
		INNER JOIN system.load_table_logs USING (tablename, timestamp)

	ORDER BY tablename
;


/*
 * validate_load_table_data_checksums_view
 * ---------------------------------------
 * Returns the table log information of the last imported import-files per table from the load_table_logs table, supplemented with the real-time determined checksum.
 * Can be used to determine if the data per table is changed since the lastest load_table action.
 * 
 */
CREATE OR REPLACE VIEW system.validate_load_table_data_checksums_view AS
SELECT 
	tablename,
	timestamp,
	checksum AS stored_checksum,
	system.determine_checksum_table(tablename::text) AS determined_checksum,
	checksum = system.determine_checksum_table(tablename::text) AS checksum_valid

	FROM system.current_load_table_data_checksums_view

	ORDER BY tablename, timestamp
;
