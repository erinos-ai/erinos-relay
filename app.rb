# frozen_string_literal: true

require "sinatra/base"
require "json"
require "yaml"
require "uri"
require "net/http"
require "base64"
require "timeout"

require_relative "store/memory"
require_relative "routes/oauth"
require_relative "routes/tunnel"

class Relay < Sinatra::Base
  set :host_authorization, permitted: :all

  PROVIDERS = YAML.load_file(File.expand_path("providers.yml", __dir__))

  # Swappable stores — replace with Store::Redis.new(url) to scale horizontally.
  # Sessions: OAuth flow state (TTL-based).
  # Registry: which tunnel key is connected (and on which machine, for multi-machine).
  SESSIONS = Store::Memory.new
  REGISTRY = Store::Memory.new

  helpers do
    def json(data)
      content_type :json
      data.to_json
    end

    def exchange_code(session, code, redirect_uri)
      token_post(session[:token_url], session[:client_id], session[:client_secret], session[:token_auth], {
        code: code,
        redirect_uri: redirect_uri,
        grant_type: "authorization_code"
      })
    end

    def token_post(url, client_id, client_secret, token_auth, form_data)
      uri = URI(url)

      if token_auth == "basic"
        req = Net::HTTP::Post.new(uri)
        req.basic_auth(client_id, client_secret)
        req.set_form_data(form_data)
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      else
        response = Net::HTTP.post_form(uri, form_data.merge(client_id: client_id, client_secret: client_secret))
      end

      JSON.parse(response.body)
    end
  end

  register Routes::OAuth
  register Routes::Tunnel

  get "/health" do
    json(status: "ok", appliances: REGISTRY.size)
  end
end
