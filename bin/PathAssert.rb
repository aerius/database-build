##
# Path existence checks used when resolving build layout paths.
#
class PathAssert

  # Raise unless path is an existing directory; label is used in the message.
  def self.require_directory(path, label)
    path = path.fix_pathname
    raise "#{path} not found for: #{label}" unless File.directory?(path)
    path
  end

  # Raise unless path is an existing file; label is used in the message.
  def self.require_file(path, label)
    path = path.fix_filename
    raise "#{path} not found for: #{label}" unless File.file?(path)
    path
  end

end
