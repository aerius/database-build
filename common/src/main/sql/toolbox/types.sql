/*
 * fraction
 * --------
 * Real (decimal) value type between 0 and 1 (inclusive), specifying fractions.
 * Used for the habitat coverage factor for example.
 */
CREATE DOMAIN system.fraction AS real
	CHECK ((VALUE >= 0::real) AND (VALUE <= 1::real));
