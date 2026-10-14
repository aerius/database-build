require 'Utility.rb'
require 'PathConventions.rb'
require 'PathAssert.rb'
require 'GitUtility.rb'
require 'BuildConfig.rb'

# Single process handle for build settings (groups: layout, output, postgres, sync, tools, session)
$build_config = nil

##
# CLI bootstrap for $build_config: resolve ARGV paths, require product settings, finalize.
# App/User settings are loaded inside BuildConfig#finalize.
#
# Must be run from the product source folder (the folder containing src/build/); product
# settings are always a profile under src/build/profiles/.
#
class SettingsLoader

  # Load product settings into $build_config and finalize. If runscript_file_argument is
  # given, resolve it after finalize (needs layout.runscripts_path).
  # profile_argument may be nil when src/build/profiles/ holds exactly one profile.
  def self.load_settings(profile_argument, runscript_file_argument = nil)
    source_path = determine_source_path

    $build_config = BuildConfig.new_empty
    $build_config.apply_defaults

    # Product settings (mandatory) — assign $build_config.product
    determine_product_settings_file(source_path, profile_argument)
    require $build_config.session.product_settings_file

    $build_config.finalize(source_path)

    determine_runscript_file(runscript_file_argument) unless runscript_file_argument.nil?
  end

  #
  # Private section
  #
  private

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

  # The CWD is the product source folder; it must contain src/build/profiles/.
  def self.determine_source_path
    source_path = Dir.pwd.fix_pathname
    profiles_path = PathConventions.profiles(source_path)
    unless File.directory?(profiles_path) then
      raise "Run from the product source folder (the folder containing #{PathConventions::BUILD_CONFIG_REL}/); \"#{profiles_path}\" not found"
    end
    source_path
  end

  # Sets session.profile and session.product_settings_file (src/build/profiles/<profile>.rb) from
  # profile_argument: a bare name without path or .rb (e.g. 'latest'). Without a name, the
  # single profile is used. Raises when the name is invalid, not found, or omitted while
  # several profiles exist.
  def self.determine_product_settings_file(source_path, profile_argument)
    profiles_path = PathConventions.profiles(source_path)
    available = Dir[File.join(profiles_path, '*.rb')].map { |path| File.basename(path, '.rb') }.sort

    profile = profile_argument.to_s
    if profile.empty? then
      if available.size != 1 then
        raise "No profile given and #{available.size} profiles found in \"#{profiles_path}\" (#{available.join(', ')}); specify one"
      end
      profile = available.first
    end
    if profile =~ %r{[/\\]} || profile.downcase.end_with?('.rb') then
      raise "Profile must be a name without path or .rb, e.g. 'latest' for #{PathConventions::BUILD_CONFIG_REL}/#{PathConventions::PROFILES_DIR}/latest.rb (got \"#{profile_argument}\")"
    end

    product_settings_file = File.join(profiles_path, profile + '.rb').fix_filename
    raise "Profile '#{profile}' not found in \"#{profiles_path}\" (available: #{available.join(', ')})" unless File.file?(product_settings_file)

    $build_config.session.profile = profile
    $build_config.session.product_settings_file = product_settings_file
  end

  # First absolute path or relative to CWD; otherwise under layout.runscripts_path.
  def self.determine_runscript_file(runscript_file_argument)
    runscript_file = expand_with_suffixes(runscript_file_argument, ['.rb'])

    unless File.file?(runscript_file) || $build_config.nil? then
      under_scripts = ($build_config.layout.runscripts_path + runscript_file_argument).fix_filename
      runscript_file = expand_with_suffixes(under_scripts, ['.rb'])
    end

    # Cannot live in BuildConfig#finalize: ARGV runscript is resolved here after finalize,
    $build_config.session.runscript_file = PathAssert.require_file(runscript_file, 'runscript_file')
  end

end
