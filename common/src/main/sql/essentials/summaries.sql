/*
 * db_output_summary_table
 * -----------------------
 * Empty (default) db_output_summary_table function.
 *
 * Function could generating files with statistics.
 * Called during build by ruby build script.
 * Can be overwritten by each product to generate some actual summaries.
 */
CREATE OR REPLACE FUNCTION system.db_output_summary_table(filespec text)
	RETURNS void AS
$BODY$
BEGIN
	RAISE NOTICE '** Empty output summary table function...';
END;
$BODY$
LANGUAGE plpgsql VOLATILE;
