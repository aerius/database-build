/*
 * load_table_logs
 * ---------------
 * Table that stores the source import-file per imported table and creates a checksum during the import-proces.
 * - @column timestamp The date/time of the import, is filled by the load_table function.
 * - @column filename The filename of the import file imported via the load_table function (which has been extended for this purpose with this functionality).
 * - @column checksum The checksum of the table after import. This is populated by the load_table function. If it's '0', the table contains no data.
 * - @column checksum_before The checksum of the table before import. This is populated by the load_table function. If it's '0', the table contains no data.
  */
CREATE TABLE system.load_table_logs (
	tablename text NOT NULL,
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
 * register_load_table_logs
 * ------------------------
 * Function that writes log-data for the given table in the system.load_table_logs table. 
 * Each import is logged, regardless if the table already exists in this metaload_table_logs table.
 * @param v_tablename The table name for which the checksum is generated.
 * @param filename The filename that is used for the import.
 * @#param checksum_before The checksum of the table before the data is inserted.
 */
CREATE OR REPLACE FUNCTION system.register_load_table_logs(tablename text, filename text, checksum_before bigint)
	RETURNS void AS
$BODY$
DECLARE
	v_checksum bigint;
BEGIN
	RAISE NOTICE '% Insert imported file in load_table_logs table @ %', tablename, timeofday();

	v_checksum := system.determine_checksum_table(tablename::text);
	
	INSERT INTO system.load_table_logs (tablename, filename, checksum_before, checksum, timestamp) 
		VALUES (
			tablename,
			SPLIT_PART(filename, '/', -1),
			checksum_before,
			v_checksum,
			clock_timestamp()::timestamp
	); 
	
END;
$BODY$
LANGUAGE plpgsql VOLATILE;


/*
 * last_load_table_logs_view
 * -------------------------
 * Returns the table log information of the last imported import-files per table from the load_table_logs table.
 */
CREATE OR REPLACE VIEW system.last_load_table_logs_view AS
WITH numbered_files AS (
	SELECT 
		tablename,
		timestamp,
		filename,
		checksum,
		checksum_before,
		ROW_NUMBER() OVER (PARTITION BY tablename ORDER BY tablename, timestamp DESC) AS row_no
		
		FROM system.load_table_logs 
)
SELECT 
	tablename,
	timestamp,
	filename,
	checksum,
	checksum_before

	FROM numbered_files 

	WHERE row_no = 1 

	ORDER BY tablename 
;
