module Net; module SSH; class Shell

  class Process
    attr_reader :command
    attr_reader :manager
    attr_reader :callback
    attr_reader :exit_status

    def initialize(manager, command, callback)
      @command = command
      @manager = manager
      @callback = callback
    end

    def run
      manager.open!
      manager.channel.on_data(&method(:on_stdout))
      manager.channel.on_extended_data(&method(:on_stderr))
      @master_onclose = manager.channel.on_close(&method(:on_close))

      manager.channel.send_data(command + "\n")
      self
    end

    def running?
      exit_status.nil?
    end

    def wait!
      manager.session.loop { running? }
      self
    end

    private

      def on_stdout(ch, data)
        if data.strip =~ /^#{manager.separator} (\d+)$/
          before = $`
          callback.call(ch, before) unless before.empty?

          ch.on_close(&@master_onclose)
          finished!($1)
        else
          callback.call(ch, data)
        end
      end

      def on_stderr(ch, type, data)
        puts "[stderr] #{data.inspect}"
      end

      def on_close(ch)
        @master_onclose.call(ch)
        finished!(-1)
      end

      def finished!(status)
        @exit_status = status.to_i
        manager.child_finished(self)
      end
  end

end; end; end