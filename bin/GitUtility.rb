##
# Git-specific utility methods.
#
class GitUtility

  # Returns short git hash (first 7 chars) for the repo containing path, or nil.
  def self.get_git_short_hash_for_path(path)
    full_hash = get_git_hash_for_path(path)
    return nil if full_hash.nil?
    return full_hash[0, 7]
  end

  # Returns git repo root for path, or nil.
  def self.get_git_repo_root(path)
    return run_git(path, 'rev-parse --show-toplevel')
  end

  # Returns full git commit hash for the repo containing path, or nil.
  def self.get_git_hash_for_path(path)
    return run_git(path, 'rev-parse HEAD')
  end

  # Returns remote.origin.url for the repo containing path, or nil.
  def self.get_git_remote_url(path)
    return run_git(path, 'config --get remote.origin.url')
  end

  # Returns true if the repo containing path has uncommitted or untracked changes.
  def self.get_git_has_uncommitted_changes(path)
    return run_git(path, 'status --porcelain') != nil
  end

  # Runs a git command from the directory of path.
  # Returns trimmed output as string, or nil on empty output / error.
  def self.run_git(path, args)
    return nil if path.nil? || !File.exist?(path)
    dir = File.directory?(path) ? path : File.dirname(path)
    curr_dir = Dir.pwd
    Dir.chdir(dir)
    cmd = ($git_bin_path.to_s.empty? ? 'git' : "\"#{$git_bin_path}git\"") + ' ' + args + ' 2>/dev/null'
    socket = IO.popen(cmd)
    begin
      out = socket.gets(nil).to_s.strip
      return out.empty? ? nil : out
    ensure
      socket.close
      Dir.chdir(curr_dir)
    end
  rescue
    Dir.chdir(curr_dir) if defined?(curr_dir) && Dir.pwd != curr_dir
    return nil
  end

  private_class_method :run_git
end
