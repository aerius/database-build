/*
 * metadata
 * --------
 * Table that stores the source import-file per imported table and creates a checksum during the import-proces.
 * - @column timestamp The date/time of the import, is filled by the load_table function.
 * - @column filename The filename of the import file imported via the load_table function (which has been extended for this purpose with this functionality).
 * - @column checksum The checksum of the table after import. This is populated by the load_table function. If it's '0', the table contains no data.
 * - @column checksum_before The checksum of the table before import. This is populated by the load_table function. If it's '0', the table contains no data.
  */
CREATE TABLE system.metadata (
	tablename text NOT NULL,
	timestamp timestamp NOT NULL,
	filename text NOT NULL,
	checksum bigint NOT NULL,
	checksum_before bigint,
	
	CONSTRAINT metadata_pkey PRIMARY KEY (tablename, timestamp)
);


/*
 * determine_checksum
 * ------------------
 * Function that returns a checksum value for a given tablename. 
 * Used by functions that populate the checksum in the metadata table, allowing table content comparisons between databases in different locations.
 * @param v_tablename The table name for which the checksum should be generated.
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
 * register_metadata
 * -----------------
 * Function that writes metadata for the given table in the system.metadata table. 
 * Each import is logged, regardless if the table already exists in this metadata table.
 * @param v_tablename The table name for which the checksum is generated.
 * @param filename The filename that is used for the import.
 * @#param checksum_before The checksum of the table before the data is inserted.
 */
CREATE OR REPLACE FUNCTION system.register_metadata(tablename text, filename text, checksum_before bigint)
	RETURNS void AS
$BODY$
DECLARE
	v_checksum bigint;
BEGIN
	RAISE NOTICE '% Insert imported file in metadata table @ %', tablename, timeofday();

	v_checksum := system.determine_checksum_table(tablename::text);
	
	INSERT INTO system.metadata (tablename, filename, checksum_before, checksum, timestamp) 
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
 * last_metadata_files_view
 * ------------------------
 * Returns the metadata information of the last imported import-files per table from the metadata table.
 */
CREATE OR REPLACE VIEW system.last_metadata_files_view AS
WITH metadata_last_file AS (
	SELECT 
		tablename,
		timestamp,
		filename,
		checksum,
		checksum_before,
		ROW_NUMBER() OVER (PARTITION BY tablename ORDER BY tablename, timestamp DESC) AS row_no
		
		FROM system.metadata 
)
SELECT 
	tablename,
	timestamp,
	filename,
	checksum,
	checksum_before

	FROM metadata_last_file 

	WHERE row_no = 1 

	ORDER BY tablename 
;
