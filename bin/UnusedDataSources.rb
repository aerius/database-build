#!/usr/bin/env ruby

puts "WARNING: only use this tool when all products have the same parent root folder! Because we must scan ALL products otherwise we delete too much. Normally not all products are known, only the one specified by the product settings file..."

# Finds all data files that are no longer used in the db-data folder (these are likely older versions).
# Generates a batch file in the /target/ folder which you can run to delete them.

this_path = File.expand_path(File.dirname(__FILE__)) # This makes sure we can 'require' from current folder in all Ruby versions.
$LOAD_PATH << this_path unless $LOAD_PATH.include?(this_path)
$LOAD_PATH.delete('.') if $LOAD_PATH.include?('.')

require 'fileutils'
require 'getoptlong'

require 'Utility.rb'
require 'DataSourceCollector.rb'

# ------------------------------------

# Settings
require 'Globals.rb'
Globals.load_settings(ARGV.size > 0 ? ARGV[0] : nil)

# Logger
require 'BuildLogger.rb'
$logger = BuildLogger.new
$logger.open($log_path, 'unused_datasources')

# Collect datasources
# Walk through all load sql files in the data folder and find the datasource txt filenames.
# parse_path is the path to database\src\data\sql\
$logger.writeln "Collecting datasources..."

datasources = {}
parse_path = File.expand_path($product_data_path + '../').fix_pathname
$logger.writeln "Looking in #{parse_path}..."
Dir[parse_path.fix_pathname + '*/load.rb'].each{ |load_rb_entry|
  product_datasources = DataSourceCollector.collect($logger, File.dirname(load_rb_entry), $common_data_path, $dbdata_path)
  datasources.merge!(product_datasources)
  $logger.writeln "#{load_rb_entry} (#{product_datasources.size} datasources found)"
}
$datasources = datasources.keys.sort

# Collect unused files
$logger.writeln "Scanning '#{$dbdata_path}'..."
unused = []
unused_total_size = 0
Dir[$dbdata_path + '/**/*'].each { |filename|
  ext = File.extname(filename)
  if ext == '.txt' || ext == '.info' then
    txtfilename = filename
    txtfilename = filename.chomp('.info') + '.txt' if ext == '.info'
    unless $datasources.include?(txtfilename)
      unused << filename
      unused_total_size += File.size(filename)
    end
  end
}

$logger.writeln "#{unused.size} unused files found (#{Utility.format_filesize(unused_total_size)})."

unless unused.empty? then
  output_file = $output_path + 'delete_unused_datasources.bat'
  open(output_file, 'w') { |f|
    f.puts '@ECHO OFF'
    unused.each{ |filename|
      filename.gsub!('/', '\\')
      f.puts "DEL \"#{filename}\""
    }
  }

  $logger.writeln "Batch file to delete them written to: #{output_file}"
  $logger.writeln "ENSURE THAT THE PRODUCT LIST ABOVE IS COMPLETE BEFORE RUNNING THIS -- OTHERWISE TOO MUCH DATASOURCES ARE LISTED HERE"
end
