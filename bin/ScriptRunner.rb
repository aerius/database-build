require 'ScriptCommands.rb'

##
# Basically wraps around ScriptCommands to ensure only its public methods can be called from within the execute() call.
#
class ScriptRunner

  @@script_commands = ScriptCommands.new

  def method_missing(method_sym, *arguments)
    # Note: In Ruby 1.8 the 'methods' array below contains Strings, in 1.9 it contains Symbols.
    if @@script_commands.methods.include?(method_sym) || @@script_commands.methods.include?(method_sym.to_s) then # only public methods
      @@script_commands.send(method_sym, *arguments)
    else
      super
    end
  end

  def execute
    eval(IO.readlines($build_config.session.runscript_file).join, nil, $build_config.session.runscript_file)
  end

end
