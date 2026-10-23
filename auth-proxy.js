#!/usr/bin/env node
//
// auth-proxy.js - HTTP Basic Auth reverse proxy for pinokiod.
//
// pinokiod has no authentication of its own and bore is a raw TCP tunnel, so
// anything published is open to whoever has the URL. This puts a password in
// front of it without touching pinokiod, and forwards WebSocket upgrades
// (the terminal) as well as plain HTTP.
//
// Env:
//   UPSTREAM_PORT  port pinokiod listens on        (default 42000)
//   LISTEN_PORT    port this proxy listens on      (default 42001)
//   AUTH_USER      username                        (default pinokio)
//   AUTH_PASS      password (required)
//
"use strict";

const http = require("http");
const net = require("net");
const crypto = require("crypto");

const UPSTREAM_HOST = process.env.UPSTREAM_HOST || "127.0.0.1";
const UPSTREAM_PORT = Number(process.env.UPSTREAM_PORT || 42000);
const LISTEN_PORT = Number(process.env.LISTEN_PORT || 42001);
const USER = process.env.AUTH_USER || "pinokio";
const PASS = process.env.AUTH_PASS || "";

if (!PASS) {
  console.error("[auth] AUTH_PASS is required");
  process.exit(1);
}

const EXPECTED = "Basic " + Buffer.from(`${USER}:${PASS}`).toString("base64");

// Constant-time compare so the password cannot be probed by timing.
function authorized(req) {
  const got = req.headers.authorization || "";
  const a = Buffer.from(got);
  const b = Buffer.from(EXPECTED);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function unauthorized(res) {
  res.writeHead(401, {
    "WWW-Authenticate": 'Basic realm="Pinokio", charset="UTF-8"',
    "Content-Type": "text/plain; charset=utf-8",
    "Cache-Control": "no-store",
  });
  res.end("Authentication required\n");
}

function forwardHeaders(req) {
  const headers = {};
  for (const [key, value] of Object.entries(req.headers)) {
    if (key.toLowerCase() === "authorization") continue; // do not leak creds upstream
    headers[key] = value;
  }
  return headers;
}

const server = http.createServer((req, res) => {
  if (!authorized(req)) return unauthorized(res);

  const upstream = http.request(
    {
      host: UPSTREAM_HOST,
      port: UPSTREAM_PORT,
      method: req.method,
      path: req.url,
      headers: forwardHeaders(req),
    },
    (upRes) => {
      res.writeHead(upRes.statusCode || 502, upRes.headers);
      upRes.pipe(res);
    }
  );

  upstream.on("error", (err) => {
    if (!res.headersSent) {
      res.writeHead(502, { "Content-Type": "text/plain; charset=utf-8" });
    }
    res.end(`Upstream error: ${err.message}\n`);
  });

  req.on("error", () => upstream.destroy());
  res.on("close", () => upstream.destroy());
  req.pipe(upstream);
});

// WebSockets (xterm terminal, live logs) arrive as an upgrade request.
server.on("upgrade", (req, socket, head) => {
  socket.on("error", () => {});

  if (!authorized(req)) {
    socket.write(
      "HTTP/1.1 401 Unauthorized\r\n" +
        'WWW-Authenticate: Basic realm="Pinokio", charset="UTF-8"\r\n' +
        "Connection: close\r\n\r\n"
    );
    socket.destroy();
    return;
  }

  const upstream = net.connect(UPSTREAM_PORT, UPSTREAM_HOST, () => {
    const lines = [`${req.method} ${req.url} HTTP/1.1`];
    for (const [key, value] of Object.entries(req.headers)) {
      if (key.toLowerCase() === "authorization") continue;
      for (const v of Array.isArray(value) ? value : [value]) {
        lines.push(`${key}: ${v}`);
      }
    }
    upstream.write(lines.join("\r\n") + "\r\n\r\n");
    if (head && head.length) upstream.write(head);
    upstream.pipe(socket);
    socket.pipe(upstream);
  });

  upstream.on("error", () => socket.destroy());
  socket.on("error", () => upstream.destroy());
  socket.on("close", () => upstream.destroy());
});

server.on("clientError", (err, socket) => {
  if (socket.writable) socket.end("HTTP/1.1 400 Bad Request\r\n\r\n");
});

server.listen(LISTEN_PORT, "127.0.0.1", () => {
  console.log(
    `[auth] http://127.0.0.1:${LISTEN_PORT} -> http://${UPSTREAM_HOST}:${UPSTREAM_PORT} (user: ${USER})`
  );
});

for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 2000).unref();
  });
}
