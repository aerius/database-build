##
# Convention path fragments and helpers for deriving product/module layout.
#
module PathConventions
  SQL_REL = 'src/main/sql'
  DATA_REL = 'src/data/sql'
  MODULES_DIR = 'modules'
  DBDATA_DIR = 'dbdata'
  BUILD_CONFIG_REL = 'src/build'
  PROFILES_DIR = 'profiles'
  EXTERNALS_DIR = 'externals'
  EXTERNAL_COMMON_MODULES_FILE = 'modules.rb'
  BUILTIN_COMMON_SQL_REL = 'common/src/main/sql'
  EXTERNAL_MODULES_SQL_REL = 'source/modules/src/main/sql'
  EXTERNAL_MODULES_DATA_REL = 'source/modules/src/data/sql'
  CONFIG_DIR = 'config'
  SCRIPTS_DIR = 'scripts'
  APP_SETTINGS_FILE = 'AppSettings.rb'
  USER_SETTINGS_FILE = 'UserSettings.rb'

  # database-build checkout root (parent of bin/)
  def self.database_build_root
    File.expand_path('..', File.dirname($0))
  end

  # Parent of database-build (workspace: sibling repo checkouts and dbdata/ folder)
  def self.workspace_root
    File.expand_path('..', database_build_root)
  end

  def self.join(*parts)
    File.expand_path(File.join(*parts.reject { |p| p.nil? || p.to_s.empty? }))
  end

  def self.dir_if_exists(*parts)
    path = join(*parts)
    (File.exist?(path) && File.directory?(path)) ? path.fix_pathname : nil
  end

  # <source>/src/build
  def self.build_config(source_path)
    join(source_path, BUILD_CONFIG_REL)
  end

  # <source>/src/build/profiles
  def self.profiles(source_path)
    join(source_path, BUILD_CONFIG_REL, PROFILES_DIR)
  end

  def self.product_sql(source_path, product)
    join(source_path, SQL_REL, product.to_s)
  end

  # Data set per profile: <source>/src/data/sql/<profile>
  def self.product_data(source_path, profile)
    join(source_path, DATA_REL, profile.to_s)
  end

  def self.runscripts(build_config_path)
    join(build_config_path, SCRIPTS_DIR)
  end

  def self.app_settings(build_config_path)
    join(build_config_path, CONFIG_DIR, APP_SETTINGS_FILE)
  end

  def self.user_settings(build_config_path)
    join(build_config_path, CONFIG_DIR, USER_SETTINGS_FILE).fix_filename
  end

  # Fixed beside profiles/: <build_config>/externals/modules.rb when present.
  def self.external_modules_file(build_config_path)
    path = join(build_config_path, EXTERNALS_DIR, EXTERNAL_COMMON_MODULES_FILE).fix_filename
    File.file?(path) ? path : nil
  end

  def self.default_dbdata
    join(workspace_root, DBDATA_DIR)
  end

  # Internal modules sit beside $source_path: <parent>/modules/src/{main,data}/sql
  def self.internal_modules_sql(source_path)
    dir_if_exists(File.dirname(source_path), MODULES_DIR, SQL_REL)
  end

  def self.internal_modules_data(source_path)
    dir_if_exists(File.dirname(source_path), MODULES_DIR, DATA_REL)
  end

end
