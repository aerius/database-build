##
# Path existence checks used when resolving build layout paths.
#
class PathUtils

  # Ensure path is an existing directory; label is used for the raise message.
  def self.ensure_dir!(path, label)
    path = path.fix_pathname
    raise "#{path} not found for: #{label}" unless File.exist?(path) && File.directory?(path)
    path
  end

  # Ensure path is an existing file; label is used for the raise message.
  def self.ensure_file!(path, label)
    path = path.fix_filename
    raise "#{path} not found for: #{label}" unless File.exist?(path) && !File.directory?(path)
    path
  end

end
