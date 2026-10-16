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
  MODULES_REPO = 'database-modules'
  # Sibling modules repo: <workspace>/database-modules/source/modules/src/{main,data}/sql
  MODULES_SQL_REL = 'source/modules/src/main/sql'
  MODULES_DATA_REL = 'source/modules/src/data/sql'
  BUILTIN_COMMON_SQL_REL = 'common/src/main/sql'
  CONFIG_DIR = 'config'
  SCRIPTS_DIR = 'scripts'
  APP_SETTINGS_FILE = 'AppSettings.rb'
  USER_SETTINGS_FILE = 'UserSettings.rb'

  # database-build checkout root (parent of bin/)
  def self.database_build_root
    File.expand_path('..', File.dirname($0))
  end

  # Parent of database-build (workspace containing sibling repos)
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
    join(build_config_path, CONFIG_DIR, APP_SETTINGS_FILE).fix_filename
  end

  def self.user_settings(build_config_path)
    join(build_config_path, CONFIG_DIR, USER_SETTINGS_FILE).fix_filename
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
