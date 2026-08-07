##
# Convention path fragments and helpers for deriving product/module layout.
#
module PathConventions
  SQL_REL = 'src/main/sql'
  DATA_REL = 'src/data/sql'
  COMMON_DIR = 'common'
  DBDATA_DIR = 'dbdata'
  RUNSCRIPTS_REL = '../scripts'
  MODULES_REPO = 'database-modules'
  MODULES_SQL_REL = 'source/modules/src/main/sql'
  MODULES_DATA_REL = 'source/modules/src/data/sql'
  BUILTIN_COMMON_SQL_REL = 'common/src/main/sql'
  DEFAULT_DATABASE_NAME_PREFIX = 'AERIUS'

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

  # Expand path to an absolute filename.
  # Relative paths are resolved against base_dir; absolute paths are left as-is.
  def self.expand_from(base_dir, path)
    return nil if path.nil?

    path = path.to_s
    path = '.' if path.empty?

    expanded = is_absolute?(path) ? File.expand_path(path) : File.expand_path(path, base_dir)
    expanded.fix_filename
  end

  def self.is_absolute?(path)
    path.start_with?('/') || path.match?(/^[A-Za-z]:[\\\/]/
  end
  private_class_method :is_absolute?
end
