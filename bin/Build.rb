#!/usr/bin/env ruby
#
# This file is the entrypoint for the buildscript. It is called from the .bat files with various parameters.
#

# ------------------------------------

# This makes sure we can 'require' from current folder in all Ruby versions.
# We want an absolute path in there, and not '.', because the latter causes problems with Settings.rb being placed in multiple locations.
this_path = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH << this_path unless $LOAD_PATH.include?(this_path)
$LOAD_PATH.delete('.') if $LOAD_PATH.include?('.')

require 'fileutils'
require 'getoptlong'

require 'Utility.rb'

# ------------------------------------

def display_help
  puts "Syntax:\n  ruby #{File.basename(__FILE__)} ruby-script-file product-settings-file [parameters]\n\n"
  puts "  ruby-script-file"
  puts "                      Path and filename of runscript with the build steps. Can"
  puts "                      be absolute, relative to CWD, or in $run_scripts_path."
  puts "  product-settings-file"
  puts "                      Path and filename of product settings of product to"
  puts "                      build. Contains $product and references to paths of"
  puts "                      project, product data and sql, and common data and sql."
  puts "\nParameters:"
  puts "  -d --dbdata-path    Path where the table dump files are located (for"
  puts "                      load scripts)"
  puts "  -n --database-name  Target name for the new database"
  puts "  -v --version        Target version for the new database"
  puts "  -f --dump-filename  Filename (no path) for the database dump. If"
  puts "                      omitted, database name is used"
  puts "  -l --flags          Comma separated list of build flags"
  puts "     --hints [level]  Specify hint level, 0 = off, 1 = only major, 2 = all"
  puts "  -h --help           This help"
  exit
end

opts = {}
GetoptLong.new(
    ['--dbdata-path', '-d', GetoptLong::REQUIRED_ARGUMENT],
    ['--database-name', '-n', GetoptLong::REQUIRED_ARGUMENT],
    ['--version', '-v', GetoptLong::REQUIRED_ARGUMENT],
    ['--dump-filename', '-f', GetoptLong::REQUIRED_ARGUMENT],
    ['--flags', '-l', GetoptLong::REQUIRED_ARGUMENT],
    ['--hints', GetoptLong::REQUIRED_ARGUMENT],
    ['--help', '-h', GetoptLong::NO_ARGUMENT]
).each { |option, argument| opts[option.downcase] = argument }

display_help if opts.has_key?('--help')

# ------------------------------------

# Settings
require 'Globals.rb'
Globals.load_settings(ARGV.size > 1 ? ARGV[1] : nil)
Globals.determine_runscript_file(ARGV.size > 0 ? ARGV[0] : nil)

# Logger
require 'BuildLogger.rb'
$logger = BuildLogger.new
$logger.open($product_log_path)

# Scriptrunner will be the class encapsulating the user script
require 'ScriptRunner.rb'
$script_runner = ScriptRunner.new

# ------------------------------------

# Parse commandline options
override_database_name = nil
override_version = nil
opts.each do |option, argument|
  case option.downcase
    when '--dbdata-path'; $script_runner.set_dbdata_path(argument)
    when '--database-name'; override_database_name = argument
    when '--version'; override_version = argument
    when '--dump-filename'; $dump_filetitle = argument
    when '--flags'; argument.split(',').each{ |flag| $build_flags << flag.strip.downcase.to_sym }
    when '--hints'; $hint_level = argument.to_i
    when '--help'; display_help
  end
end

$logger.hint_level = $hint_level
$logger.major_hint "You are running a very old depecrated Ruby version (#{RUBY_VERSION}); updating to latest version is recommended" if Utility.is_ruby_version_below('2.2.0')

# ------------------------------------

$logger.writeln "Building product: #{$product.to_s}"
$logger.writeln 'Build flags: ' + ($build_flags.empty? ? '<none>' : $build_flags.sort.join(', '))
$logger.writeln "Runscript: #{$runscript_file}"
$logger.writeln "Product settings file: #{$product_settings_file}"
$logger.writeln "User product settings file: #{$user_product_settings_file}" unless $user_product_settings_file.nil?
$logger.writeln "Project settings file: #{$project_settings_file}"
$logger.writeln "User project settings file: #{$user_project_settings_file}" unless $user_project_settings_file.nil?
$logger.writeln "Output path: #{$product_output_path}"

# Let's go!
begin
  starttime = Time.now
  $logger.writeln ''
  $logger.writeln "Build started at #{Time.now.strftime('%d-%m-%Y %H:%M:%S')}"
  $logger.writeln ''

  # Clean up/prepare folders
  if File.exist?($product_temp_path) && File.directory?($product_temp_path) then # possible previous run
    $logger.writeln "Deleting '#{$product_temp_path}'..."
    FileUtils.rm_r($product_temp_path)
    $logger.error "Deleting '#{$product_temp_path}' FAILED!" if File.exist?($product_temp_path)
  end
  FileUtils.mkdir_p($product_temp_path)

  FileUtils.mkdir_p($product_output_path) unless File.exists?($product_output_path)

  # Initialize per product
  $comments_collected = false
  $datasources = nil

  $script_runner.set_database_name(override_database_name) unless override_database_name.nil?
  $script_runner.set_version(override_version) unless override_version.nil?

  $script_runner.execute  # This runs the user script

  # Cleaning up
  if File.exist?($product_temp_path) then
    $logger.writeln "Deleting #{$product_temp_path}..."
    FileUtils.rm_r($product_temp_path)
    $logger.writeln "(Deleting '#{$product_temp_path}' FAILED!)" if File.exist?($product_temp_path)
  end

  $logger.writeln ''
  $logger.writeln "Build completed at #{Time.now.strftime('%d-%m-%Y %H:%M:%S')} (#{Utility.format_duration(Time.now - starttime)})"

rescue Exception => e
  $logger.log e
  $logger.writeln ''
  $logger.writeln "Build failed at #{Time.now.strftime('%d-%m-%Y %H:%M:%S')} (#{Utility.format_duration(Time.now - starttime)})"
  $logger.close

  raise
end

$logger.close

