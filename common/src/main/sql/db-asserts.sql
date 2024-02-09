/*
 * db_assert_equals
 * ----------------
 * Function to assert that the 2 supplied values match. Handles NULL values as expected (non-NULL and NULL values are not equal).
 * The supplied values should be of the same data type.
 */
CREATE OR REPLACE FUNCTION system.db_assert_equals(v_expected anyelement, v_actual anyelement, v_message text = NULL)
	RETURNS void AS
$BODY$
BEGIN
	IF v_actual IS DISTINCT FROM v_expected THEN
		RAISE EXCEPTION 'assert_equals: expected=% actual=% %', v_expected, v_actual, COALESCE('[' || v_message || ']', '');
	END IF;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;


/*
 * db_assert_differs
 * -----------------
 * Function to assert that the 2 supplied values do NOT match. Handles NULL values as expected (non-NULL and NULL values are not equal).
 * The supplied values should be of the same data type.
 */
CREATE OR REPLACE FUNCTION system.db_assert_differs(v_not_allowed anyelement, v_actual anyelement, v_message text = NULL)
	RETURNS void AS
$BODY$
BEGIN
	IF v_actual IS NOT DISTINCT FROM v_not_allowed THEN
		RAISE EXCEPTION 'assert_differs: not allowed=% actual=% %', v_not_allowed, v_actual, COALESCE('[' || v_message || ']', '');
	END IF;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;


/*
 * db_assert_true
 * --------------
 * Function to assert that the supplied condition is true.
 *
 * This assertion is useful for different types of checks, for example to confirm that a query returns at least 1 record:
 *	PERFORM * FROM some_table WHERE id = 123;
 *	PERFORM system.db_assert_true(FOUND);
 *
 * Or use one of the subquery expressions:
 * 	PERFORM system.db_assert_true(EXISTS(SELECT * FROM some_table WHERE id = 123));
 * More on: https://www.postgresql.org/docs/current/static/functions-subquery.html
 */
CREATE OR REPLACE FUNCTION system.db_assert_true(v_condition boolean, v_message text = NULL)
	RETURNS void AS
$BODY$
BEGIN
	IF v_condition IS NOT TRUE THEN
		RAISE EXCEPTION 'assert_true: condition=% %', v_condition, COALESCE('[' || v_message || ']', '');
	END IF;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;


/*
 * db_assert_false
 * ---------------
 * Function to assert that the supplied condition is false. Note: NULL is not considered the same as false.
 */
CREATE OR REPLACE FUNCTION system.db_assert_false(v_condition boolean, v_message text = NULL)
	RETURNS void AS
$BODY$
BEGIN
	IF v_condition IS NOT FALSE THEN
		RAISE EXCEPTION 'assert_false: condition=% %', v_condition, COALESCE('[' || v_message || ']', '');
	END IF;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;


/*
 * db_assert_not_null
 * ------------------
 * Function to assert that the supplied value is not NULL.
 */
CREATE OR REPLACE FUNCTION system.db_assert_not_null(v_value anyelement, v_message text = NULL)
	RETURNS void AS
$BODY$
BEGIN
	IF v_value IS NULL THEN
		RAISE EXCEPTION 'assert_not_null: value=% %', v_value, COALESCE('[' || v_message || ']', '');
	END IF;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;


/*
 * db_assert_null
 * --------------
 * Function to assert that the supplied value is NULL.
 */
CREATE OR REPLACE FUNCTION system.db_assert_null(v_value anyelement, v_message text = NULL)
	RETURNS void AS
$BODY$
BEGIN
	IF v_value IS NOT NULL THEN
		RAISE EXCEPTION 'assert_null: value=% %', v_value, COALESCE('[' || v_message || ']', '');
	END IF;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;
