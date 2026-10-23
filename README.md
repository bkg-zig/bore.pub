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

Installs Node.js 20, bore, git + build tooling, clones `pinokiod` into `~/pinokiod`, and runs `npm ci --omit=dev`.

## Run

```bash
~/pinokiod/start.sh
```

```
[start] starting pinokiod (port 42000)
[start] pinokiod ready: http://localhost:42000
[start] opening bore tunnel to bore.pub

  === PINOKIO IS LIVE ===

  Local : http://localhost:42000
  Public: http://bore.pub:17731
```

Ctrl-C stops the tunnel and the server together.

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
| `PINOKIO_DIR` | `~/pinokiod` | pinokiod checkout |
| `PINOKIO_HOME` | `~/.pinokio` | Pinokio state dir (apps, downloads) |
| `LOG_DIR` | `$PINOKIO_DIR/logs` | log output |

Examples:

```bash
PORT=8080 ./start.sh
NO_TUNNEL=1 ./start.sh
BORE_PORT=12345 ./start.sh
BORE_SERVER=tunnel.example.com BORE_SECRET=xyz ./start.sh
```

## Stable URLs (self-hosted server)

`bore.pub` hands out a **random port on every launch**, so the public URL changes each restart. For a stable endpoint, run your own server:

```bash
# on a VPS with a public IP
bore server --secret "$SECRET"          # TCP 7835

# on the Pinokio machine
BORE_SERVER=your-vps.example.com BORE_SECRET="$SECRET" BORE_PORT=42000 ./start.sh
```

## Security

`pinokiod` has **no authentication layer** — it exposes a shell, a file API, and a terminal. Anything you publish through `bore.pub` is reachable by anyone who has (or guesses) the URL, unencrypted. Only tunnel on a host you are willing to expose, and prefer a self-hosted `bore server` with `--secret` on a private network.

## Layout

```
install.sh   # node + bore + pinokiod + npm deps
start.sh     # pinokiod + bore tunnel, one process tree, clean shutdown
```

## License

MIT (scripts). `pinokiod` and `bore` keep their own licenses.
