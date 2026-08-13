require 'ScriptCommands.rb'

##
# Basically wraps around ScriptCommands to ensure only its public methods can be called from within the execute() call.
#
class ScriptRunner

  @@script_commands = ScriptCommands.new

  def method_missing(method_sym, *arguments)
    if @@script_commands.methods.include?(method_sym) then # only public methods
      @@script_commands.send(method_sym, *arguments)
    else
      super
    end
  end

  def execute
    eval(IO.readlines($build_config.session.runscript_file).join, nil, $build_config.session.runscript_file)
  end

end
