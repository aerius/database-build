/*
 * ae_checksum_included_objects
 * ----------------------------
 * Helper function for ae_checksum_all, returning all database objects that should be included in the checksums.
 *
 * System catalog objects and objects of extensions like PostGIS are automatically filtered out.
 * This is determined using pg_depend: an object is included when it depends on a non-system non-temporary schema
 * and is not a member of an extension. The (non-system non-temporary) schemas themselves are included as well.
 * Objects should always be matched on both their class ID (or catalog) and object ID, as object IDs are only unique within a single system catalog.
 *
 * @return The class ID (as regclass) and object ID (as oid) of each included object.
 */
CREATE OR REPLACE FUNCTION ae_checksum_included_objects()
	RETURNS TABLE(classid regclass, objid oid) AS
$BODY$
	WITH target_schemas AS (
		-- Interesting schemas for checksumming are those not internal to postgres.
		SELECT
			'pg_namespace'::regclass AS classid,
			pg_namespace.oid AS objid

			FROM pg_namespace

			WHERE
				NOT pg_namespace.nspname = 'information_schema'
				AND NOT pg_namespace.nspname ilike 'pg_%'
	), target_objects AS (
		-- Objects that are interesting to checksum are those related to interesting schemas, including the schemas themselves.
		-- This does not cover indirect dependencies like indices and constraints. Those will for example have to be retrieved based on the table.
		SELECT
			pg_depend.classid::regclass,
			pg_depend.objid

			FROM pg_depend
				INNER JOIN target_schemas ON (pg_depend.refclassid = target_schemas.classid AND pg_depend.refobjid = target_schemas.objid)
		UNION
		SELECT
			classid,
			objid

			FROM target_schemas
	), extension_depend AS (
		-- Filter out any object that is related to an extension.
		SELECT
			classid,
			objid

			FROM pg_depend

			WHERE
				refclassid = 'pg_extension'::regclass
				AND deptype = 'e'
	)
	SELECT
		target_objects.classid,
		target_objects.objid

		FROM target_objects
			LEFT JOIN extension_depend USING (classid, objid)

		WHERE
			extension_depend.objid IS NULL
			AND target_objects.classid <> 'pg_extension'::regclass
	;
$BODY$
LANGUAGE sql STABLE;


/*
 * ae_checksum_hash
 * ----------------
 * Helper function for ae_checksum_all, returning a numeric hash of the given text.
 * Having this in a separate function makes it easy to change the hash algorithm in a single place.
 *
 * @param v_value The text to hash.
 * @return The hash, or NULL if the given text is NULL.
 */
CREATE OR REPLACE FUNCTION ae_checksum_hash(v_value text)
	RETURNS integer AS
$BODY$
	SELECT hashtext(v_value);
$BODY$
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;


/*
 * ae_checksum_all
 * ---------------
 * Function to generate checksums for all important database objects.
 * In the case of tables, a separate checksum is made for the structure and the data.
 * For the data checksums some tables can be skipped, for example when the content is dynamic and it does not make sense to check/compare checksums.
 *
 * The (sorted) result of the function can be saved to compare it with another database.
 * For example after patching a production database, to check if it matches the last build.
 *
 * System catalog objects and objects of extensions like PostGIS are automatically filtered out, see ae_checksum_included_objects.
 *
 * The checksums are generated using ae_checksum_hash.
 * For table data the hashes of the individual rows are summed, so the checksum does not depend on the row order.
 * 
 * Note: running the checksum method might result in different results when using a different client (difference in timezone, datestyle, etc).
 *
 * @param v_excluded_data_tables List of tables for which no data checksum should be generated.
 * @return Per object type a name or description of the object, and the checksum of the definition/data of that object
 */
CREATE OR REPLACE FUNCTION ae_checksum_all(v_excluded_data_tables regclass[] = NULL)
	RETURNS TABLE(objecttype text, description text, checksum bigint) AS
$BODY$
DECLARE
	data_table regclass;
BEGIN
	-- Loop all non-system non-temporary tables in the database, except for the tables in the given array parameter.
	-- For each table, stringify the contents, hash it and return it.
	FOR data_table IN
		SELECT pg_class.oid::regclass
			FROM pg_class
				INNER JOIN ae_checksum_included_objects() AS included_objects ON (included_objects.classid = 'pg_class'::regclass AND included_objects.objid = pg_class.oid)
			WHERE
				pg_class.relkind = 'r'
				AND NOT pg_class.oid::regclass = ANY(COALESCE(v_excluded_data_tables, ARRAY[]::regclass[]))
			ORDER BY pg_class.oid::regclass::text
	LOOP
		RETURN QUERY EXECUTE $$ SELECT 'table data'::text, $1::text, COALESCE(SUM(ae_checksum_hash((tbl.*)::text)), 0)::bigint AS checksum FROM $$ || data_table || $$ AS tbl $$ USING data_table;
	END LOOP;

	-- Generate checksums for the entire database structure.
	-- Do not ignore the excluded data tables for this part, as we still want to check their structure.
	RETURN QUERY
	WITH included_objects AS (
		SELECT helper.classid, helper.objid FROM ae_checksum_included_objects() AS helper
	), table_structures AS (
		SELECT
			'table structure' AS objtype,
			NULL AS objdescription,
			format('%s.%s (%s,%s,%s,%s,%s,%s)', pg_class.oid::regclass, attname, format_type(atttypid, atttypmod), attlen, attnum, attnotnull, atthasdef, pg_get_expr(adbin, pg_class.oid)) AS objdefinition

			FROM pg_attribute
				INNER JOIN pg_type ON (atttypid = pg_type.oid)
				INNER JOIN pg_class ON (attrelid = pg_class.oid)
				INNER JOIN included_objects ON (included_objects.classid = 'pg_class'::regclass AND included_objects.objid = pg_class.oid)
				LEFT JOIN pg_attrdef ON (adrelid = attrelid AND adnum = attnum)

			WHERE
				relkind = 'r'
				AND relpersistence <> 't'
				AND attnum > 0
	), views AS (
		SELECT
			'view' AS objtype,
			pg_class.oid::regclass::text AS objdescription,
			pg_get_viewdef(pg_class.oid) AS objdefinition

			FROM pg_class
				INNER JOIN included_objects ON (included_objects.classid = 'pg_class'::regclass AND included_objects.objid = pg_class.oid)

			WHERE
				relkind = 'v'
	), materialized_views AS (
		SELECT
			'materialized view' AS objtype,
			pg_class.oid::regclass::text AS objdescription,
			pg_get_viewdef(pg_class.oid) AS objdefinition

			FROM pg_class
				INNER JOIN included_objects ON (included_objects.classid = 'pg_class'::regclass AND included_objects.objid = pg_class.oid)

			WHERE
				relkind = 'm'
	), functions AS (
		SELECT
			'function' AS objtype,
			format('%s(%s) RETURNS %s', pg_proc.oid::regproc, pg_get_function_arguments(pg_proc.oid), pg_get_function_result(pg_proc.oid)) AS objdescription,
			pg_get_functiondef(pg_proc.oid) AS objdefinition

			FROM pg_proc
				INNER JOIN included_objects ON (included_objects.classid = 'pg_proc'::regclass AND included_objects.objid = pg_proc.oid)

			WHERE
				pg_proc.oid NOT IN (SELECT aggfnoid FROM pg_aggregate)
	), aggregate_functions AS (
		SELECT
			'aggregate function' AS objtype,
			NULL AS objdescription,
			format('%s (%s, %s)', pg_proc.oid::regproc, aggtransfn, aggfinalfn) AS objdefinition

			FROM pg_aggregate
				INNER JOIN pg_proc ON (aggfnoid = pg_proc.oid)
				INNER JOIN included_objects ON (included_objects.classid = 'pg_proc'::regclass AND included_objects.objid = pg_proc.oid)
	), triggers AS (
		SELECT
			'trigger' AS objtype,
			NULL AS objdescription,
			pg_get_triggerdef(pg_trigger.oid) AS objdefinition

			FROM
				(SELECT DISTINCT
					pg_depend.objid,
					pg_depend.refobjid

					FROM pg_depend

					WHERE
						pg_depend.classid = 'pg_trigger'::regclass
						AND pg_depend.refclassid = 'pg_class'::regclass
						AND pg_depend.deptype = 'a'
				) AS trigger_depend
				INNER JOIN pg_trigger ON (trigger_depend.objid = pg_trigger.oid AND trigger_depend.refobjid = pg_trigger.tgrelid)
				INNER JOIN included_objects ON (included_objects.classid = 'pg_class'::regclass AND included_objects.objid = trigger_depend.refobjid)

			WHERE
				NOT tgisinternal
	), constraints AS (
		SELECT
			'constraint' AS objtype,
			NULL AS objdescription,
			format('%s.%s = %s',
				CASE
					WHEN constraint_depend.refclassid = 'pg_class'::regclass THEN constraint_depend.refobjid::regclass::text
					ELSE constraint_depend.refobjid::regtype::text
				END,
				conname,
				pg_get_constraintdef(pg_constraint.oid)) AS objdefinition

			FROM
				(SELECT DISTINCT
					pg_depend.objid,
					pg_depend.refclassid,
					pg_depend.refobjid

					FROM pg_depend

					WHERE
						pg_depend.classid = 'pg_constraint'::regclass
						AND pg_depend.refclassid IN ('pg_class'::regclass, 'pg_type'::regclass)
						AND pg_depend.deptype = 'a'
				) AS constraint_depend
				INNER JOIN pg_constraint ON (
					constraint_depend.objid = pg_constraint.oid
					AND ((constraint_depend.refclassid = 'pg_class'::regclass AND constraint_depend.refobjid = pg_constraint.conrelid)
						OR (constraint_depend.refclassid = 'pg_type'::regclass AND constraint_depend.refobjid = pg_constraint.contypid)))
				INNER JOIN included_objects ON (included_objects.classid = constraint_depend.refclassid AND included_objects.objid = constraint_depend.refobjid)
	), indices AS (
		SELECT
			'index' AS objtype,
			NULL AS objdescription,
			pg_get_indexdef(pg_class_index.oid) AS objdefinition

			FROM pg_index
				INNER JOIN pg_class AS pg_class_index ON (indexrelid = pg_class_index.oid)
				INNER JOIN pg_class AS pg_class_table ON (indrelid = pg_class_table.oid)
				INNER JOIN included_objects ON (included_objects.classid = 'pg_class'::regclass AND included_objects.objid = pg_class_table.oid)

			WHERE
				pg_class_table.relkind IN ('r', 'm')
				AND pg_class_index.relkind IN ('i', 'I')
	), types AS (
		SELECT
			'type' AS objtype,
			NULL AS objdescription,
			format('%s (%s,%s,%s,%s,%s,%s,%s,%s)', pg_type.oid::regtype, typlen, typtype, typcategory, typnotnull, pg_class.relname, format_type(typarray, NULL), format_type(typbasetype, NULL), typndims) AS objdefinition

			FROM pg_type
				INNER JOIN included_objects ON (included_objects.classid = 'pg_type'::regclass AND included_objects.objid = pg_type.oid)
				LEFT JOIN pg_class ON (typrelid = pg_class.oid)

			WHERE
				typisdefined
				AND typelem = 0
				AND (relkind IS NULL OR relkind = 'c')
	), enum_values AS (
		SELECT
			'enum values' AS objtype,
			NULL AS objdescription,
			format('%s (%s)', pg_type.oid::regtype, array_to_string(array_agg(enumlabel::text ORDER BY enumsortorder), ',')) AS objdefinition

			FROM pg_enum
				INNER JOIN pg_type ON (enumtypid = pg_type.oid)
				INNER JOIN included_objects ON (included_objects.classid = 'pg_type'::regclass AND included_objects.objid = pg_type.oid)

			GROUP BY pg_type.oid
	), casts AS (
		SELECT
			'cast' AS objtype,
			NULL AS objdescription,
			format('%s AS %s (%s,%s,%s)', format_type(castsource, NULL), format_type(casttarget, NULL), castfunc::regproc, castcontext, castmethod) AS objdefinition

			FROM pg_cast
				INNER JOIN pg_type AS pg_type_src ON (castsource = pg_type_src.oid)
				INNER JOIN included_objects ON (included_objects.classid = 'pg_type'::regclass AND included_objects.objid = pg_type_src.oid)
		UNION ALL
		SELECT
			'cast' AS objtype,
			NULL AS objdescription,
			format('%s AS %s (%s,%s,%s)', format_type(castsource, NULL), format_type(casttarget, NULL), castfunc::regproc, castcontext, castmethod) AS objdefinition

			FROM pg_cast
				INNER JOIN pg_type AS pg_type_src ON (castsource = pg_type_src.oid)
				INNER JOIN pg_type AS pg_type_tgt ON (casttarget = pg_type_tgt.oid)
				INNER JOIN included_objects AS included_objects_tgt ON (included_objects_tgt.classid = 'pg_type'::regclass AND included_objects_tgt.objid = pg_type_tgt.oid)
				LEFT JOIN included_objects AS included_objects_src ON (included_objects_src.classid = 'pg_type'::regclass AND included_objects_src.objid = pg_type_src.oid)

			WHERE
				included_objects_src.objid IS NULL
	), comments AS (
		SELECT
			'comment' AS objtype,
			pg_describe_object(classoid, objoid, objsubid) AS objdescription,
			pg_description.description AS objdefinition

			FROM pg_description
				INNER JOIN included_objects ON (included_objects.classid = pg_description.classoid AND included_objects.objid = pg_description.objoid)

			WHERE
				objsubid = 0
	)
	SELECT
		objtype::text AS objecttype,
		COALESCE(objdescription, objdefinition)::text AS objdescription,
		ae_checksum_hash(objdefinition)::bigint AS checksum

		FROM (
			SELECT
				objtype,
				regexp_replace(objdescription, '[\n\r]+', ' ', 'g' ) AS objdescription,
				regexp_replace(objdefinition, '[\n\r]+', ' ', 'g' ) AS objdefinition

				FROM
					(SELECT * FROM table_structures
					UNION ALL
					SELECT * FROM views
					UNION ALL
					SELECT * FROM materialized_views
					UNION ALL
					SELECT * FROM functions
					UNION ALL
					SELECT * FROM aggregate_functions
					UNION ALL
					SELECT * FROM triggers
					UNION ALL
					SELECT * FROM constraints
					UNION ALL
					SELECT * FROM indices
					UNION ALL
					SELECT * FROM types
					UNION ALL
					SELECT * FROM enum_values
					UNION ALL
					SELECT * FROM casts
					UNION ALL
					SELECT * FROM comments
				) AS raw_definitions
		) AS definitions

		ORDER BY
			objtype::text,
			COALESCE(objdescription, objdefinition)::text
	;

	RETURN;
END;
$BODY$
LANGUAGE plpgsql STABLE;
