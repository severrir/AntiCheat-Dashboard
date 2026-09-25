import { caseFile, type ReplayEvent, type Sample } from "../_shared/caseFile.ts";
import { db, json, replayLink, renderLink, secret, sameString, sha256, SERVICE_KEY, SUPABASE_URL } from "../_shared/util.ts";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

// game servers talk to this. no jwt, auth is the x-game-key header (we only store its sha256)

const MAX_BODY = 600_000;
const ID_RE = /^[1-9][0-9]{0,18}$/;
const CHECK_RE = /^[A-Za-z]{1,24}$/;

const num = (v: unknown, lo: number, hi: number) =>
  typeof v === "number" && Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : null;
const id = (v: unknown) => {
  const s = typeof v === "number" ? String(Math.trunc(v)) : typeof v === "string" ? v : "";
  return ID_RE.test(s) ? s : null;
};
const str = (v: unknown, max: number) => (typeof v === "string" ? v.slice(0, max) : "");
const arr = (v: unknown, max: number): unknown[] => (Array.isArray(v) ? v.slice(0, max) : []);
const bool = (v: unknown) => v === true;

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

function vec(v: unknown, len: number, lo = -1e6, hi = 1e6): number[] | null {
  if (!Array.isArray(v) || v.length !== len) return null;
  const out: number[] = [];
  for (const x of v) {
    const n = num(x, lo, hi);
    if (n === null) return null;
    out.push(n);
  }
  return out;
}

function cmdAcks(v: unknown) {
  return arr(v, 50).flatMap((a: any) =>
    typeof a?.id === "number" && Number.isInteger(a.id) && typeof a?.ok === "boolean"
      ? [{ id: a.id, ok: a.ok, result: str(a.result, 200) }]
      : []
  );
}

function parseSync(body: Record<string, unknown>) {
  const players = arr(body.players, 200).flatMap((p: any) => {
    const pid = id(p?.id);
    const score = num(p?.score, 0, 1e6);
    const peak = num(p?.peak, 0, 1e6);
    if (!pid || score === null || peak === null) return [];
    const age = num(p?.age, 0, 1e6);
    return [{ id: pid, name: str(p.name, 32), score, peak, fp: vec(p.fp, 8, -1e4, 1e4), age: age === null ? null : Math.trunc(age) }];
  });

  const flags = arr(body.flags, 500).flatMap((f: any) => {
    const pid = id(f?.id);
    const sev = num(f?.sev, 0, 1e4);
    const raw = num(f?.raw, 0, 1e4);
    const score = num(f?.score, 0, 1e6);
    const hits = num(f?.hits, 1, 1e4);
    if (!pid || typeof f?.check !== "string" || !CHECK_RE.test(f.check) || sev === null || score === null || hits === null) {
      return [];
    }
    return [{
      id: pid, check: f.check, sev, raw, score, hits: Math.trunc(hits), ctx: cleanCtx(f.ctx), pos: vec(f.pos, 3),
    }];
  });

  const kicks = arr(body.kicks, 100).flatMap((k: any) => {
    const pid = id(k?.id);
    if (!pid) return [];
    const sig = arr(k.sig, 12).filter((s) => typeof s === "string").map((s) => (s as string).slice(0, 40));
    const replay = num(k.replay, 1, 9e15);
    return [{
      id: pid, name: str(k.name, 32), reason: str(k.reason, 200), score: num(k.score, 0, 1e6) ?? 0,
      replay: replay === null ? null : Math.trunc(replay), sig,
    }];
  });

  const acks = arr(body.acks, 500).flatMap((a: any) => {
    const pid = id(a?.id);
    return pid && typeof a?.active === "boolean" ? [{ id: pid, active: a.active }] : [];
  });

  let since: string | null = null;
  if (typeof body.since === "string" && !Number.isNaN(Date.parse(body.since))) since = body.since;

  return {
    server: str(body.server, 64),
    place: id(body.place),
    since,
    threat: Math.trunc(num(body.threat, 0, 3) ?? 0),
    island: bool(body.island),
    players, flags, kicks, acks,
    cmdAcks: cmdAcks(body.cmdAcks),
  };
}

type Kick = ReturnType<typeof parseSync>["kicks"][number];

async function postKicks(kicks: Kick[], server: string) {
  const url = await secret("discord_webhook");
  if (!url) return;

  for (const k of kicks.slice(0, 5)) {
    const embed: Record<string, unknown> = {
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
    };

    if (k.replay) {
      const { data: r } = await db.from("replays").select("id, token, samples, events, meta").eq("id", k.replay).maybeSingle();
      if (r) {
        const file = caseFile({
          name: k.name || k.id,
          events: r.events as ReplayEvent[],
          samples: r.samples as Sample[],
          score: k.score,
          kickScore: (r.meta as any)?.kickScore,
          walkSpeed: (r.meta as any)?.walkSpeed,
          kind: "kick",
        });
        embed.description = `${file.lines.slice(0, 4).join("\n")}\n\n**[▶ Watch the 3D replay](${replayLink(r.id)})**`;
        embed.image = { url: renderLink(r.id, r.token) };
      }
    }

    await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: "AntiCheat", embeds: [embed], allowed_mentions: { parse: [] } }),
    }).catch(() => {});
  }
}

// mission control goes over a private realtime channel, only approved admins can listen
async function broadcast(payload: unknown) {
  await fetch(`${SUPABASE_URL}/realtime/v1/api/broadcast`, {
    method: "POST",
    headers: { "content-type": "application/json", apikey: SERVICE_KEY, authorization: `Bearer ${SERVICE_KEY}` },
    body: JSON.stringify({ messages: [{ topic: "mission", event: "pulse", payload, private: true }] }),
  }).catch(() => {});
}

function parsePulse(body: Record<string, unknown>) {
  const players = arr(body.players, 200).flatMap((p: any) => {
    const pid = id(p?.id);
    if (!pid) return [];
    const x = num(p.x, -1e6, 1e6), y = num(p.y, -1e6, 1e6), z = num(p.z, -1e6, 1e6);
    return [{
      id: pid,
      name: str(p.name, 32),
      score: num(p.score, 0, 1e6) ?? 0,
      x, y, z,
      yaw: num(p.yaw, -10, 10) ?? 0,
      admin: bool(p.admin),
    }];
  });
  return {
    server: str(body.server, 64),
    place: id(body.place),
    threat: Math.trunc(num(body.threat, 0, 3) ?? 0),
    island: bool(body.island),
    live: bool(body.live),
    players,
    cmdAcks: cmdAcks(body.cmdAcks),
  };
}

function parseReplay(body: Record<string, unknown>) {
  const user = id(body.user);
  const kind = typeof body.kind === "string" && ["kick", "capture", "session"].includes(body.kind) ? body.kind : null;
  if (!user || !kind) return null;
  const samples = arr(body.samples, 400).flatMap((s) => {
    const v = vec(s, 7);
    return v ? [v.map((n, i) => (i === 0 || i === 4 ? Math.round(n * 100) / 100 : Math.round(n * 10) / 10))] : [];
  });
  if (samples.length < 2) return null;
  const events = arr(body.events, 200).flatMap((e: any) =>
    Array.isArray(e) && num(e[0], -1e4, 1e4) !== null && typeof e[1] === "string" && CHECK_RE.test(e[1])
      ? [[num(e[0], -1e4, 1e4), e[1], str(e[2], 60), str(e[3], 40)]]
      : []
  );
  const meta = cleanCtx(body.meta);
  return {
    user, kind, events, samples, meta,
    server: str(body.server, 64),
    place: id(body.place),
    mapVersion: str(body.mapVersion, 64),
    reason: str(body.reason, 200),
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method" });
  if (Number(req.headers.get("content-length") ?? 0) > MAX_BODY) return json(413, { error: "size" });

  const key = req.headers.get("x-game-key") ?? "";
  const expected = await secret("game_key_sha256");
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

  switch (body.op) {
    case "join": {
      const pid = id(body.id);
      if (!pid) return json(400, { error: "id" });
      const { data, error } = await db.rpc("game_join", { p_user_id: pid });
      return error ? json(500, { error: "db" }) : json(200, data);
    }

    case "sync": {
      const payload = parseSync(body);
      const { data, error } = await db.rpc("game_ingest", { p: payload });
      if (error) {
        console.error("ingest", error.message);
        return json(500, { error: "db" });
      }
      // don't make the game server wait on discord
      if (payload.kicks.length > 0) EdgeRuntime.waitUntil(postKicks(payload.kicks, payload.server));
      return json(200, data);
    }

    case "pulse": {
      const p = parsePulse(body);
      const { data, error } = await db.rpc("game_pulse", { p });
      if (error) return json(500, { error: "db" });
      if (p.live) {
        EdgeRuntime.waitUntil(broadcast({
          server: p.server, place: p.place, threat: p.threat, island: p.island, t: Date.now(),
          players: p.players.map(({ admin, ...rest }) => ({ ...rest, admin: admin || undefined })),
        }));
      }
      return json(200, data);
    }

    case "replay": {
      const r = parseReplay(body);
      if (!r) return json(400, { error: "replay" });
      const { data, error } = await db.rpc("game_replay", { p: r });
      return error ? json(500, { error: "db" }) : json(200, { id: (data as any).id });
    }

    case "map_check": {
      const place = id(body.place);
      const version = str(body.version, 64);
      const total = num(body.total, 1, 10);
      const bounds = vec(body.bounds, 6);
      if (!place || !version || total === null) return json(400, { error: "map" });
      const { data, error } = await db.rpc("game_map_check", {
        p_place: place, p_version: version, p_total: Math.trunc(total), p_bounds: bounds,
      });
      return error ? json(500, { error: "db" }) : json(200, { needed: data === true });
    }

    case "map_chunk": {
      const place = id(body.place);
      const version = str(body.version, 64);
      const idx = num(body.idx, 1, 10);
      if (!place || !version || idx === null) return json(400, { error: "map" });
      const parts = arr(body.parts, 1600).flatMap((p) => {
        const v = vec(p, 11, -1e7, 1e8);
        return v ? [v] : [];
      });
      const { error } = await db.rpc("game_map_chunk", {
        p_place: place, p_version: version, p_idx: Math.trunc(idx), p_parts: parts,
      });
      return error ? json(500, { error: "db" }) : json(200, { ok: true });
    }
  }

  return json(400, { error: "op" });
});
