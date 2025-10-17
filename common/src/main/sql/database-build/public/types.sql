/*
 * posint
 * ------
 * Integer value type which can only be positive or 0.
 */
CREATE DOMAIN posint AS integer
	CHECK (VALUE >= 0::integer);


/*
 * posreal
 * -------
 * Real (decimal) value type which can only be positive or 0.
 */
CREATE DOMAIN posreal AS real
	CHECK (VALUE >= 0::real);


/*
 * posnum
 * -------
 * Numeric (decimal) value type which can only be positive or 0.
 */
CREATE DOMAIN posnum AS numeric
	CHECK (VALUE >= 0::numeric);


/*
 * fraction
 * --------
 * Numeric (decimal) value type between 0 and 1 (inclusive), specifying fractions.
 */
CREATE DOMAIN fraction AS numeric
	CHECK ((VALUE >= 0::numeric) AND (VALUE <= 1::numeric));
