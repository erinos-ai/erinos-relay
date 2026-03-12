# ErinOS Relay

Cloud relay for ErinOS appliances. Provides two services:

1. **OAuth** — Holds provider client credentials and handles OAuth flows so appliances never need client secrets.
2. **Tunnel** — WebSocket tunnel for remote access. Supports multiple appliances, each identified by a unique `TUNNEL_KEY`.

## How it works

### OAuth

1. Erin calls `/oauth/start` with a provider name — the relay builds the OAuth URL using its stored client credentials
2. The user authorizes in their browser — the provider redirects to `/oauth/callback` where the relay exchanges the code for tokens
3. Erin polls `/oauth/poll` to retrieve the tokens and stores them locally
4. When tokens expire, Erin calls `/oauth/refresh` — the relay uses the client secret to get a new access token

### Tunnel

Each appliance has a unique `TUNNEL_KEY` (a random token). The same key is used by both the appliance and its clients:

1. The appliance opens a WebSocket to `/tunnel` with `Authorization: Bearer <TUNNEL_KEY>`
2. Clients call `POST /api/chat` with `Authorization: Bearer <TUNNEL_KEY>`
3. The relay matches the key to the correct appliance and forwards the request through the WebSocket

Multiple appliances can connect simultaneously — each with its own key. No port forwarding, VPN, or Tailscale required.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/oauth/start` | Start an OAuth flow |
| GET | `/oauth/callback` | OAuth callback from provider |
| GET | `/oauth/poll` | Poll for tokens |
| POST | `/oauth/refresh` | Refresh an expired token |
| GET | `/tunnel` | WebSocket — appliance connects here (Bearer auth) |
| POST | `/api/chat` | Proxied to appliance via tunnel (Bearer auth) |
| GET | `/health` | Health check (shows connected appliance count) |

## Adding a provider

1. Add the provider's OAuth config to `providers.yml`
2. Add `PROVIDER_CLIENT_ID` and `PROVIDER_CLIENT_SECRET` to `.env`
3. Redeploy

## Deploy to Fly.io

```
cp .env.example .env   # fill in HOST and OAuth client credentials
./deploy.sh
```

On first run, the script launches the app and adds a TLS certificate for your `HOST` domain. Add the CNAME record Fly gives you to your DNS. Subsequent runs update secrets and redeploy.

## Appliance setup

Generate a random key and set it in the appliance's `.env`:

```
RELAY_URL=https://relay.erinos.ai
TUNNEL_KEY=<random-token>
```

Use the same `TUNNEL_KEY` in your iPhone Shortcut's Authorization header to reach this appliance remotely.
