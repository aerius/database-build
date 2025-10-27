--------------------------------------------------------
-- Interpolate functions -------------------------------
--------------------------------------------------------

/*
 * linear_interpolate
 * ------------------
 * Linear interpolation function.
 *
 * xb, yb = Start point
 * xe, ye = End point
 * xi = the x value to interpolate the y value for.
 * Expects a float for each value, and returns a float.
 */
CREATE OR REPLACE FUNCTION system.linear_interpolate(xb float, xe float, yb float, ye float, xi float)
	RETURNS float AS
$BODY$
DECLARE
BEGIN
	IF xe - xb = 0 THEN
		RETURN yb;
	ELSE
		RETURN yb + ( (xi - xb) / (xe - xb) ) * (ye - yb);
	END IF;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;


/*
 * linear_interpolate
 * ------------------
 * Linear interpolation function.
 *
 * xb, yb = Start point
 * xe, ye = End point
 * xi = the x value to interpolate the y value for.
 * Expects integer values for xb,xe and xi.
 * Expects real values for yb and ye.
 * Returns a real value.
 */
CREATE OR REPLACE FUNCTION system.linear_interpolate(xb integer, xe integer, yb real, ye real, xi integer)
	RETURNS real AS
$BODY$
DECLARE
BEGIN
	IF xe - xb = 0 THEN
		RETURN yb;
	ELSE
		RETURN yb + ( (xi - xb)::real / (xe - xb) ) * (ye - yb);
	END IF;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;


/*
 * linear_interpolate
 * ------------------
 * Linear interpolation function.
 *
 * xb, yb = Start point
 * xe, ye = End point
 * xi = the x value to interpolate the y value for.
 * Expects integer values for xb,xe and xi.
 * Expects numeric values for yb and ye.
 * Returns a numeric value.
 */
CREATE OR REPLACE FUNCTION system.linear_interpolate(xb integer, xe integer, yb numeric, ye numeric, xi integer)
	RETURNS numeric AS
$BODY$
DECLARE
BEGIN
	IF xe - xb = 0 THEN
		RETURN yb;
	ELSE
		RETURN yb + ( (xi - xb)::numeric / (xe - xb) ) * (ye - yb);
	END IF;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;


--------------------------------------------------------
-- Percentile functions --------------------------------
--------------------------------------------------------

/*
 * percentile_sorted_array
 * -----------------------
 * Function to calculate the percentile based on a sorted array.
 */
CREATE OR REPLACE FUNCTION system.percentile_sorted_array(sorted_array numeric[], percentile int)
	RETURNS numeric AS
$BODY$
DECLARE
	array_size 		int;
	index 			int;
	percentile_by_index 	numeric;
BEGIN
	IF array_length(sorted_array, 1) IS NULL THEN -- No empty arrays
		RETURN NULL;
	END IF;

	array_size = array_length(sorted_array, 1);
	index = FLOOR( (array_size - 1) * percentile / 100.0) + 1;

	-- an array of n elements starts with array[1] and ends with array[n].
	IF index >= array_size THEN
		RETURN sorted_array[array_size];

	ELSE
		percentile_by_index = (index - 1) * 100.0 / (array_size - 1);

		RETURN sorted_array[index] + (array_size - 1) *
				((percentile - percentile_by_index) / 100.0) *
				(sorted_array[index + 1] - sorted_array[index]);

	END IF;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE RETURNS NULL ON NULL INPUT;


/*
 * percentile
 * ----------
 * Function to calculate the percentile based on an unsorted list.
 * Remark: there is no aggregate version of this function due to very bad performance.
 */
CREATE OR REPLACE FUNCTION system.percentile(unsorted_array numeric[], percentile int)
	RETURNS numeric AS
$BODY$
BEGIN
	RETURN system.percentile_sorted_array((SELECT array_agg(v) FROM (SELECT v FROM unnest(unsorted_array) AS v WHERE v IS NOT NULL ORDER BY 1) AS t), percentile);
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE RETURNS NULL ON NULL INPUT;


/*
 * median
 * ------
 * Function to calculate the median based on an unsorted list. Identical to 50% percentile.
 * Remark: there is no aggregate version of this function due to very bad performance.
 */
CREATE OR REPLACE FUNCTION system.median(unsorted_array numeric[])
	RETURNS numeric AS
$BODY$
BEGIN
	RETURN system.percentile(unsorted_array, 50);
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE RETURNS NULL ON NULL INPUT;


--------------------------------------------------------
-- Max with key aggregation (max_with_key) -------------
--------------------------------------------------------

/*
 * key_value_rs
 * ------------
 * Type used as a return type in the case where a key-value pair is returned.
 * Intended for use by the aggregate function max_with_key, but can be used for other means as well.
 */
CREATE TYPE system.key_value_rs AS
(
	key numeric,
	value numeric
);

/*
 * max_with_key_sfunc
 * ------------------
 * State function for 'max_with_key'.
 */
CREATE OR REPLACE FUNCTION system.max_with_key_sfunc(state numeric[2], e1 numeric, e2 numeric)
	RETURNS numeric[2] AS
$BODY$
BEGIN
	IF state[2] > e2 OR e2 IS NULL THEN
		RETURN state;
	ELSE
		RETURN ARRAY[e1, e2];
	END IF;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;


/*
 * max_with_key_ffunc
 * ------------------
 * Final function for 'max_with_key'.
 * This function is used to shape the endresult into the correct type.
 */
CREATE OR REPLACE FUNCTION system.max_with_key_ffunc(state numeric[2])
	RETURNS system.key_value_rs AS
$BODY$
BEGIN
	RETURN (state[1], state[2]);
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;


/*
 * max_with_key
 * ------------
 * Aggregate function to determine the maximum value in a list of key-values, returning both the key and the value.
 * Input consists of 2 numeric arguments, first should be the key, second should be the value.
 * Output is of the type system.key_value_rs
 (which also consists of a numeric key and numeric value).
 */
CREATE AGGREGATE system.max_with_key(numeric, numeric) (
	SFUNC = system.max_with_key_sfunc,
	STYPE = numeric[2],
	FINALFUNC = system.max_with_key_ffunc,
	INITCOND = '{NULL,NULL}'
);


--------------------------------------------------------
-- Weighted average aggregation (weighted_avg) ---------
--------------------------------------------------------

/*
 * weighted_avg_sfunc
 * ------------------
 * State function for the weighted average function 'weighted_avg'.
 * Collects the total of weighted values and the total of weights in an array with 2 values.
 */
CREATE OR REPLACE FUNCTION system.weighted_avg_sfunc(state numeric[], value numeric, weight numeric)
	RETURNS numeric[] AS
$BODY$
BEGIN
	RETURN ARRAY[COALESCE(state[1], 0) + (value * weight), COALESCE(state[2], 0) + weight];
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE RETURNS NULL ON NULL INPUT;


/*
 * weighted_avg_ffunc
 * ------------------
 * Final function for the weighted average function 'weighted_avg'.
 * Divides the total of the weighted values by the total of the weights (which were collected in an array with 2 values).
 */
CREATE OR REPLACE FUNCTION system.weighted_avg_ffunc(state numeric[])
	RETURNS numeric AS
$BODY$
BEGIN
	IF state[2] = 0 THEN
		RETURN 0;
	ELSE
		RETURN state[1] / state[2];
	END IF;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE RETURNS NULL ON NULL INPUT;


/*
 * weighted_avg
 * ------------
 * Aggregate function to determine a weighted average.
 * First parameter is the value, second parameter is the weight.
 * NULL values are skipped, and if there are no non-NULL values, NULL will be returned.
 */
CREATE AGGREGATE system.weighted_avg(numeric, numeric) (
	SFUNC = system.weighted_avg_sfunc,
	STYPE = numeric[],
	FINALFUNC = system.weighted_avg_ffunc,
	INITCOND = '{NULL,NULL}'
);


--------------------------------------------------------
-- Distibute enum aggregation (distribute_enum) --------
--------------------------------------------------------

/*
 * distribute_enum_sfunc
 * ---------------------
 * State function for enum distribution function 'distribute_enum'.
 * Tracks an array with an element for each value in the enum, and sums the weight according to the supplied enum values.
 */
CREATE OR REPLACE FUNCTION system.distribute_enum_sfunc(state numeric[], key anyenum, weight numeric)
	RETURNS numeric[] AS
$BODY$
BEGIN
	IF array_length(state, 1) IS NULL THEN
		state := array_fill(0, ARRAY[array_length(enum_range(key), 1)]);
	END IF;
	state[system.enum_to_index(key)] := state[system.enum_to_index(key)] + weight;
	RETURN state;
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE RETURNS NULL ON NULL INPUT;


/*
 * distribute_enum
 * ---------------
 * Aggregate function to count the occurrence of values in an enum, weighted if need be.
 * First parameter is an enum value, second parameter is the weight which should be summed for that enum value.
 * As an example, the weight can be 1 to count the number of occurrences of each enum value, or a 'surface' column to sum the surface per enum value.
 * The return value is an array with as many elements as there are values in the enum, in same order as the enum is defined.
 * Each element consists of the summed value for each respective enum value.
 * NULL values are skipped, and if there are no non-NULL values, NULL will be returned.
 */
CREATE AGGREGATE system.distribute_enum(anyenum, numeric) (
	SFUNC = system.distribute_enum_sfunc,
	STYPE = numeric[],
	INITCOND = '{}'
);
