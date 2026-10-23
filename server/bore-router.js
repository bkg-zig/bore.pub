#!/usr/bin/env node
// bore-router.js - route https://<app>.eysho.info to the bore port that app
// asked for. Dependency free.
//
// Run this on the machine that runs `bore server`. A TLS terminator (Caddy,
// see Caddyfile) sits in front and forwards plain HTTP + WebSocket upgrades
// here, preserving the Host header.
//
// The port for an app is deterministic, so the server never needs to talk to
// the Colab client:
//
//     port = PORT_BASE + hash(appName) % PORT_RANGE
//
// with the same hash implementation as auto-tunnel.sh:
//
//     h = 0; for each byte: h = (h * 131 + byte) % 1000003
//
// "pinokio" is special-cased to PINOKIO_PORT (the auth-proxied pinokiod), so
// https://pinokio.eysho.info is the Pinokio UI itself.
//
// Env:
//   DOMAIN        eysho.info          base domain (host must end with it)
//   PORT_BASE     43000               first port in the app range
//   PORT_RANGE    1000                size of the app range
//   PINOKIO_PORT  42000               port used for pinokio.<domain>
//   HTTP_PORT     8080                where this router listens
//   BIND          127.0.0.1           bind address
"use strict";

const http = require("http");
const net = require("net");
const { URL } = require("url");

const DOMAIN = (process.env.DOMAIN || "eysho.info").toLowerCase();
const PORT_BASE = Number(process.env.PORT_BASE || 43000);
const PORT_RANGE = Number(process.env.PORT_RANGE || 1000);
const PINOKIO_PORT = Number(process.env.PINOKIO_PORT || 42000);
const HTTP_PORT = Number(process.env.HTTP_PORT || 8080);
const BIND = process.env.BIND || "127.0.0.1";

function normalize(name) {
  return String(name || "")
    .toLowerCase()
    .replace(/\.git$/, "")
    .replace(/[^a-z0-9-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 40);
}

function hashName(name) {
  let h = 0;
  for (const ch of Buffer.from(name, "utf8")) h = (h * 131 + ch) % 1000003;
  return h;
}

function portFor(name) {
  if (name === "pinokio") return PINOKIO_PORT;
  return PORT_BASE + (hashName(name) % PORT_RANGE);
}

function hostName(header) {
  if (!header) return "";
  const host = String(header).split(",")[0].trim().toLowerCase();
  const bare = host.replace(/:\d+$/, "");
  if (bare === DOMAIN) return "pinokio";
  if (!bare.endsWith("." + DOMAIN)) return "";
  return normalize(bare.slice(0, -(DOMAIN.length + 1)).split(".")[0]);
}

function proxy(req, res, port) {
  const headers = Object.assign({}, req.headers);
  headers.host = `127.0.0.1:${port}`;
  delete headers["x-forwarded-for"];
  if (req.socket.remoteAddress) headers["x-forwarded-for"] = req.socket.remoteAddress;
  headers["x-forwarded-proto"] = req.headers["x-forwarded-proto"] || "https";

  const upstream = http.request(
    {
      host: "127.0.0.1",
      port,
      method: req.method,
      path: req.url,
      headers,
    },
    (up) => {
      res.writeHead(up.statusCode || 502, up.headers);
      up.pipe(res);
    },
  );

  upstream.on("error", (err) => {
    if (!res.headersSent) {
      res.writeHead(502, { "content-type": "text/plain; charset=utf-8" });
    }
    res.end(
      `no tunnel on port ${port} for this name\n` +
        `start the app in Pinokio so it asks bore for that port\n` +
        `(${err.code || err.message})\n`,
    );
  });

  upstream.setTimeout(0);
  req.pipe(upstream);
}

const server = http.createServer((req, res) => {
  // Caddy on-demand TLS check: only issue certs for our own subdomains.
  if (req.url && req.url.startsWith("/ask")) {
    const query = new URL(req.url, "http://localhost").searchParams;
    const domain = (query.get("domain") || "").toLowerCase();
    const ok = domain === DOMAIN || domain.endsWith("." + DOMAIN);
    res.writeHead(ok ? 200 : 404, { "content-type": "text/plain" });
    return res.end(ok ? "ok" : "no");
  }
  if (req.url === "/_health") {
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(JSON.stringify({ ok: true, domain: DOMAIN, base: PORT_BASE, range: PORT_RANGE }));
  }

  const name = hostName(req.headers.host);
  if (!name) {
    res.writeHead(421, { "content-type": "text/plain" });
    return res.end(`unknown host, expected <app>.${DOMAIN}\n`);
  }
  proxy(req, res, portFor(name));
});

// WebSocket and other upgrades.
server.on("upgrade", (req, socket, head) => {
  const name = hostName(req.headers.host);
  const port = name ? portFor(name) : 0;
  if (!port) {
    socket.end("HTTP/1.1 421 Misdirected Request\r\n\r\n");
    return;
  }
  const upstream = net.connect(port, "127.0.0.1", () => {
    const headers = Object.assign({}, req.headers, { host: `127.0.0.1:${port}` });
    let raw = `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`;
    for (const [k, v] of Object.entries(headers)) {
      for (const item of Array.isArray(v) ? v : [v]) raw += `${k}: ${item}\r\n`;
    }
    upstream.write(raw + "\r\n");
    if (head && head.length) upstream.write(head);
    upstream.pipe(socket);
    socket.pipe(upstream);
  });
  upstream.on("error", () => socket.destroy());
  socket.on("error", () => upstream.destroy());
});

server.listen(HTTP_PORT, BIND, () => {
  console.log(
    `router: <app>.${DOMAIN} on ${BIND}:${HTTP_PORT} -> 127.0.0.1:${PORT_BASE}-${PORT_BASE + PORT_RANGE - 1} (pinokio -> ${PINOKIO_PORT})`,
  );
});
