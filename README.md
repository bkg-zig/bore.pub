# bore.pub

Install [pinokiod](https://github.com/pinokiocomputer/pinokiod) (the Pinokio backend) and expose it through a [bore](https://github.com/ekzhang/bore) tunnel, so you can drive Pinokio from any browser.

```
pinokiod  ->  127.0.0.1:42000  ->  bore local 42000 --to bore.pub  ->  http://bore.pub:<random>
```

## Install

Debian/Ubuntu, as root:

```bash
curl -fsSL https://raw.githubusercontent.com/bkg-zig/bore.pub/main/install.sh | sudo bash
```

Installs Node.js 20, bore, git + build tooling, clones `pinokiod` into `~/pinokiod`, runs `npm ci --omit=dev`, and installs the [auto-tunnel plugin](https://github.com/bkg-zig/bore_pinokio_pluckin-bKG) that lists live URLs in the Pinokio dashboard.

Add `--start` to install **and** launch in one command (safe to re-run on a fresh Colab runtime):

```bash
curl -fsSL https://raw.githubusercontent.com/bkg-zig/bore.pub/main/install.sh | sudo bash -s -- --start
```

It prints the live URL and password when the tunnel is up.

## Run

```bash
~/pinokiod/start.sh
```

```
[start] pinokiod ready: http://localhost:42000
[start] starting auth proxy on 127.0.0.1:42001
[start] starting app auto-tunnel (Pinokio app ports only)
[start] opening bore tunnel to bore.pub (port 42001)

  === PINOKIO IS LIVE ===

  URL  : http://bore.pub:46490
  User : bkg
  Pass : -tQUw7qVh4Mc

  Supervised: a dropped tunnel reconnects and updates url.md.
  Stop with: ~/pinokiod/stop.sh
```

**The URL stays the same as long as the process is not killed.** It only changes if the bore connection itself drops, because bore.pub hands out a random port per connection — and in that case `start.sh` reconnects, rewrites `url.md` and the dashboard entry automatically, then prints the new URL.

`start.sh` supervises pinokiod, the auth proxy, the tunnel and the app watcher: any of them dying is restarted in place. Stop it with `stop.sh` (never `pkill`):

```bash
~/pinokiod/stop.sh     # clean shutdown, by pidfile
~/pinokiod/status.sh   # what runs, live URL, every app tunnel
```

### The long way

```bash
cd ~/pinokiod
node script/index &
bore local 42000 --to bore.pub
```

## Options

All via environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | `42000` | pinokiod hardcodes this upstream; other values are ignored with a warning |
| `BORE_SERVER` | `bore.pub` | tunnel server |
| `BORE_PORT` | `0` (random) | requested public port |
| `BORE_SECRET` | unset | shared secret for a self-hosted bore server |
| `NO_TUNNEL` | `0` | `1` = local only, no tunnel |
| `AUTH` | `1` | `0` = no password (not recommended) |
| `AUTH_USER` | `bkg` | Basic Auth username |
| `AUTH_PASS` | random each start | Basic Auth password (printed + written to `url.md`) |
| `AUTH_PORT` | `PORT+1` | local auth proxy port |
| `PINOKIO_DIR` | `~/pinokiod` | pinokiod checkout |
| `PINOKIO_HOME` | `~/.pinokio` | Pinokio state dir (apps, downloads) |
| `LOG_DIR` | `$PINOKIO_DIR/logs` | log output |
| `AUTO_APPS` | `1` | `0` = do not tunnel app ports |
| `PUBLIC_DOMAIN` | unset | e.g. `eysho.info` → stable `https://<app>.<domain>` names |
| `PORT_BASE` | `43000` | first deterministic app port (must match the server) |
| `PORT_RANGE` | `1000` | size of the deterministic app port range |
| `ALLOW_PORTS` | unset | extra ports to tunnel regardless of owner |
| `URL_FILE` | `url.md` next to `start.sh` | live-URL status file (local, gitignored) |
| `URL_SHOW_PASS` | `1` | `0` = keep the password out of `url.md` |
| `URL_PUSH` | `0` | `1` = commit + push the URL (needs `URL_SHOW_PASS=0`) |

## Auth

`pinokiod` has **no authentication**. bore is a raw TCP tunnel, so publishing it exposes a shell, a file API and a terminal. `start.sh` therefore puts [`auth-proxy.js`](auth-proxy.js) in front of it and tunnels *that*:

```
bore.pub  ->  auth-proxy :42001 (Basic Auth)  ->  pinokiod :42000
```

The proxy handles plain HTTP and WebSocket upgrades (the terminal), returns `401` with `WWW-Authenticate`, compares passwords in constant time and strips credentials before forwarding. Password goes to `logs/credentials.txt` (`chmod 600`) and the console — never into `url.md` or git.

`AUTH=0` disables it. Don't, on a public tunnel.


Examples:

```bash
PORT=8080 ./start.sh
NO_TUNNEL=1 ./start.sh
BORE_PORT=12345 ./start.sh
BORE_SERVER=tunnel.example.com BORE_SECRET=xyz ./start.sh
URL_PUSH=1 ./start.sh          # keep url.md on GitHub in sync
```

## url.md

`start.sh` rewrites `url.md` whenever the tunnel comes up, reconnects, or shuts down. It is **local only** (gitignored) because it contains the current password.

```markdown
## http://bore.pub:46490

| | |
|---|---|
| User | `bkg` |
| Password | `-tQUw7qVh4Mc` |
```

`status.sh` prints the same thing, plus every app tunnel.

Set `URL_SHOW_PASS=0` to leave the password to `logs/credentials.txt` and the console. With that set, `URL_PUSH=1` additionally commits and pushes `url.md`, so GitHub always shows whether the tunnel is live. That needs push access to this repo (an SSH deploy key with write access works).

## Colab / ephemeral machines

Runtimes like Colab are wiped when the session ends, so `/content` and `~/.pinokio` are lost. Only GitHub survives:

```bash
# after a new runtime comes up
curl -fsSL https://raw.githubusercontent.com/bkg-zig/bore.pub/main/install.sh | sudo bash
~/pinokiod/start.sh
```

`install.sh` is idempotent and pulls the latest `start.sh`, `stop.sh`, `status.sh`, `auth-proxy.js` and the auto-tunnel plugin. You get a new tunnel URL and a new password, printed at startup and written to `url.md`.

## Private server on your own domain

bore.pub gives a random port. Your own bore server gives **stable names**: `https://pinokio.eysho.info` for the UI and `https://<app-name>.eysho.info` for every app. bore is raw TCP, so a tiny subdomain router sits in front of it (deterministic port per app name, no shared state):

```
https://app.eysho.info  ->  Caddy (TLS)  ->  bore-router  ->  127.0.0.1:<port>
                                                                  |
                                                          bore server (eysho.info)
                                                                  |
                                                     Colab: pinokiod / the app
```

**On the server that owns the domain:**

```bash
git clone https://github.com/bkg-zig/bore.pub && cd bore.pub
sudo DOMAIN=eysho.info BORE_SECRET="$(openssl rand -hex 16)" \
     ./server/install-bore-server.sh --with-caddy
```

DNS: `A` records for `eysho.info` and `*.eysho.info` → that host.
Firewall: `22`, `80`, `443`, `7835/tcp`, `42000-43999/tcp`.

**On the Colab GPU runtime** (or any machine):

```bash
BORE_SERVER=eysho.info BORE_SECRET=<secret> BORE_PORT=42000 \
PUBLIC_DOMAIN=eysho.info ./start.sh
```

That yields:

| URL | What |
|---|---|
| `https://pinokio.eysho.info` | Pinokio UI, Basic Auth (`bkg` + random password) |
| `https://<app>.eysho.info` | each app you start in Pinokio |

How names are derived: the app directory under `~/.pinokio/api` (`stable-diffusion` → `https://stable-diffusion.eysho.info`), port `43000 + hash(name) % 1000`. The server computes the same hash, so it needs no registry. One subdomain per app: if an app listens on several ports, the first one owns the name. If the port is taken, the client retries instead of pointing the name somewhere else.

`PORT_BASE` and `PORT_RANGE` must match on both sides (defaults `43000`, `1000`).

## Colab GPU runtime

Uses [google-colab-cli](https://github.com/googlecolab/google-colab-cli):

```bash
pip install google-colab-cli

BORE_SECRET=<secret> ./colab/colab-up.sh          # T4 by default
GPU=L4 SESSION=pinokio ./colab/colab-up.sh        # other accelerators
```

`colab-up.sh` provisions the runtime (`colab new --gpu T4`), runs `install.sh --start` inside it, and prints the live URL and password. Then open `https://pinokio.eysho.info` and install apps from the Pinokio UI — each one appears at `https://<app>.eysho.info` as soon as it listens.

Keep the runtime from idling out (Colab reclaims idle kernels):

```bash
./colab/keepalive.sh      # second terminal, pokes the kernel every 4 min
```

Teardown: `colab stop -s pinokio`. Everything on the VM is ephemeral; the repo plus `install.sh` is all you need to rebuild.

## Stable URLs (self-hosted server)

`bore.pub` hands out a **random port on every launch**, so the public URL changes each restart. For a stable endpoint, run your own server:

```bash
# on a VPS with a public IP
bore server --secret "$SECRET"          # TCP 7835

# on the Pinokio machine
BORE_SERVER=your-vps.example.com BORE_SECRET="$SECRET" BORE_PORT=42000 ./start.sh
```

## Security

Apps tunnelled by the auto-tunnel plugin are **not** authenticated — that plugin exposes whatever the app exposes. Pinokio itself is protected by the Basic Auth proxy above. Only tunnel on a host you are willing to expose, and prefer a self-hosted `bore server` with `--secret` on a private network.

## Layout

```
install.sh     # node + bore + pinokiod + npm deps + auto-tunnel plugin
server/        # install-bore-server.sh, bore-router.js, Caddyfile (own domain)
colab/         # colab-up.sh, keepalive.sh (google-colab-cli, GPU runtime)
start.sh       # pinokiod -> auth proxy -> bore tunnel, supervised
stop.sh        # clean shutdown via pidfile
status.sh      # what runs, live URL, every app tunnel
auth-proxy.js  # Basic Auth + WebSocket reverse proxy
url.md         # current URL + password, local only (gitignored)
```

## License

MIT (scripts). `pinokiod` and `bore` keep their own licenses.
