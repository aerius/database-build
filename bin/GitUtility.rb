require 'pathname'

##
# Git-specific utility methods.
#
class GitUtility

  def self.get_git_hash
    raise 'Git bin path not set ($git_bin_path)' if $git_bin_path.nil?
    raise "Git bin path not found ($git_bin_path = \"#{$git_bin_path}\")" unless ((File.exist?($git_bin_path) && File.directory?($git_bin_path)) || ($git_bin_path.empty?))

    curr_dir = Dir.pwd
    Dir.chdir($product_sql_path)
    cmd = "\"#{$git_bin_path}git\" log -1 --pretty=format:%h"
    socket = IO.popen(cmd)
    begin
      if line = socket.gets then
        line = line.strip
        raise "Illegal git hash found: #{line}" if line.length > 10
        return line
      end
    ensure
      socket.close
      Dir.chdir(curr_dir)
    end
    raise "Could not read GIT hash with command: #{cmd}"
  end

  # Returns git repo root (directory containing .git) for path, or nil.
  def self.get_git_repo_root(path)
    return nil if path.nil? || !File.exist?(path)
    current = Pathname.new(File.expand_path(path)).realpath
    current = current.directory? ? current : current.parent
    while current != current.parent
      return current.to_s if File.exist?(File.join(current.to_s, '.git'))
      current = current.parent
    end
    return nil
  end

  # Returns full git commit hash for the repo containing path, or nil.
  def self.get_git_hash_for_path(path)
    return nil if path.nil? || !File.exist?(path)
    return nil if $git_bin_path.nil? || (!$git_bin_path.to_s.empty? && !File.directory?($git_bin_path))
    root = get_git_repo_root(path)
    return nil if root.nil?
    curr_dir = Dir.pwd
    Dir.chdir(root)
    cmd = ($git_bin_path.to_s.empty? ? 'git' : "\"#{$git_bin_path}git\"") + ' rev-parse HEAD 2>/dev/null'
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

  # Returns remote.origin.url for the repo containing path, or nil.
  def self.get_git_remote_url(path)
    root = get_git_repo_root(path)
    return nil if root.nil?
    curr_dir = Dir.pwd
    Dir.chdir(root)
    cmd = ($git_bin_path.to_s.empty? ? 'git' : "\"#{$git_bin_path}git\"") + ' config --get remote.origin.url 2>/dev/null'
    socket = IO.popen(cmd)
    begin
      url = socket.gets(nil).to_s.strip
      return url.empty? ? nil : url
    ensure
      socket.close
      Dir.chdir(curr_dir)
    end
  rescue
    Dir.chdir(curr_dir) if defined?(curr_dir) && Dir.pwd != curr_dir
    return nil
  end

  # Returns true if the repo containing path has uncommitted or untracked changes.
  def self.get_git_has_uncommitted_changes(path)
    root = get_git_repo_root(path)
    return false if root.nil?
    curr_dir = Dir.pwd
    Dir.chdir(root)
    cmd = ($git_bin_path.to_s.empty? ? 'git' : "\"#{$git_bin_path}git\"") + ' status --porcelain 2>/dev/null'
    socket = IO.popen(cmd)
    begin
      out = socket.gets(nil).to_s.strip
      return !out.empty?
    ensure
      socket.close
      Dir.chdir(curr_dir)
    end
  rescue
    Dir.chdir(curr_dir) if defined?(curr_dir) && Dir.pwd != curr_dir
    return false
  end
end
