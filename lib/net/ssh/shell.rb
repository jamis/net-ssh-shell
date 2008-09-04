require 'digest/sha1'
require 'net/ssh'
require 'net/ssh/shell/process'
require 'net/ssh/shell/subshell'

module Net
  module SSH
    class Shell
      attr_reader :session
      attr_reader :channel
      attr_reader :state
      attr_reader :shell
      attr_reader :processes

      def initialize(session, shell=:default)
        @session = session
        @shell = shell
        @state = :closed
        @processes = []
      end

      def open!
        if closed?
          @state = :opening
          @channel = session.open_channel(&method(:open_succeeded))
          @channel.on_open_failed(&method(:open_failed))
          session.loop { opening? }
        end
      end

      def open?
        state == :open
      end

      def closed?
        state == :closed
      end

      def opening?
        !open? && !closed?
      end

      def execute(command, klass=Net::SSH::Shell::Process, &callback)
        callback ||= Proc.new { |ch, data| print(data) }
        process = klass.new(self, command, callback)
        process.run if processes.empty?
        processes << process
        return process
      end

      def subshell(command, &callback)
        callback ||= Proc.new { |ch, data| }
        execute(command, Net::SSH::Shell::Subshell, &callback)
      end

      def execute!(command, &callback)
        execute(command, &callback)
        wait!
      end

      def wait!
        session.loop { processes.any? }
      end

      def child_finished(child)
        processes.delete(child)
        processes.first.run if processes.any?
      end

      def separator
        @separator ||= begin
          s = Digest::SHA1.hexdigest([session.host, Time.now.to_i, Time.now.usec, rand(0xFFFFFFFF)].join(":"))
          s << Digest::SHA1.hexdigest(s)
        end
      end

      private

        def open_succeeded(channel)
          @state = :pty
          channel.on_close(&method(:on_close))
          channel.request_pty(:modes => { Net::SSH::Connection::Term::ECHO => 0 }, &method(:pty_requested))
        end

        def open_failed(channel, code, description)
          @state = :closed
          raise "could not open channel for process manager (#{description}, ##{code})"
        end

        def pty_requested(channel, success)
          @state = :shell
          raise "could not request pty for process manager" unless success
          if shell == :default
            channel.send_channel_request("shell", &method(:shell_requested))
          else
            channel.exec(shell, &method(:shell_requested))
          end
        end

        def shell_requested(channel, success)
          @state = :initializing
          raise "could not request shell for process manager" unless success
          channel.on_data(&method(:look_for_initialization_done))
          channel.send_data "export PS1='#{separator} $?'\n"
        end

        def look_for_initialization_done(channel, data)
          @state = :open if data.include?(separator)
        end

        def on_close(channel)
          @state = :closed
          @channel = nil
        end
    end
  end
end

class Net::SSH::Connection::Session
  # Provides a convenient way to initialize a shell given a Net::SSH
  # session. Yields the new shell if a block is given. Returns the shell
  # instance.
  def shell(*args)
    shell = Net::SSH::Shell.new(self, *args)
    yield shell if block_given?
    return shell
  end
end