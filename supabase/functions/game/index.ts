import { createClient } from "npm:@supabase/supabase-js@2";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

// game servers hit this. no jwt, auth is the x-game-key header (we only keep its sha256)
const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

const MAX_BODY = 256_000;
const ID_RE = /^[1-9][0-9]{0,18}$/;
const CHECK_RE = /^[A-Za-z]{1,24}$/;

let keyHash: string | null = null;
let keyHashAt = 0;

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });

async function sha256(text: string) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function sameString(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function expectedHash() {
  // cache for a minute so rotating the key doesn't need a redeploy
  if (keyHash && Date.now() - keyHashAt < 60_000) return keyHash;
  const { data } = await db.rpc("game_secret", { p_name: "game_key_sha256" });
  keyHash = typeof data === "string" ? data : null;
  keyHashAt = Date.now();
  return keyHash;
}

const num = (v: unknown, lo: number, hi: number) =>
  typeof v === "number" && Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : null;

const id = (v: unknown) => {
  const s = typeof v === "number" ? String(Math.trunc(v)) : typeof v === "string" ? v : "";
  return ID_RE.test(s) ? s : null;
};

const str = (v: unknown, max: number) => (typeof v === "string" ? v.slice(0, max) : "");

function cleanCtx(v: unknown) {
  if (!v || typeof v !== "object" || Array.isArray(v)) return {};
  const out: Record<string, string | number | boolean> = {};
  let n = 0;
  for (const [k, val] of Object.entries(v as Record<string, unknown>)) {
    if (n >= 12) break;
    const key = k.slice(0, 24);
    if (typeof val === "number" && Number.isFinite(val)) out[key] = Math.round(val * 1000) / 1000;
    else if (typeof val === "boolean") out[key] = val;
    else if (typeof val === "string") out[key] = val.slice(0, 120);
    else continue;
    n++;
  }
  return out;
}

function arr(v: unknown, max: number): unknown[] {
  return Array.isArray(v) ? v.slice(0, max) : [];
}

function parseSync(body: Record<string, unknown>) {
  const players = arr(body.players, 200).flatMap((p: any) => {
    const pid = id(p?.id);
    const score = num(p?.score, 0, 1e6);
    const peak = num(p?.peak, 0, 1e6);
    return pid && score !== null && peak !== null
      ? [{ id: pid, name: str(p.name, 32), score, peak }]
      : [];
  });

  const flags = arr(body.flags, 500).flatMap((f: any) => {
    const pid = id(f?.id);
    const sev = num(f?.sev, 0, 1e4);
    const score = num(f?.score, 0, 1e6);
    const hits = num(f?.hits, 1, 1e4);
    return pid && typeof f?.check === "string" && CHECK_RE.test(f.check) && sev !== null &&
        score !== null && hits !== null
      ? [{ id: pid, check: f.check, sev, score, hits: Math.trunc(hits), ctx: cleanCtx(f.ctx) }]
      : [];
  });

  const kicks = arr(body.kicks, 100).flatMap((k: any) => {
    const pid = id(k?.id);
    const score = num(k?.score, 0, 1e6);
    return pid ? [{ id: pid, reason: str(k.reason, 200), score: score ?? 0, name: str(k.name, 32) }] : [];
  });

  const acks = arr(body.acks, 500).flatMap((a: any) => {
    const pid = id(a?.id);
    return pid && typeof a?.active === "boolean" ? [{ id: pid, active: a.active }] : [];
  });

  let since: string | null = null;
  if (typeof body.since === "string" && !Number.isNaN(Date.parse(body.since))) since = body.since;

  return { server: str(body.server, 64), players, flags, kicks, acks, since };
}

async function postKicks(kicks: { id: string; reason: string; score: number; name: string }[], server: string) {
  const { data: url } = await db.rpc("game_secret", { p_name: "discord_webhook" });
  if (typeof url !== "string" || !url) return;
  const embeds = kicks.slice(0, 10).map((k) => ({
    title: `Kicked ${k.name || k.id}`,
    url: `https://www.roblox.com/users/${k.id}/profile`,
    color: 0xef4444,
    fields: [
      { name: "UserId", value: k.id, inline: true },
      { name: "Score", value: String(Math.round(k.score)), inline: true },
      { name: "Top checks", value: k.reason || "n/a" },
    ],
    footer: { text: `server ${server.slice(0, 8)}` },
    timestamp: new Date().toISOString(),
  }));
  await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ username: "AntiCheat", embeds, allowed_mentions: { parse: [] } }),
  }).catch(() => {});
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method" });
  if (Number(req.headers.get("content-length") ?? 0) > MAX_BODY) return json(413, { error: "size" });

  const key = req.headers.get("x-game-key") ?? "";
  const expected = await expectedHash();
  if (!key || key.length > 200 || !expected || !sameString(await sha256(key), expected)) {
    return json(401, { error: "auth" });
  }

  const raw = await req.text();
  if (raw.length > MAX_BODY) return json(413, { error: "size" });

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw);
    if (!body || typeof body !== "object" || Array.isArray(body)) throw 0;
  } catch {
    return json(400, { error: "json" });
  }

  if (body.op === "join") {
    const pid = id(body.id);
    if (!pid) return json(400, { error: "id" });
    const { data, error } = await db.rpc("game_join", { p_user_id: pid });
    if (error) return json(500, { error: "db" });
    return json(200, data);
  }

  if (body.op === "sync") {
    const payload = parseSync(body);
    const { data, error } = await db.rpc("game_ingest", { p: payload });
    if (error) {
      console.error(error.message);
      return json(500, { error: "db" });
    }
    if (payload.kicks.length > 0) {
      // don't make the game server wait on discord
      EdgeRuntime.waitUntil(postKicks(payload.kicks, payload.server));
    }
    return json(200, data);
  }

  return json(400, { error: "op" });
});
