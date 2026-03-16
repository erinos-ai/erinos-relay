# frozen_string_literal: true

module Routes
  module OAuth
    TTL = 300 # seconds

    def self.registered(app)
      # Called by Erin to start an OAuth flow.
      app.post "/oauth/start" do
        body = JSON.parse(request.body.read)
        provider = body["provider"]
        state = body["state"]

        config = Relay::PROVIDERS[provider]
        unless config
          status 400
          return json(error: "Unknown provider: #{provider}")
        end

        client_id = ENV["#{provider.upcase}_CLIENT_ID"]
        client_secret = ENV["#{provider.upcase}_CLIENT_SECRET"]

        unless client_id && client_secret
          status 400
          return json(error: "No credentials configured for provider: #{provider}")
        end

        Relay::SESSIONS.set(state, {
          provider: provider,
          client_id: client_id,
          client_secret: client_secret,
          token_url: config["token_url"],
          token_auth: config["token_auth"]
        }, ttl: TTL)

        auth_params = {
          client_id: client_id,
          redirect_uri: "#{request.base_url}/oauth/callback",
          response_type: "code",
          scope: config["scopes"].join(" "),
          state: state
        }
        auth_params.merge!(config["extra_params"]) if config["extra_params"]

        Relay::SESSIONS.cleanup
        json(url: "#{config['auth_url']}?#{URI.encode_www_form(auth_params)}")
      end

      # OAuth callback from provider.
      app.get "/oauth/callback" do
        state = params["state"]
        code = params["code"]
        error = params["error"]

        if error
          status 400
          return "Authorization failed: #{error}"
        end

        unless state && code
          status 400
          return "Missing state or code parameter."
        end

        session = Relay::SESSIONS.get(state)
        unless session
          status 400
          return "Unknown or expired session."
        end

        tokens = exchange_code(session, code, "#{request.base_url}/oauth/callback")

        if tokens["error"]
          Relay::SESSIONS.delete(state)
          status 400
          return "Token exchange failed: #{tokens['error_description'] || tokens['error']}"
        end

        Relay::SESSIONS.set(state, session.merge(
          tokens: {
            access_token: tokens["access_token"],
            refresh_token: tokens["refresh_token"],
            expires_in: tokens["expires_in"]
          }
        ), ttl: TTL)

        content_type :html
        <<~HTML
          <!DOCTYPE html>
          <html>
          <body style="font-family: sans-serif; text-align: center; padding-top: 100px;">
            <h2>Authorization successful</h2>
            <p>You can close this tab and return to Erin.</p>
          </body>
          </html>
        HTML
      end

      # Polled by Erin to retrieve tokens.
      app.get "/oauth/poll" do
        state = params["state"]

        unless state
          status 400
          return json(error: "Missing state parameter.")
        end

        session = Relay::SESSIONS.get(state)

        unless session&.dig(:tokens)
          status 404
          return json(status: "pending")
        end

        tokens = session[:tokens]
        Relay::SESSIONS.delete(state)
        json(status: "ok", **tokens)
      end

      # Called by Erin to refresh an expired access token.
      app.post "/oauth/refresh" do
        body = JSON.parse(request.body.read)
        provider = body["provider"]

        config = Relay::PROVIDERS[provider]
        unless config
          status 400
          return json(error: "Unknown provider: #{provider}")
        end

        client_id = ENV["#{provider.upcase}_CLIENT_ID"]
        client_secret = ENV["#{provider.upcase}_CLIENT_SECRET"]

        unless client_id && client_secret
          status 400
          return json(error: "No credentials configured for provider: #{provider}")
        end

        tokens = token_post(config["token_url"], client_id, client_secret, config["token_auth"], {
          refresh_token: body["refresh_token"],
          grant_type: "refresh_token"
        })

        if tokens["error"]
          status 400
          return json(error: tokens["error_description"] || tokens["error"])
        end

        json(
          access_token: tokens["access_token"],
          expires_in: tokens["expires_in"]
        )
      end
    end
  end
end
