require 'Utility.rb'
require 'PathConventions.rb'
require 'PathAssert.rb'
require 'GitUtility.rb'
require 'BuildConfig.rb'

# Single process handle for build settings (groups: layout, output, postgres, tools, session)
$build_config = nil

##
# CLI bootstrap for $build_config: resolve ARGV paths, require product settings, finalize.
# App/User settings are loaded inside BuildConfig#finalize!.
#
class SettingsLoader

  # Load product settings into $build_config and finalize. If runscript_file_argument is
  # given, resolve it after finalize (needs layout.runscripts_path).
  def self.load_settings(product_settings_file_argument, runscript_file_argument = nil)
    $build_config = BuildConfig.new_empty
    $build_config.apply_defaults!

    # Product settings (mandatory) — assign $build_config.product / layout.*
    product_settings_file = determine_product_settings_file(product_settings_file_argument)
    $build_config.session.product_settings_file = product_settings_file
    require product_settings_file

    $build_config.finalize!(product_settings_dir: File.dirname(product_settings_file))

    determine_runscript_file(runscript_file_argument) unless runscript_file_argument.nil?
  end

  #
  # Private section
  #
  private

  # Expand path_argument; if not a file, try appending each suffix in order.
  # Returns the first existing non-directory path, or the expanded path if none match.
  def self.expand_with_suffixes(path_argument, suffixes)
    path = File.expand_path(path_argument).form_filename
    return path if file?(path)
    suffixes.each do |suffix|
      candidate = (path + suffix).form_filename
      return candidate if file?(candidate)
    end
    path
  end

  def self.file?(path)
    File.exist?(path) && !File.directory?(path)
  end

  def self.determine_product_settings_file(product_settings_file_argument)
    if product_settings_file_argument.nil? || product_settings_file_argument.start_with?('-') then
      puts 'Specify a product-settings file. See --help for more information.'
      exit
    else
      product_settings_file = expand_with_suffixes(product_settings_file_argument, ['.rb', 'Settings.rb'])
      # Cannot live in BuildConfig#finalize!: must exist before require and before
      return PathAssert.ensure_file!(product_settings_file, 'product_settings_file')
    end
  end

  # First absolute path or relative to CWD; otherwise under layout.runscripts_path.
  def self.determine_runscript_file(runscript_file_argument)
    runscript_file = expand_with_suffixes(runscript_file_argument, ['.rb'])

    unless file?(runscript_file) || $build_config.nil? then
      under_scripts = ($build_config.layout.runscripts_path + runscript_file_argument).form_filename
      runscript_file = expand_with_suffixes(under_scripts, ['.rb'])
    end

    # Cannot live in BuildConfig#finalize!: ARGV runscript is resolved here after finalize,
    $build_config.session.runscript_file = PathAssert.ensure_file!(runscript_file, 'runscript_file')
  end

end
