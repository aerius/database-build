##
# Path existence checks used when resolving build layout paths.
#
class PathUtils

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

end
