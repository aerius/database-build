require 'fileutils'
require 'uri'
require 'Utility.rb'

##
# Git-specific utility methods.
#
class GitUtility

  # Default git bin path: GIT_BIN env, else Windows Program Files Git/cmd/, else '' (use PATH).
  def self.default_bin_path
    return ENV['GIT_BIN'] unless ENV['GIT_BIN'].nil?

    if ON_WINDOWS then
      path = nil
      path = ENV['ProgramFiles(x86)'].fix_pathname + 'Git/cmd/' unless ENV['ProgramFiles(x86)'].nil?
      path = ENV['ProgramFiles'].fix_pathname + 'Git/cmd/' if path.nil? && !ENV['ProgramFiles'].nil?
      return path.nil? ? '' : path  # empty: assume git is on PATH
    else # Linux / other
      return ''  # assume git is on PATH
    end
  end

  # Returns Git's abbreviated hash for the repo containing path, or nil. Raises if abbreviation is longer than 10 chars.
  def self.get_git_short_hash_for_path(path)
    short = run_git(path, 'log -1 --pretty=format:%h')
    return nil if short.nil?
    raise "Illegal git hash found: #{short}" if short.length > 10
    return short
  end

  # Returns git repo root for path, or nil.
  # Prefers `git rev-parse`; if git is unavailable, walks parents for a `.git` entry.
  def self.get_git_repo_root(path)
    root = run_git(path, 'rev-parse --show-toplevel')
    return root unless root.nil? || root.to_s.empty?
    return find_git_repo_root_by_dot_git(path)
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

  # Returns true if HEAD at path resolves to the same commit as gitref
  # (full/short hash, tag, or branch name in that repo).
  def self.ref_matches_path?(path, gitref)
    return false if path.nil? || !File.directory?(path) || gitref.nil? || gitref.to_s.empty?
    current = get_git_hash_for_path(path)
    return false if current.nil?
    desired = resolve_commit(path, gitref)
    return !desired.nil? && desired == current
  end

  # Raises unless repo_url is a plain HTTPS URL (no SSH, no embedded credentials).
  # Auth for private clones is only via GIT_USERNAME / GIT_TOKEN.
  def self.require_plain_https_repo_url(repo_url)
    url = repo_url.to_s
    raise "git_repository must be an HTTPS URL without credentials (got \"#{url}\")" unless url =~ %r{\Ahttps://}i
    raise "git_repository must not include credentials; use GIT_USERNAME/GIT_TOKEN (got \"#{url}\")" if url =~ %r{\Ahttps://[^/]*@}i
  end

  # Clones repo_url into target_dir. Raises on failure.
  # When GIT_USERNAME and GIT_TOKEN are set, HTTPS URLs are cloned with those credentials.
  # The token is never written to command logs or left on remote.origin.url.
  def self.clone_repo(repo_url, target_dir)
    require_plain_https_repo_url(repo_url)
    parent = File.dirname(target_dir)
    FileUtils.mkdir_p(parent)
    raise "Git clone target already exists: '#{target_dir}'" if File.exist?(target_dir)
    clone_url = authenticated_clone_url(repo_url)
    # Avoid logging credentials embedded in the clone URL.
    log_command = (clone_url == repo_url)
    clone_cmd = "cd \"#{parent}\" && #{git_exe} clone --quiet \"#{clone_url}\" \"#{target_dir}\""
    raise "Git clone failed for '#{repo_url}'" unless Utility.run_cmd(clone_cmd, log_command, "git clone #{repo_url}")
    # Keep recorded remotes credential-free (hashes / CURRENT_BUILD_* constants).
    if clone_url != repo_url then
      set_url_cmd = "cd \"#{target_dir}\" && #{git_exe} remote set-url origin \"#{repo_url}\""
      raise "Git remote set-url failed for '#{repo_url}'" unless Utility.run_cmd(set_url_cmd, true, "git remote set-url origin #{repo_url}")
    end
  end

  # Checks out gitref in target_dir (commit hash, tag, or branch). Raises on failure.
  def self.checkout_ref(target_dir, gitref)
    raise "Git checkout target not found: '#{target_dir}'" unless File.directory?(target_dir)
    checkout_cmd = "cd \"#{target_dir}\" && #{git_exe} checkout --quiet \"#{gitref}\""
    raise "Git checkout failed for '#{gitref}' in '#{target_dir}'" unless Utility.run_cmd(checkout_cmd, true, "git checkout #{gitref}")
  end

  # Clones repo_url into target_dir and checks out gitref (commit hash, tag, or branch). Raises on failure.
  def self.clone_and_checkout(repo_url, target_dir, gitref)
    clone_repo(repo_url, target_dir)
    checkout_ref(target_dir, gitref)
  end

  #
  # Private section
  #
  private

  # Resolves gitref to a full commit hash in the repo at path, or nil.
  def self.resolve_commit(path, gitref)
    return nil if gitref.nil? || gitref.to_s.empty?
    # Peel annotated tags to the commit (^{commit}); works for hashes/branches/tags.
    return run_git(path, "rev-parse \"#{gitref.to_s.gsub('"', '')}^{commit}\"")
  end

  # Returns repo_url with GIT_USERNAME:GIT_TOKEN embedded when both env vars are set.
  # Caller must pass a plain HTTPS URL (see require_plain_https_repo_url).
  def self.authenticated_clone_url(repo_url)
    username = ENV['GIT_USERNAME'].to_s
    token = ENV['GIT_TOKEN'].to_s
    return repo_url if username.empty? || token.empty?
    return repo_url.sub(%r{\Ahttps://}i, "https://#{URI.encode_uri_component(username)}:#{URI.encode_uri_component(token)}@")
  end

  # Git executable for shell invocation: PATH name or quoted path when git bin path is set.
  def self.git_exe
    return $build_config.tools.git_bin_path.to_s.empty? ? 'git' : "\"#{$build_config.tools.git_bin_path}git\""
  end

  # Shell stderr redirect for discarding git noise: cmd.exe has no /dev/null (use 2>nul); Unix uses 2>/dev/null.
  def self.git_stderr_null
    return (RUBY_PLATFORM =~ /mswin|mingw|cygwin/) ? '2>nul' : '2>/dev/null'
  end

  # Runs a git command from the directory of path.
  # Returns trimmed output as string, or nil on empty output / error.
  def self.run_git(path, args)
    return nil if path.nil? || !File.exist?(path)
    dir = File.directory?(path) ? path : File.dirname(path)
    curr_dir = Dir.pwd
    Dir.chdir(dir)
    cmd = "#{git_exe} #{args} #{git_stderr_null}"
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

  # Walk parents of path looking for a `.git` entry; return that directory or nil.
  def self.find_git_repo_root_by_dot_git(path)
    return nil if path.nil? || path.to_s.empty?
    start = File.exist?(path) ? (File.directory?(path) ? path : File.dirname(path)) : nil
    return nil if start.nil?
    dir = File.expand_path(start)
    loop do
      return dir.fix_pathname.chomp('/') if File.exist?(File.join(dir, '.git'))
      parent = File.expand_path('..', dir)
      return nil if parent == dir
      dir = parent
    end
  end

end
