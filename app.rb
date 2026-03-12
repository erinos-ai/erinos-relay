# frozen_string_literal: true

require "sinatra/base"
require "json"
require "yaml"
require "uri"
require "net/http"
require "base64"
require "timeout"

require_relative "routes/oauth"
require_relative "routes/tunnel"

class Relay < Sinatra::Base
  set :host_authorization, permitted: :all

  PROVIDERS = YAML.load_file(File.expand_path("providers.yml", __dir__))
  SESSIONS = {}
  TTL = 300 # seconds

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

    def cleanup_expired
      cutoff = Time.now - TTL
      SESSIONS.delete_if { |_, v| v[:created_at] < cutoff }
    end
  end

  register Routes::OAuth
  register Routes::Tunnel

  get "/health" do
    count = Routes::Tunnel::LOCK.synchronize { Routes::Tunnel::APPLIANCES.size }
    json(status: "ok", appliances: count)
  end
end
