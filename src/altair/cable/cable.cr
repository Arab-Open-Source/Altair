module Altair
  # A small channel-based WebSocket broadcaster.
  module Cable
    CHANNELS = {} of String => Array(::HTTP::WebSocket)
    LOCK     = Mutex.new

    def self.subscribe(channel : String, socket : ::HTTP::WebSocket) : Nil
      LOCK.synchronize { (CHANNELS[channel] ||= [] of ::HTTP::WebSocket) << socket }
    end

    def self.unsubscribe(channel : String, socket : ::HTTP::WebSocket) : Nil
      LOCK.synchronize do
        if sockets = CHANNELS[channel]?
          sockets.delete(socket)
          CHANNELS.delete(channel) if sockets.empty?
        end
      end
    end

    # The number of active subscribers on a channel (for testing).
    def self.subscriber_count(channel : String) : Int32
      LOCK.synchronize { CHANNELS[channel]?.try(&.size) || 0 }
    end

    def self.broadcast(channel : String, message : String) : Nil
      sockets = LOCK.synchronize { (CHANNELS[channel]? || [] of ::HTTP::WebSocket).dup }
      sockets.each { |socket| socket.send(message) unless socket.closed? }
    end

    class Handler
      include ::HTTP::Handler

      def initialize(@app : Altair::Application)
      end

      def call(context : ::HTTP::Server::Context) : Nil
        return call_next(context) unless context.request.path == @app.config.cable_path
        ::HTTP::WebSocketHandler.new do |socket, request_context|
          channel = request_context.request.query_params["channel"]? || "default"
          Altair::Cable.subscribe(channel, socket)
          socket.on_message { |message| Altair::Cable.broadcast(channel, message) }
          socket.on_close { Altair::Cable.unsubscribe(channel, socket) }
        end.call(context)
      end
    end
  end
end
