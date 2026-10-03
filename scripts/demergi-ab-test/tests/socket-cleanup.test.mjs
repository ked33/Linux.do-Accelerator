import assert from "node:assert/strict";
import net from "node:net";
import { once } from "node:events";
import { resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";
import test from "node:test";

const sourceDir = process.env.DEMERGI_SOURCE_DIR;
const moduleUrl = sourceDir
  ? pathToFileURL(resolve(sourceDir, "src/proxy.js"))
  : new URL("../../../.demergi-work/linux_do_proxy/demergi/src/proxy.js", import.meta.url);
const { DemergiProxy } = await import(moduleUrl.href);
const crlf = String.fromCharCode(13, 10);

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

async function waitUntil(predicate, message) {
  const deadline = Date.now() + 1500;
  while (!predicate() && Date.now() < deadline) await delay(5);
  assert.ok(predicate(), message);
}

async function openProxyClient(proxy, targetPort) {
  const port = [...proxy.servers][0].address().port;
  const client = net.connect({ host: "127.0.0.1", port });
  client.on("error", () => {});
  await once(client, "connect");
  client.write([
    `CONNECT pending.invalid:${targetPort} HTTP/1.1`,
    `Host: pending.invalid:${targetPort}`,
    "",
    "",
  ].join(crlf));
  return client;
}

async function pendingConnection(t, { inactivityTimeout = 60000, targetPort = 443 } = {}) {
  const started = deferred();
  const lookup = deferred();
  const proxy = new DemergiProxy({
    addrs: ["127.0.0.1:0"],
    inactivityTimeout,
    resolver: { resolve() { started.resolve(); return lookup.promise; } },
  });
  const sockets = new Set();
  let client;
  t.after(async () => {
    client?.destroy();
    // Retain references independently so a failing test can clean up sockets
    // that the old timeout handler removed from the proxy's tracking set.
    for (const socket of sockets) socket.destroy();
    for (const socket of proxy.sockets) socket.destroy();
    await proxy.stop();
  });
  await proxy.start();
  client = await openProxyClient(proxy, targetPort);
  await started.promise;
  for (const socket of proxy.sockets) sockets.add(socket);
  const upstream = [...sockets].find((socket) => socket.connecting);
  assert.ok(upstream, "upstream is waiting for the controlled DNS answer");
  return { proxy, client, upstream, lookup, sockets };
}

test("client cancellation destroys an upstream still resolving DNS", { timeout: 5000 }, async (t) => {
  const { client, upstream, proxy } = await pendingConnection(t);
  client.destroy();
  await waitUntil(() => upstream.destroyed, "cancelled upstream must be destroyed without connecting");
  await waitUntil(() => proxy.sockets.size === 0, "closed sockets must leave the tracking set");
  assert.equal(upstream.connecting, false);
  assert.equal(upstream.listenerCount("connect"), 0);
});

test("inactivity timeout destroys both sides of a pending connection", { timeout: 5000 }, async (t) => {
  const { client, upstream, proxy, sockets } = await pendingConnection(t, { inactivityTimeout: 50 });
  client.resume();
  await waitUntil(() => upstream.destroyed, "timeout must cancel the pending connect");
  await waitUntil(() => [...sockets].every((socket) => socket.destroyed), "timeout must destroy both sockets");
  await waitUntil(() => proxy.sockets.size === 0, "tracking is removed after closure");
});

test("stopping the proxy cancels pending upstream connections", { timeout: 5000 }, async (t) => {
  const { proxy, upstream } = await pendingConnection(t);
  await proxy.stop();
  assert.equal(upstream.destroyed, true);
  assert.equal(upstream.connecting, false);
  await waitUntil(() => proxy.sockets.size === 0, "stop must leave no tracked sockets");
});

test("a late DNS answer cannot reopen a cancelled connection", { timeout: 5000 }, async (t) => {
  const accepted = new Set();
  const server = net.createServer((socket) => {
    accepted.add(socket);
    socket.on("error", () => {});
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(async () => {
    for (const socket of accepted) socket.destroy();
    await new Promise((done) => server.close(done));
  });
  const { proxy, client, upstream, lookup } = await pendingConnection(t, { targetPort: server.address().port });
  const downstream = [...proxy.sockets].find((socket) => socket !== upstream);
  const closed = new Promise((done) => downstream.once("close", done));
  client.destroy();
  await closed;
  lookup.resolve([{ address: "127.0.0.1", family: 4 }]);
  await delay(100);
  assert.equal(accepted.size, 0, "a cancelled request must never contact its upstream");
  assert.equal(upstream.destroyed, true);
});

test("normal CONNECT traffic still relays in both directions", { timeout: 5000 }, async (t) => {
  const accepted = new Set();
  const server = net.createServer((socket) => {
    accepted.add(socket);
    socket.on("error", () => {});
    socket.pipe(socket);
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const proxy = new DemergiProxy({
    addrs: ["127.0.0.1:0"],
    resolver: { async resolve() { return [{ address: "127.0.0.1", family: 4 }]; } },
  });
  let client;
  t.after(async () => {
    client?.destroy();
    for (const socket of proxy.sockets) socket.destroy();
    for (const socket of accepted) socket.destroy();
    await proxy.stop();
    await new Promise((done) => server.close(done));
  });
  await proxy.start();
  client = await openProxyClient(proxy, server.address().port);
  let received = Buffer.alloc(0);
  client.on("data", (data) => { received = Buffer.concat([received, data]); });
  const response = Buffer.from(`HTTP/1.1 200 Connection Established${crlf}${crlf}`);
  await waitUntil(() => received.length >= response.length, "proxy must accept CONNECT");
  assert.deepEqual(received, response);
  const payload = Buffer.from("connection lifecycle regression check ".repeat(512));
  client.write(payload);
  await waitUntil(() => received.length >= response.length + payload.length, "upstream response must reach client");
  assert.deepEqual(received.subarray(response.length), payload);
  client.destroy();
  await waitUntil(() => proxy.sockets.size === 0, "normal connection must clean up");
});
