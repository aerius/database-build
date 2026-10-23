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
 * Once the constraint (in this case the primary key) has been set, in the future clustering can be done by using: CLUSTER databasename.
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


/*
 * drop_foreign_keys_before_load
 * -----------------------------
 * Function to drop the foreign keys before the data is loaded, so system.add_foreign_keys_after_load can add them back after the load.
 * While a table is loaded, a foreign key is checked row by row. Adding the key back to the filled table checks all rows in one pass.
 * The dropped keys are stored in system.dropped_foreign_keys. This is a normal table and not a temporary one, because the build script runs each call in a new session.
 * Some foreign keys are left in place:
 * - Keys with an ON UPDATE or ON DELETE action, as the load could rely on that action.
 * - NOT VALID keys, as adding one back would not check the loaded rows.
 * - The copies of a key on each partition, as they follow the key on the parent table.
 *
 * Called during build by ruby build script, when load_data is given :foreign_keys_after_load.
 */
CREATE OR REPLACE FUNCTION system.drop_foreign_keys_before_load()
	RETURNS void AS
$BODY$
DECLARE
	foreign_keys record;
	sql text;
BEGIN
	CREATE TABLE system.dropped_foreign_keys (
		tablename text NOT NULL,
		constraintname text NOT NULL,
		definition text NOT NULL
	);

	INSERT INTO system.dropped_foreign_keys (tablename, constraintname, definition)
		SELECT
			conrelid::regclass::text,
			conname,
			pg_get_constraintdef(oid)

			FROM pg_constraint

			WHERE contype = 'f' AND conparentid = 0 AND convalidated AND confupdtype IN ('a', 'r') AND confdeltype IN ('a', 'r')
	;

	FOR foreign_keys IN
		SELECT
			tablename,
			constraintname

			FROM system.dropped_foreign_keys

			ORDER BY tablename, constraintname
	LOOP
		sql := 'ALTER TABLE ' || foreign_keys.tablename || ' DROP CONSTRAINT ' || quote_ident(foreign_keys.constraintname);
		RAISE NOTICE '%', sql;
		EXECUTE sql;
	END LOOP;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;


/*
 * add_foreign_keys_after_load
 * ---------------------------
 * Function to add back the foreign keys that system.drop_foreign_keys_before_load dropped, and to drop system.dropped_foreign_keys.
 * Adding a key checks all rows, so bad data still fails the build, with the usual error that names the table, the key and the value.
 *
 * Called during build by ruby build script, when load_data is given :foreign_keys_after_load.
 */
CREATE OR REPLACE FUNCTION system.add_foreign_keys_after_load()
	RETURNS void AS
$BODY$
DECLARE
	foreign_keys record;
	sql text;
BEGIN
	FOR foreign_keys IN
		SELECT
			tablename,
			constraintname,
			definition

			FROM system.dropped_foreign_keys

			ORDER BY tablename, constraintname
	LOOP
		sql := 'ALTER TABLE ' || foreign_keys.tablename || ' ADD CONSTRAINT ' || quote_ident(foreign_keys.constraintname) || ' ' || foreign_keys.definition;
		RAISE NOTICE '%', sql;
		EXECUTE sql;
	END LOOP;

	DROP TABLE system.dropped_foreign_keys;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;
