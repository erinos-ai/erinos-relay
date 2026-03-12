require "dotenv/load"
require "faye/websocket"
require_relative "app"

Faye::WebSocket.load_adapter("puma")

run Relay
