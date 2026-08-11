#!/usr/bin/env ruby
#
# This file is the entrypoint for the buildscript. It is called from the .bat files with various parameters.
#

# ------------------------------------

# This makes sure we can 'require' from current folder in all Ruby versions.
# We want an absolute path in there, and not '.', because relative '.' causes
# problems when the same basename is required from multiple directories.
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
  puts "                      build. Contains $build_config.product,"
  puts "                      layout.source_path, and layout.build_config_path."
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
require 'SettingsLoader.rb'
SettingsLoader.load_settings(
  ARGV.size > 1 ? ARGV[1] : nil,
  ARGV.size > 0 ? ARGV[0] : nil
)

# Logger
require 'BuildLogger.rb'
$logger = BuildLogger.new
$logger.open($build_config.output.log_path)

# Scriptrunner will be the class encapsulating the user script
require 'ScriptRunner.rb'
require 'CommonModulesUtility.rb'
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
    when '--dump-filename'; $build_config.session.dump_filetitle = argument
    when '--flags'; argument.split(',').each{ |flag| $build_config.session.build_flags << flag.strip.downcase.to_sym }
    when '--hints'; $build_config.tools.hint_level = argument.to_i
    when '--help'; display_help
  end
end

$logger.hint_level = $build_config.tools.hint_level
$logger.major_hint "You are running a very old depecrated Ruby version (#{RUBY_VERSION}); updating to latest version is recommended" if Utility.is_ruby_version_below('2.2.0')

# ------------------------------------

$build_config.log!($logger)

# Let's go!
begin
  starttime = Time.now
  $logger.writeln ''
  $logger.writeln "Build started at #{Time.now.strftime('%d-%m-%Y %H:%M:%S')}"
  $logger.writeln ''

  if CommonModulesUtility.any_had_uncommitted_changes?($build_config.layout.product_sql_path, $build_config.layout.product_data_path, $build_config.layout.common_sql_paths, $build_config.layout.common_data_paths) then
    case $build_config.tools.on_uncommitted_changes
    when :abort
      $logger.warn 'Uncommitted or untracked changes detected in product or common module repository. Aborting build.'
      exit 1
    when :prompt
      $logger.warn 'Uncommitted or untracked changes detected in product or common module repository!'
      require 'io/console'
      $stdout.print 'Are you sure you want to proceed? (y/n): '
      response = $stdin.getch.downcase
      $stdout.puts response
      unless response == 'y' then
        $logger.writeln 'Build aborted.'
        exit 1
      end
    when :warn
      $logger.warn 'Uncommitted or untracked changes detected in product or common module repository!'
    end
  end

  # Clean up/prepare folders
  if File.exist?($build_config.output.temp_path) && File.directory?($build_config.output.temp_path) then # possible previous run
    $logger.writeln "Deleting '#{$build_config.output.temp_path}'..."
    FileUtils.rm_r($build_config.output.temp_path)
    $logger.error "Deleting '#{$build_config.output.temp_path}' FAILED!" if File.exist?($build_config.output.temp_path)
  end
  FileUtils.mkdir_p($build_config.output.temp_path)

  FileUtils.mkdir_p($build_config.output.output_path) unless File.exist?($build_config.output.output_path)

  # Initialize per product
  $comments_collected = false
  $datasources = nil

  $script_runner.set_database_name(override_database_name) unless override_database_name.nil?
  $script_runner.set_version(override_version) unless override_version.nil?

  $script_runner.execute  # This runs the user script

  # Cleaning up
  if File.exist?($build_config.output.temp_path) then
    $logger.writeln "Deleting #{$build_config.output.temp_path}..."
    FileUtils.rm_r($build_config.output.temp_path)
    $logger.writeln "(Deleting '#{$build_config.output.temp_path}' FAILED!)" if File.exist?($build_config.output.temp_path)
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

