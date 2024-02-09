/*
 * db_checksum_all
 * ---------------
 * Function to generate checksums for all important database objects.
 * In the case of tables, a separate checksum is made for the structure and the data.
 * For the data checksums some tables can be skipped, for example when the content is dynamic and it does not make sense to check/compare checksums.
 *
 * The (sorted) result of the function can be saved to compare it with another database.
 * For example after patching a production database, to check if it matches the last build.
 *
 * Catalog objects and objects of extensions like PostGIS are automatically filtered out.
 *
 * @param v_excluded_data_tables List of tables for which no data checksum should be generated.
 * @return Per object type a name or description of the object, and the checksum of the definiton/data of that object
 */
CREATE OR REPLACE FUNCTION system.db_checksum_all(v_excluded_data_tables regclass[] = NULL)
	RETURNS TABLE(objecttype text, description text, checksum bigint) AS
$BODY$
DECLARE
	data_table regclass;
	noncatalog_objects oid[];
	extension_objects oid[];
BEGIN
	noncatalog_objects := (SELECT array_agg(objid) || array_agg(DISTINCT pg_namespace.oid) FROM pg_depend INNER JOIN pg_namespace ON (refobjid = pg_namespace.oid) WHERE pg_namespace.oid <> pg_my_temp_schema() AND NOT pg_is_other_temp_schema(pg_namespace.oid) AND NOT nspname IN ('information_schema', 'pg_catalog', 'pg_toast'));
	extension_objects := (SELECT array_agg(objid) || array_agg(DISTINCT pg_extension.oid) FROM pg_depend INNER JOIN pg_extension ON (refobjid = pg_extension.oid));

	-- Loop all non-catalog non-temporary tables in the database, except for the tables in the given array parameter.
	-- For each table, stringify the contents, hash it and return it.
	FOR data_table IN
		SELECT pg_class.oid::regclass
			FROM pg_class
			WHERE
				relkind = 'r'
				AND NOT pg_class.oid::regclass = ANY(COALESCE(v_excluded_data_tables, ARRAY[]::regclass[]))
				AND pg_class.oid = ANY(noncatalog_objects)
				AND NOT pg_class.oid = ANY(extension_objects)
	LOOP
		RETURN QUERY EXECUTE $$ SELECT 'table data'::text, $1::text, COALESCE(SUM(hashtext((tbl.*)::text)), 0) AS checksum FROM $$ || data_table || $$ AS tbl $$ USING data_table;
	END LOOP;

	-- Generate checksums for the entire database structure. The query hashes the definitions of tables, views, functions, aggregate functions,
	-- triggers, constraints and indexes. This type is returned as well as a description, which may sometimes be the same as the definition that
	-- was hashed.
	-- Again applies only to non-catalog non-temporary objects. Also the PostGIS functions prefixed with ST_ are filtered out.
	RETURN QUERY SELECT
		objtype::text AS objecttype,
		COALESCE(objdescription, objdefinition)::text AS objdescription,
		hashtext(objdefinition)::bigint AS checksum

		FROM (
			SELECT
				objtype,
				regexp_replace(objdescription, '[\n\r]+', ' ', 'g' ) AS objdescription,
				regexp_replace(objdefinition, '[\n\r]+', ' ', 'g' ) AS objdefinition

				FROM
					(SELECT
						'table structure' AS objtype,
						NULL AS objdescription,
						format('%s.%s (%s,%s,%s,%s,%s,%s)', pg_class.oid::regclass, attname, typname, attlen, attnum, attnotnull, atthasdef, pg_get_expr(adbin, pg_class.oid)) AS objdefinition

						FROM pg_attribute
							INNER JOIN pg_type ON (atttypid = pg_type.oid)
							INNER JOIN pg_class ON (attrelid = pg_class.oid)
							LEFT JOIN pg_attrdef ON (adrelid = attrelid AND adnum = attnum)

						WHERE
							relkind = 'r'
							AND relpersistence <> 't'
							AND attnum > 0
							AND pg_class.oid = ANY(noncatalog_objects)
							AND NOT pg_class.oid = ANY(extension_objects)
					UNION ALL
					SELECT
						'view' AS objtype,
						pg_class.oid::regclass::text AS objdescription,
						pg_get_viewdef(pg_class.oid) AS objdefinition

						FROM pg_class

						WHERE
							relkind = 'v'
							AND pg_class.oid = ANY(noncatalog_objects)
							AND NOT pg_class.oid = ANY(extension_objects)
					UNION ALL
					SELECT
						'function' AS objtype,
						format('%s(%s) RETURNS %s', pg_proc.oid::regproc, pg_get_function_arguments(pg_proc.oid), pg_get_function_result(pg_proc.oid)) AS objdescription,
						pg_get_functiondef(pg_proc.oid) AS objdefinition

						FROM pg_proc

						WHERE
							pg_proc.oid NOT IN (SELECT aggfnoid FROM pg_aggregate)
							AND pg_proc.oid = ANY(noncatalog_objects)
							AND NOT pg_proc.oid = ANY(extension_objects)
					UNION ALL
					SELECT
						'aggregate function' AS objtype,
						NULL AS objdescription,
						format('%s (%s, %s)', pg_proc.oid::regproc, aggtransfn, aggfinalfn) AS objdefinition

						FROM pg_aggregate
							INNER JOIN pg_proc ON (aggfnoid = pg_proc.oid)

						WHERE
							pg_proc.oid = ANY(noncatalog_objects)
							AND NOT pg_proc.oid = ANY(extension_objects)
					UNION ALL
					SELECT
						'trigger' AS objtype,
						NULL AS objdescription,
						pg_get_triggerdef(pg_trigger.oid) AS objdefinition

						FROM pg_trigger
							INNER JOIN pg_class ON (tgrelid = pg_class.oid)

						WHERE
							NOT tgisinternal
							AND pg_class.oid = ANY(noncatalog_objects)
							AND NOT pg_class.oid = ANY(extension_objects)
					UNION ALL
					SELECT
						'constraint' AS objtype,
						NULL AS objdescription,
						format('%s.%s = %s', pg_class.oid::regclass, conname, pg_get_constraintdef(pg_constraint.oid)) AS objdefinition

						FROM pg_constraint
							INNER JOIN pg_class ON (conrelid = pg_class.oid)

						WHERE
							pg_class.oid = ANY(noncatalog_objects)
							AND NOT pg_class.oid = ANY(extension_objects)
					UNION ALL
					SELECT
						'index' AS objtype,
						NULL AS objdescription,
						pg_get_indexdef(pg_class_index.oid) AS objdefinition

						FROM pg_index
							INNER JOIN pg_class AS pg_class_index ON (indexrelid = pg_class_index.oid)
							INNER JOIN pg_class AS pg_class_table ON (indrelid = pg_class_table.oid)

						WHERE
							pg_class_table.relkind IN ('r', 'm')
							AND pg_class_index.relkind = 'i'
							AND pg_class_table.oid = ANY(noncatalog_objects)
							AND NOT pg_class_table.oid = ANY(extension_objects)
					UNION ALL
		 			SELECT
						'type' AS objtype,
						NULL AS objdescription,
						format('%s (%s,%s,%s,%s,%s,%s,%s,%s)', pg_type.oid::regtype, typlen, typtype, typcategory, typnotnull, pg_class.relname, format_type(typarray, NULL), format_type(typbasetype, NULL), typndims) AS objdefinition

						FROM pg_type
							LEFT JOIN pg_class ON (typrelid = pg_class.oid)

						WHERE
							typisdefined
							AND typelem = 0
							AND (relkind IS NULL OR relkind = 'c')
							AND pg_type.oid = ANY(noncatalog_objects)
							AND NOT pg_type.oid = ANY(extension_objects)
					UNION ALL
					SELECT
						'enum values' AS objtype,
						NULL AS objdescription,
						format('%s (%s)', pg_type.oid::regtype, array_to_string(array_agg(enumlabel::text), ',')) AS objdefinition

						FROM (SELECT * FROM pg_enum ORDER BY enumtypid, enumsortorder) AS pg_enum
							INNER JOIN pg_type ON (enumtypid = pg_type.oid)

						WHERE
							pg_type.oid = ANY(noncatalog_objects)
							AND NOT pg_type.oid = ANY(extension_objects)

						GROUP BY pg_type.oid
					UNION ALL
					SELECT
						'cast' AS objtype,
						NULL AS objdescription,
						format('%s AS %s (%s,%s,%s)', format_type(castsource, NULL), format_type(casttarget, NULL), castfunc::regproc, castcontext, castmethod) AS objdefinition

						FROM pg_cast
							INNER JOIN pg_type AS pg_type_src ON (castsource = pg_type_src.oid)

						WHERE
							pg_type_src.oid = ANY(noncatalog_objects)
							AND NOT pg_type_src.oid = ANY(extension_objects)
					UNION ALL
					SELECT
						'cast' AS objtype,
						NULL AS objdescription,
						format('%s AS %s (%s,%s,%s)', format_type(castsource, NULL), format_type(casttarget, NULL), castfunc::regproc, castcontext, castmethod) AS objdefinition

						FROM pg_cast
							INNER JOIN pg_type AS pg_type_src ON (castsource = pg_type_src.oid)
							INNER JOIN pg_type AS pg_type_tgt ON (casttarget = pg_type_tgt.oid)

						WHERE
							pg_type_tgt.oid = ANY(noncatalog_objects)
							AND NOT pg_type_tgt.oid = ANY(extension_objects)
							AND NOT (pg_type_src.oid = ANY(noncatalog_objects) AND NOT pg_type_src.oid = ANY(extension_objects))
					UNION ALL
					SELECT
						'comment' AS objtype,
						pg_describe_object(classoid, objoid, objsubid) AS objdescription,
						pg_description.description AS objdefinition

						FROM pg_description

						WHERE
							objsubid = 0
							AND objoid = ANY(noncatalog_objects)
							AND NOT objoid = ANY(extension_objects)
				) AS raw_definitions

		) AS definitions
	;

	RETURN;
END;
$BODY$
LANGUAGE plpgsql STABLE;
