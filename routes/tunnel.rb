# frozen_string_literal: true

require "faye/websocket"
require "json"
require "securerandom"
require "thread"

module Routes
  module Tunnel
    LOCK = Mutex.new
    APPLIANCES = {} # tunnel_key => WebSocket
    PENDING = {}    # request_id => Queue

    def self.registered(app)
      # WebSocket endpoint — appliances connect here on boot.
      # Authenticated and routed by TUNNEL_KEY.
      app.get "/tunnel" do
        unless Faye::WebSocket.websocket?(request.env)
          halt 400, json(error: "WebSocket required")
        end

        key = request.env["HTTP_AUTHORIZATION"]&.sub(/^Bearer\s+/, "")
        halt 401, json(error: "unauthorized") unless key&.length&.positive?

        ws = Faye::WebSocket.new(request.env)

        ws.on :open do |_|
          LOCK.synchronize { APPLIANCES[key] = ws }
          puts "[tunnel] Appliance connected (#{key[0..7]}...)"
        end

        ws.on :message do |event|
          begin
            msg = JSON.parse(event.data)
            queue = PENDING[msg["id"]]
            queue&.push(msg)
          rescue JSON::ParserError
            puts "[tunnel] Invalid message"
          end
        end

        ws.on :close do |_|
          LOCK.synchronize { APPLIANCES.delete(key) }
          # Unblock any pending requests for this appliance
          PENDING.each_value { |q| q.push(nil) }
          puts "[tunnel] Appliance disconnected (#{key[0..7]}...)"
        end

        ws.rack_response
      end

      # Proxy endpoint — clients (iPhone, Watch, etc.) call this.
      # Routed to the correct appliance by the same TUNNEL_KEY.
      app.post "/api/chat" do
        key = request.env["HTTP_AUTHORIZATION"]&.sub(/^Bearer\s+/, "")
        halt 401, json(error: "unauthorized") unless key&.length&.positive?

        ws = LOCK.synchronize { APPLIANCES[key] }
        halt 502, json(error: "Appliance not connected") unless ws

        request_id = SecureRandom.uuid
        queue = Queue.new
        PENDING[request_id] = queue

        # Build the tunneled request
        tunnel_request = {
          id: request_id,
          method: "POST",
          path: "/api/chat",
          headers: {
            "Content-Type" => request.content_type,
            "Accept" => request.env["HTTP_ACCEPT"],
            "X-User-ID" => request.env["HTTP_X_USER_ID"]
          }.compact,
          body: request.body.read
        }

        # Handle multipart (audio file upload)
        if params[:file]
          file = params[:file]
          tunnel_request[:headers]["Content-Type"] = "multipart/form-data"
          tunnel_request[:file] = {
            filename: file[:filename],
            type: file[:type],
            data: Base64.strict_encode64(file[:tempfile].read)
          }
          tunnel_request.delete(:body)
        end

        ws.send(JSON.generate(tunnel_request))

        # Wait for response from appliance (30s timeout)
        response = nil
        begin
          Timeout.timeout(30) { response = queue.pop }
        rescue Timeout::Error
          PENDING.delete(request_id)
          halt 504, json(error: "Appliance did not respond in time")
        end
        PENDING.delete(request_id)

        unless response
          halt 502, json(error: "Tunnel closed")
        end

        status response["status"] || 200
        content_type response.dig("headers", "Content-Type") || "application/json"
        if response["body_base64"]
          Base64.strict_decode64(response["body_base64"])
        else
          response["body"] || ""
        end
      end
    end
  end
end
