require 'Utility.rb'
require 'PathConventions.rb'
require 'PathAssert.rb'
require 'GitUtility.rb'
require 'BuildConfig.rb'
require 'ExternalModules.rb'

# Single process handle for build settings (groups: layout, output, postgres, tools, session)
$build_config = nil

##
# CLI bootstrap for $build_config: resolve ARGV paths, require product settings, finalize,
# materialize external common modules. App/User settings are loaded inside BuildConfig#finalize!.
#
class SettingsLoader

  # Prepare $build_config for Build / Sync: load settings, materialize or restore externals.
  # build_flags may be nil, a comma-separated String, or an Array (must include :clean for clean/Docker).
  def self.prepare!(product_settings_file_argument, runscript_file_argument = nil, build_flags: [])
    $build_config = BuildConfig.new_empty
    $build_config.apply_defaults!
    $build_config.session.build_flags = parse_build_flags(build_flags)

    # Product settings (mandatory) — assign $build_config.product / layout.*
    product_settings_file = determine_product_settings_file(product_settings_file_argument)
    $build_config.session.product_settings_file = product_settings_file
    require product_settings_file

    $build_config.finalize!(product_settings_dir: File.dirname(product_settings_file))

    load_external_modules_file!
    ExternalModules.ensure_prepared!(logger: nil)

    determine_runscript_file(runscript_file_argument) unless runscript_file_argument.nil?
  end

  # Accepts nil, a comma-separated String, or an Array of flags/symbols.
  def self.parse_build_flags(flags_argument)
    return [] if flags_argument.nil?
    parts = flags_argument.is_a?(String) ? flags_argument.split(',') : Array(flags_argument)
    normalize_build_flags(parts)
  end

  #
  # Private section
  #
  private

  def self.normalize_build_flags(build_flags)
    flags = []
    Array(build_flags).each do |flag|
      sym = flag.to_s.strip.downcase.to_sym
      flags << sym unless sym.to_s.empty? || flags.include?(sym)
    end
    flags
  end

  # Expand path_argument; if not a file, try appending each suffix in order.
  # Returns the first existing non-directory path, or the expanded path if none match.
  def self.expand_with_suffixes(path_argument, suffixes)
    path = File.expand_path(path_argument).fix_filename
    return path if File.file?(path)
    suffixes.each do |suffix|
      candidate = (path + suffix).fix_filename
      return candidate if File.file?(candidate)
    end
    path
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

    unless File.file?(runscript_file) || $build_config.nil? then
      under_scripts = ($build_config.layout.runscripts_path + runscript_file_argument).fix_filename
      runscript_file = expand_with_suffixes(under_scripts, ['.rb'])
    end

    # Cannot live in BuildConfig#finalize!: ARGV runscript is resolved here after finalize,
    $build_config.session.runscript_file = PathAssert.ensure_file!(runscript_file, 'runscript_file')
  end

  # Load optional layout.external_common_modules_file into session.common_module_versions.
  # Modules files may assign $build_config.session.common_module_versions or $common_module_versions.
  def self.load_external_modules_file!
    path = $build_config.layout.external_common_modules_file
    if path.nil? || path.to_s.empty? then
      $build_config.session.common_module_versions = []
      return
    end

    $common_module_versions = nil
    require path

    versions = $build_config.session.common_module_versions
    if (versions.nil? || (versions.respond_to?(:empty?) && versions.empty?)) && !$common_module_versions.nil? then
      versions = $common_module_versions
    end
    $build_config.session.common_module_versions = Array(versions)
  end

end
