/*
 * synchronize_all_serials
 * -----------------------
 * Function to synchronize serials/sequences.
 * All functions with naming convention tablename_columnname_seq are set to the max value of that column in that table.
 *
 * Serials/sequences can get out of sync with the actual content of the database after bulk loads, COPY FROMs and INSERTs without defaults.
 * This function makes sure sequences match the content once again.
 * This is for instance used after a database build.
 */
CREATE OR REPLACE FUNCTION system.synchronize_all_serials()
	RETURNS void AS
$BODY$
DECLARE
	sequences record;
	sql text;
BEGIN
	FOR sequences IN
		SELECT
			seqs.sequence_schema || '.' || seqs.sequence_name AS sequence_name,
			cols.table_schema || '.' || cols.table_name::text AS table_name,
			cols.column_name::text

			FROM information_schema.columns AS cols
				INNER JOIN information_schema.sequences AS seqs
					ON ( (cols.table_schema || '.' || cols.table_name || '_' || cols.column_name || '_seq') = (seqs.sequence_schema || '.' || seqs.sequence_name) )
	LOOP
		sql := 'SELECT SETVAL(''' || sequences.sequence_name || ''', (SELECT COALESCE(MAX(' || sequences.column_name || '), 0) FROM ' || sequences.table_name || ') + 1, false)';
		RAISE NOTICE '%', sql;
		EXECUTE sql;
	END LOOP;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;


/*
 * cluster_all_tables
 * ------------------
 * Function to cluster all tables in the database based on their primary key.
 * Once the constraint (in this case the primary key) has been set, in the future clustering can be done by using: CLUSTER databasname.
 */
CREATE OR REPLACE FUNCTION system.cluster_all_tables()
	RETURNS void AS
$BODY$
DECLARE
	pkey_constraints record;
	sql text;
BEGIN
	FOR pkey_constraints IN
		SELECT
			(nspname || '.' || relname)::regclass::text AS tablename,
			conname::text AS pkey_name

			FROM pg_constraint
				INNER JOIN pg_class ON (pg_class.oid = pg_constraint.conrelid)
				INNER JOIN pg_namespace ON (pg_namespace.oid = pg_class.relnamespace)

			WHERE pg_class.relkind = 'r' AND pg_constraint.contype = 'p' AND pg_class.relisshared IS FALSE AND relname NOT LIKE 'pg_%'

			ORDER BY tablename
	LOOP
		sql := 'CLUSTER ' || pkey_constraints.tablename || ' USING ' || pkey_constraints.pkey_name;
		RAISE NOTICE '%', sql;
		EXECUTE sql;
	END LOOP;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;
