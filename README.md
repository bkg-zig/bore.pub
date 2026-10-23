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

## Run

```bash
~/pinokiod/start.sh
```

```
[start] pinokiod ready: http://localhost:42000
[start] starting auth proxy on 127.0.0.1:42001
[start] opening bore tunnel to bore.pub (port 42001)

  === PINOKIO IS LIVE ===

  Public : http://bore.pub:57835
  User   : pinokio
  Pass   : kTJf5aM7H9er
```

Ctrl-C stops the tunnel, the proxy and the server together.

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
| `PORT` | `42000` | local port pinokiod listens on |
| `BORE_SERVER` | `bore.pub` | tunnel server |
| `BORE_PORT` | `0` (random) | requested public port |
| `BORE_SECRET` | unset | shared secret for a self-hosted bore server |
| `NO_TUNNEL` | `0` | `1` = local only, no tunnel |
| `AUTH` | `1` | `0` = no password (not recommended) |
| `AUTH_USER` | `pinokio` | Basic Auth username |
| `AUTH_PASS` | random | Basic Auth password (auto-generated, printed) |
| `AUTH_PORT` | `PORT+1` | local auth proxy port |
| `PINOKIO_DIR` | `~/pinokiod` | pinokiod checkout |
| `PINOKIO_HOME` | `~/.pinokio` | Pinokio state dir (apps, downloads) |
| `LOG_DIR` | `$PINOKIO_DIR/logs` | log output |
| `URL_FILE` | `url.md` next to `start.sh` | live-URL status file |
| `URL_PUSH` | `0` | `1` = commit + push `url.md` on every start/stop |

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

`start.sh` rewrites `url.md` twice per session: once when the tunnel is up, once on shutdown.

```markdown
## http://bore.pub:17731
```

Set `URL_PUSH=1` to also commit and push it, so the file on GitHub always shows whether the tunnel is live. That needs push access to the repo containing `url.md` (an SSH deploy key with write access works). Without it, the file is still updated locally.

Note the URL is **random on every launch** and dies with the process — `url.md` is a status indicator, not a permanent address. See below for a stable URL.


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
start.sh       # pinokiod -> auth proxy -> bore tunnel, clean shutdown
auth-proxy.js  # Basic Auth + WebSocket reverse proxy
url.md         # current tunnel URL, rewritten by start.sh
```

## License

MIT (scripts). `pinokiod` and `bore` keep their own licenses.
