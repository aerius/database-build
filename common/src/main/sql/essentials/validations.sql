/*
 * validation_result_type
 * ----------------------
 * Enum type for the different validation results.
 * The order of this enum is important, and runs from low to high.
 */
CREATE TYPE system.validation_result_type AS ENUM
	('success', 'hint', 'warning', 'error');


/*
 * validation_result
 * -----------------
 * Type used as a return type for validation results.
 */
CREATE TYPE system.validation_result AS (
	result system.validation_result_type,
	object text,
	message text
);


/*
 * db_validate_all
 * ---------------
 * Empty (default) db_validate_all function.
 *
 * Called during build by ruby build script.
 * Can be overwritten by each product to perform some actual validations.
 */
CREATE OR REPLACE FUNCTION system.db_validate_all()
	RETURNS TABLE (validaton_result_id integer, validation_run_id integer, name regproc, result system.validation_result_type) AS
$BODY$
BEGIN
	RAISE NOTICE '** Empty validating function...';

	RETURN;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;
