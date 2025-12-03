/*
 * metadata
 * --------
 * Table that stores the source import-file per imported table and creates a checksum during the import-proces.
 * - @column filename The filename of the import file imported via the load_table function (which has been extended for this purpose with this functionality).
 * - @column checksum The checksum of the table after import. This is populated by the load_table function. If it's '0', the table contains no data.
 * - @column timestamp The date/time of the import, is filled by the load_table function.
 */
CREATE TABLE system.metadata (
	metadata_id integer GENERATED ALWAYS AS IDENTITY,
	tablename text NOT NULL,
	filename text NULL,
	checksum_before bigint NULL,
	checksum bigint NULL,
	timestamp timestamp NULL,

	CONSTRAINT metadata_pkey PRIMARY KEY (metadata_id)
);


/*
 * checksum_table
 * --------------
 * Function that returns a checksum value for a given tablename. 
 * Used by functions that populate the checksum in the metadata table, allowing table content comparisons between databases in different locations.
 * @param v_tablename The table name for which the checksum should be generated.
 */
CREATE OR REPLACE FUNCTION system.checksum_table(v_tablename text)
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
	v_checksum := system.checksum_table(tablename::text);
	RAISE NOTICE '% Insert imported file in metadata table @ %', tablename, timeofday();
	
	EXECUTE format(
			'DO $$ 
			BEGIN 
				INSERT INTO system.metadata (tablename, filename, checksum_before, checksum, timestamp) 
					VALUES (
						''%s'',
						SPLIT_PART(''%s'', ''/'', -1),
						%L,
						%L,
						clock_timestamp()::timestamp); 
			END 
			$$',
			tablename, filename, checksum_before, v_checksum
	);
END;
$BODY$
LANGUAGE plpgsql VOLATILE;
