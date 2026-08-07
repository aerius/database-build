require 'Utility.rb'
require 'PathConventions.rb'
require 'GitUtility.rb'
require 'BuildConfig.rb'

# Single process handle for build settings (groups: layout, output, postgres, tools, session)
$build_config = nil

##
# Class with a load-methods
#
class Globals

  # Normalize path and raise unless it exists as a directory.
  def self.ensure_dir!(path, label)
    path = path.fix_pathname
    raise "#{label} not found (#{label} = \"#{path}\")" unless File.exist?(path) && File.directory?(path)
    path
  end

  # Normalize path and raise unless it exists as a file.
  def self.ensure_file!(path, label)
    path = path.fix_filename
    raise "#{label} not found (#{label} = \"#{path}\")" unless File.exist?(path) && !File.directory?(path)
    path
  end

  # Determine full runscript filename. First absolute path or relative to CWD. Otherwise use $build_config.layout.runscripts_path.
  def self.determine_runscript_file(runscript_file_argument)
    if runscript_file_argument.nil? then
      puts 'Specify a runscript. See --help for more information.'
      exit
    else
      runscript_file = File.expand_path(runscript_file_argument).fix_filename
      runscript_file += '.rb' if !File.exist?(runscript_file) && File.exist?(runscript_file + '.rb')

      unless (File.exist?(runscript_file) && !File.directory?(runscript_file)) || $build_config.nil? then
        runscript_file = ($build_config.layout.runscripts_path + runscript_file_argument).fix_filename
        runscript_file += '.rb' if !File.exist?(runscript_file) && File.exist?(runscript_file + '.rb')
      end

      $build_config.session.runscript_file = ensure_file!(runscript_file, 'runscript_file')
    end
  end

  # Load buildsystem, product, AppSettings and UserSettings into $build_config
  def self.load_settings(product_settings_file_argument)
    $build_config = BuildConfig.new_empty
    $build_config.apply_defaults!

    # Product settings (mandatory) — assign $build_config.product / layout.*
    product_settings_file = determine_product_settings_file(product_settings_file_argument)
    $build_config.session.product_settings_file = product_settings_file
    require product_settings_file

    $build_config.finalize!(product_settings_dir: File.dirname(product_settings_file))
  end

 private

  def self.determine_product_settings_file(product_settings_file_argument)
    if product_settings_file_argument.nil? || product_settings_file_argument.start_with?('-') then
      puts 'Specify a product-settings file. See --help for more information.'
      exit
    else
      product_settings_file = File.expand_path(product_settings_file_argument).fix_filename
      product_settings_file += '.rb' if !File.exist?(product_settings_file) && File.exist?(product_settings_file + '.rb')
      product_settings_file += 'Settings.rb' if !File.exist?(product_settings_file) && File.exist?(product_settings_file + 'Settings.rb')
      return ensure_file!(product_settings_file, 'product_settings_file')
    end
  end

end
