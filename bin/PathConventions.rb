##
# Convention path fragments and helpers for deriving product/module layout.
#
module PathConventions
  SQL_REL = 'src/main/sql'
  DATA_REL = 'src/data/sql'
  MODULES_DIR = 'modules'
  DBDATA_DIR = 'dbdata'
  BUILTIN_COMMON_SQL_REL = 'common/src/main/sql'
  EXTERNAL_MODULES_SQL_REL = 'source/modules/src/main/sql'
  EXTERNAL_MODULES_DATA_REL = 'source/modules/src/data/sql'

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

  # Internal modules sit beside $source_path: <parent>/modules/src/{main,data}/sql
  def self.internal_modules_sql(source_path)
    dir_if_exists(File.dirname(source_path), MODULES_DIR, SQL_REL)
  end

  def self.internal_modules_data(source_path)
    dir_if_exists(File.dirname(source_path), MODULES_DIR, DATA_REL)
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

  #
  # Private section
  #
  private

  def self.is_absolute?(path)
    path.start_with?('/') || path.match?(%r{^[A-Za-z]:[\\/]})
  end

end
