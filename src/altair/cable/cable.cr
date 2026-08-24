# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Cable`, the production WebSocket broadcaster.
#
# ## Connection lifecycle
# 1. Client opens `GET /cable?channel=<name>` — the framework performs
#    the HTTP Upgrade handshake via Crystal's WebSocketHandler.
# 2. Before accepting, the framework calls `config.cable_auth` (if set)
#    with a `ConnectionContext` carrying the request and channel — reject
#    by returning false (answers 401).
# 3. After upgrade, a per-connection heartbeat fiber pings every
#    `config.cable_heartbeat_interval`; if no pong arrives within
#    `config.cable_pong_budget`, the socket is closed and unsubscribed.
# 4. Messages are JSON envelopes: `{channel, event, data}` — broadcast
#    via `Cable.broadcast(channel, event, data)`, or verbatim via
#    `Cable.broadcast(channel, message)` (two arguments = raw payload).
# 5. On disconnect, the subscriber is removed; empty channels are cleaned up.
require "json"

module Altair
  # A small channel-based WebSocket broadcaster with authentication,
  # heartbeat, JSON envelopes and automatic cleanup.
  module Cable
    struct Envelope
      include JSON::Serializable
      property channel : String
      property event : String
      property data : JSON::Any?

      def initialize(@channel : String, @event : String, @data : JSON::Any? = nil)
      end

      def to_json_string : String
        to_json
      end
    end

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

    def self.subscriber_count(channel : String) : Int32
      LOCK.synchronize { CHANNELS[channel]?.try(&.size) || 0 }
    end

    # Broadcasts a raw message to all subscribers on the channel. Dead
    # sockets are pruned inline without breaking delivery to others.
    def self.broadcast(channel : String, message : String) : Nil
      deliver(channel, message)
    end

    # Broadcasts a structured envelope:
    # ```
    # Cable.broadcast("tweets", "created", {"id" => JSON::Any.new(42)})
    # # → {"channel":"tweets","event":"created","data":{"id":42}}
    # ```
    def self.broadcast(channel : String, event : String, data : JSON::Any?) : Nil
      deliver(channel, Envelope.new(channel, event, data).to_json_string)
    end

    private def self.deliver(channel : String, payload : String) : Nil
      sockets = LOCK.synchronize { (CHANNELS[channel]? || [] of ::HTTP::WebSocket).dup }
      sockets.each do |socket|
        next if socket.closed?
        begin
          socket.send(payload)
        rescue ::IO::Error
          unsubscribe(channel, socket)
        end
      end
    end

    class Handler
      include ::HTTP::Handler

      @connections = [] of ::HTTP::WebSocket
      @conn_lock = Mutex.new

      def initialize(@app : Altair::Application)
      end

      def call(context : ::HTTP::Server::Context) : Nil
        path = context.request.path.chomp('/')
        return call_next(context) unless path == @app.config.cable_path

        config = @app.config
        altair_request = Altair::HTTP::Request.new(context.request)
        ctx = ConnectionContext.new(altair_request, context.request.query_params["channel"]? || "default")

        # Origin check when allowed_origins is configured
        if origins = config.cable_allowed_origins
          origin = context.request.headers["Origin"]?
          unless origin && origins.includes?(origin)
            context.response.status = ::HTTP::Status::FORBIDDEN
            return
          end
        end

        # Auth hook — reject before upgrade if cable_auth returns false
        if auth_hook = config.cable_auth
          unless auth_hook.call(ctx.request, ctx)
            context.response.status = ::HTTP::Status::UNAUTHORIZED
            return
          end
        end

        handler = ::HTTP::WebSocketHandler.new do |socket, _ws_context|
          register_connection(socket)

          channel = ctx.channel
          Altair::Cable.subscribe(channel, socket)

          socket.on_message { |message| Altair::Cable.broadcast(channel, message) }
          socket.on_close { Altair::Cable.unsubscribe(channel, socket) }

          start_heartbeat(socket, config.cable_heartbeat_interval,
            config.cable_pong_budget, channel)
        end
        handler.call(context)
      end

      private def register_connection(socket : ::HTTP::WebSocket) : Nil
        @conn_lock.synchronize { @connections << socket }
        socket.on_close do
          @conn_lock.synchronize { @connections.delete(socket) }
        end
      end

      # Pings periodically; closes the socket if no pong arrives within budget.
      private def start_heartbeat(socket : ::HTTP::WebSocket, interval : Time::Span,
                                  pong_budget : Time::Span, channel : String) : Nil
        spawn(name: "cable-heartbeat") do
          loop do
            sleep(interval)
            break if socket.closed?
            pong_received = false
            socket.on_pong { pong_received = true }

            socket.ping("hb")
            sleep(pong_budget)

            unless pong_received || socket.closed?
              Altair::Cable.unsubscribe(channel, socket)
              socket.close
              break
            end
          end
        end
      end

      # Closes all tracked connections gracefully on server shutdown.
      def shutdown : Nil
        @conn_lock.synchronize { @connections.dup }.each(&.close)
      end
    end

    # Per-connection context passed to the auth hook during handshake.
    class ConnectionContext
      getter request : Altair::HTTP::Request
      getter channel : String
      property current_user_id : String?

      def initialize(@request : Altair::HTTP::Request, @channel : String)
      end
    end
  end
end
