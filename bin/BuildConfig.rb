HINT_LEVEL_OFF = 0
HINT_LEVEL_MAJOR = 1
HINT_LEVEL_ALL = 2

##
# Build settings and derived layout paths ($build_config), grouped for clarity.
#
# Call order (see SettingsLoader.prepare):
#   1. BuildConfig.new_empty
#   2. apply_defaults                         — fill defaults on the empty config
#   3. require product settings                — assign product / layout.* (overrides)
#   4. finalize(product_settings_dir)         — load App/UserSettings, derive internal/builtin layout
#   5. ExternalModules.prepare                — materialize externals, merge common SQL/data paths
#   6. optional runscript resolve              — after finalize (needs layout.runscripts_path)
#   7. log(logger)                            — optional; dump resolved config (Build.rb)
#
# Settings files assign into $build_config; overrides in steps 3–4 replace defaults from step 2.
#
class BuildConfig
  CONFIG_DIR = 'config'
  SCRIPTS_DIR = 'scripts'
  APP_SETTINGS_FILE = 'AppSettings.rb'
  USER_SETTINGS_FILE = 'UserSettings.rb'
  DEFAULT_DATABASE_NAME_PREFIX = 'AERIUS'

  Layout = Struct.new(
    :source_path, :build_config_path,
    :product_sql_path, :product_data_path,
    :common_sql_paths, :common_data_paths,
    :runscripts_path, :dbdata_path,
    :app_settings_file, :user_settings_file,
    :external_common_modules_file
  )

  Output = Struct.new(
    :target_path, :log_path, :output_path, :temp_path
  )

  Postgres = Struct.new(
    :username, :password, :bin_path, :hostname, :port,
    :template, :tablespace, :collation, :name_prefix,
    :essentials_function_prefix, :unittest_prefix
  )

  Tools = Struct.new(
    :git_bin_path,
    :https_data_path, :https_data_username, :https_data_password,
    :max_threads, :on_uncommitted_changes, :hint_level
  )

  Session = Struct.new(
    :product_settings_file, :runscript_file,
    :build_flags, :dump_filetitle,
    :common_module_versions
  )

  attr_accessor :product
  attr_reader :layout, :output, :postgres, :tools, :session
  attr_reader :internal_common_sql_paths, :internal_common_data_paths

  def initialize(product, layout, output, postgres, tools, session)
    @product = product
    @layout = layout
    @output = output
    @postgres = postgres
    @tools = tools
    @session = session
    @internal_common_sql_paths = []
    @internal_common_data_paths = []
  end

  def self.new_empty
    new(
      nil,
      Layout.new(nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil),
      Output.new(nil, nil, nil, nil),
      Postgres.new(nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil),
      Tools.new(nil, nil, nil, nil, nil, nil, nil),
      Session.new(nil, nil, [], nil, [])
    )
  end

  # Default values for a new (empty) build config (mutates self).
  def apply_defaults
    output.target_path = File.expand_path('./target/')
    output.log_path = File.expand_path(output.target_path + '/log/').fix_pathname
    output.output_path = File.expand_path(output.target_path + '/build/').fix_pathname
    output.temp_path = File.expand_path(output.target_path + '/temp/').fix_pathname

    postgres.username = 'aerius'
    postgres.password = 'aerius'

    if !ENV['POSTGRESQL_BIN'].nil? then
      postgres.bin_path = ENV['POSTGRESQL_BIN']
    elsif ON_WINDOWS then
      if !ENV['CommonProgramW6432'].nil? then
        postgres.bin_path = Utility.find_best_postgresql_path(File.expand_path(ENV['CommonProgramW6432'] + '/../'))
      elsif !ENV['ProgramFiles(x86)'].nil? then
        postgres.bin_path = Utility.find_best_postgresql_path(ENV['ProgramFiles(x86)'])
      elsif !ENV['ProgramFiles'].nil? then
        postgres.bin_path = Utility.find_best_postgresql_path(ENV['ProgramFiles'])
      end
    else
      postgres.bin_path = ''
    end

    postgres.template = 'template0'
    postgres.tablespace = ''
    postgres.collation = ''
    postgres.name_prefix = DEFAULT_DATABASE_NAME_PREFIX
    postgres.essentials_function_prefix = 'system.'
    postgres.unittest_prefix = 'unittest_'

    tools.git_bin_path = GitUtility.default_bin_path
    tools.max_threads = 10
    tools.on_uncommitted_changes = :warn
    tools.hint_level = HINT_LEVEL_ALL

    self
  end

  # Expand relative layout paths, derive fixed paths, normalize and validate.
  def finalize(product_settings_dir)
    raise 'Product not set ($build_config.product)' if product.nil?
    raise 'Source path not set ($build_config.layout.source_path)' if layout.source_path.nil?
    raise 'Build config path not set ($build_config.layout.build_config_path)' if layout.build_config_path.nil?

    layout.source_path = PathConventions.expand_from(product_settings_dir, layout.source_path)
    layout.build_config_path = PathAssert.require_directory(
      PathConventions.expand_from(product_settings_dir, layout.build_config_path),
      'build_config_path'
    )

    layout.app_settings_file = PathAssert.require_file(
      PathConventions.join(layout.build_config_path, CONFIG_DIR, APP_SETTINGS_FILE),
      'app_settings_file'
    )
    require layout.app_settings_file

    layout.user_settings_file = PathConventions.join(
      layout.build_config_path, CONFIG_DIR, USER_SETTINGS_FILE
    ).fix_filename
    layout.user_settings_file = nil unless File.exist?(layout.user_settings_file)
    require layout.user_settings_file unless layout.user_settings_file.nil?

    layout.source_path = PathAssert.require_directory(layout.source_path, 'source_path')

    # Convention: source/src/{main,data}/sql/<product>/; optional override when already set.
    layout.product_sql_path = if layout.product_sql_path.nil?
      PathConventions.join(layout.source_path, PathConventions::SQL_REL, product.to_s)
    else
      PathConventions.expand_from(layout.source_path, layout.product_sql_path)
    end
    layout.product_sql_path = PathAssert.require_directory(layout.product_sql_path, 'product_sql_path')

    layout.product_data_path = if layout.product_data_path.nil?
      PathConventions.join(layout.source_path, PathConventions::DATA_REL, product.to_s)
    else
      PathConventions.expand_from(layout.source_path, layout.product_data_path)
    end
    layout.product_data_path = PathAssert.require_directory(layout.product_data_path, 'product_data_path')

    # Internal modules only here; externals come from the modules file + ExternalModules;
    # merged common_*_paths are set by apply_common_module_paths after materialize.
    @internal_common_sql_paths = [
      PathConventions.internal_modules_sql(layout.source_path)
    ].compact
    @internal_common_data_paths = [
      PathConventions.internal_modules_data(layout.source_path)
    ].compact

    if layout.external_common_modules_file.nil? || layout.external_common_modules_file.to_s.empty?
      layout.external_common_modules_file = nil
    else
      layout.external_common_modules_file = PathAssert.require_file(
        PathConventions.expand_from(product_settings_dir, layout.external_common_modules_file),
        'external_common_modules_file'
      )
    end

    layout.runscripts_path = PathAssert.require_directory(
      PathConventions.join(layout.build_config_path, SCRIPTS_DIR),
      'runscripts_path'
    )

    layout.dbdata_path = PathConventions.join(PathConventions.workspace_root, PathConventions::DBDATA_DIR) if layout.dbdata_path.nil?
    layout.dbdata_path = PathAssert.require_directory(layout.dbdata_path, 'dbdata_path')

    raise 'Temp path not set ($build_config.output.temp_path)' if output.temp_path.nil?
    raise 'Output path not set ($build_config.output.output_path)' if output.output_path.nil?
    raise 'Log path not set ($build_config.output.log_path)' if output.log_path.nil?
    raise 'Database name prefix not set ($build_config.postgres.name_prefix)' if postgres.name_prefix.nil?
    raise 'PostgreSQL bin path not set ($build_config.postgres.bin_path)' if postgres.bin_path.nil?
    unless !ON_WINDOWS && postgres.bin_path.empty?
      postgres.bin_path = PathAssert.require_directory(postgres.bin_path, 'postgres.bin_path')
    end
    raise 'PostgreSQL username not set ($build_config.postgres.username)' if postgres.username.nil? || postgres.username.to_s.empty?
    raise 'PostgreSQL password not set ($build_config.postgres.password)' if postgres.password.nil? || postgres.password.to_s.empty?

    output.log_path = output.log_path.fix_pathname
    output.output_path = output.output_path.fix_pathname
    output.temp_path = output.temp_path.fix_pathname
    tools.git_bin_path = tools.git_bin_path.fix_pathname unless (tools.git_bin_path.nil? || tools.git_bin_path.empty?)

    self
  end

  # Merge internal + external + builtin into layout.common_sql_paths / common_data_paths and validate.
  def apply_common_module_paths(external_sql_paths, external_data_paths)
    builtin_sql = PathConventions.join(
      PathConventions.database_build_root, PathConventions::BUILTIN_COMMON_SQL_REL
    ).fix_pathname

    layout.common_sql_paths = (
      @internal_common_sql_paths + external_sql_paths + [builtin_sql]
    ).map { |path| path.fix_pathname.chomp('/') }
    layout.common_data_paths = (
      @internal_common_data_paths + external_data_paths
    ).map { |path| path.fix_pathname.chomp('/') }

    layout.common_sql_paths.map!.with_index { |path, idx|
      PathAssert.require_directory(path, "common_sql_paths[#{idx}]")
    }
    layout.common_data_paths.map!.with_index { |path, idx|
      PathAssert.require_directory(path, "common_data_paths[#{idx}]")
    }

    self
  end

  # Log the resolved $build_config values (masks secrets), using the supplied logger object.
  def log(logger)
    logger.writeln "product: #{product}"
    log_struct(logger, 'layout', layout)
    log_struct(logger, 'output', output)
    log_struct(logger, 'postgres', postgres, [:password])
    log_struct(logger, 'tools', tools, [:https_data_password])
    log_struct(logger, 'session', session)
  end

  #
  # Private section
  #
  private

  def log_struct(logger, name, struct, mask = [])
    struct.members.each do |member|
      value = struct[member]
      value = '<set>' if mask.include?(member) && !value.nil? && !value.to_s.empty?
      value = '<none>' if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      if value.is_a?(Array)
        logger.writeln "#{name}.#{member}:"
        value.each_with_index { |item, idx| logger.writeln "  [#{idx}] #{item}" }
      else
        logger.writeln "#{name}.#{member}: #{value}"
      end
    end
  end
end
