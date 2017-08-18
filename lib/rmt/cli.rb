require 'thor'

class RMT::CLI < Thor

    class << self

      # monkey patch for the output of the help command
      # (removes the alphabetical sorting and adds some custom behavior)
      def help(shell, subcommand = false)
        list = printable_commands(true, subcommand)
        Thor::Util.thor_classes_in(self).each do |klass|
          list += klass.printable_commands(false)
        end

        list.reject! { |l| l[0].split[1] == 'help' }

        if defined?(@package_name) && @package_name
          shell.say "#{@package_name} commands:"
        else
          shell.say 'Commands:'
        end

        shell.print_table(list, indent: 2, truncate: true)
        shell.say
        class_options_help(shell)

        shell.say "Run '#{basename} help COMMAND' for more information on a command."
      end

    end

end
