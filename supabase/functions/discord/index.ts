import { caseFile, type ReplayEvent, type Sample } from "../_shared/caseFile.ts";
import { db, fromDatabase, json, playerLink, renderLink, replayLink, secret } from "../_shared/util.ts";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

// discord slash commands: /check /ban /unban /replay. only approved dashboard staff can use them.
// discord signs every request, anything without a valid signature is dropped

const API = "https://discord.com/api/v10";
const EPHEMERAL = 64;

const COMMANDS = [
  {
    name: "check",
    description: "Show a player's anticheat record",
    options: [{ type: 3, name: "player", description: "Roblox username or user id", required: true }],
  },
  {
    name: "ban",
    description: "Ban a player from every server",
    options: [
      { type: 3, name: "player", description: "Roblox username or user id", required: true },
      { type: 3, name: "reason", description: "Shown to the player", required: true, max_length: 200 },
      { type: 4, name: "hours", description: "Leave empty for permanent", required: false, min_value: 1, max_value: 87600 },
    ],
  },
  {
    name: "unban",
    description: "Lift a ban",
    options: [{ type: 3, name: "player", description: "Roblox username or user id", required: true }],
  },
  {
    name: "replay",
    description: "Latest 3D replay of a player",
    options: [{ type: 3, name: "player", description: "Roblox username or user id", required: true }],
  },
];

function hex(s: string) {
  const out = new Uint8Array(s.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(s.slice(i * 2, i * 2 + 2), 16);
  return out;
}

async function verify(req: Request, body: string) {
  const sig = req.headers.get("x-signature-ed25519") ?? "";
  const ts = req.headers.get("x-signature-timestamp") ?? "";
  const pub = await secret("discord_public_key");
  if (!pub || !/^[0-9a-f]{128}$/.test(sig) || !/^\d{1,12}$/.test(ts)) return false;
  // old signed requests can't be replayed later
  if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) return false;
  try {
    const key = await crypto.subtle.importKey("raw", hex(pub), { name: "Ed25519" }, false, ["verify"]);
    return await crypto.subtle.verify("Ed25519", key, hex(sig), new TextEncoder().encode(ts + body));
  } catch {
    return false;
  }
}

async function registerCommands() {
  const [clientId, clientSecret] = await Promise.all([secret("discord_client_id"), secret("discord_client_secret")]);
  if (!clientId || !clientSecret) return { ok: false, error: "missing client credentials" };
  const tokenRes = await fetch(`${API}/oauth2/token`, {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded",
      authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
    },
    body: "grant_type=client_credentials&scope=applications.commands.update",
  });
  if (!tokenRes.ok) return { ok: false, error: `token ${tokenRes.status}` };
  const { access_token } = await tokenRes.json();
  const res = await fetch(`${API}/applications/${clientId}/commands`, {
    method: "PUT",
    headers: { "content-type": "application/json", authorization: `Bearer ${access_token}` },
    body: JSON.stringify(COMMANDS),
  });
  return { ok: res.ok, status: res.status, body: res.ok ? undefined : (await res.text()).slice(0, 300) };
}

type Staff = { name: string };

async function staff(discordId: string): Promise<Staff | null> {
  const { data } = await db
    .from("dashboard_users")
    .select("username, role")
    .eq("discord_id", discordId)
    .in("role", ["owner", "admin"])
    .maybeSingle();
  return data ? { name: data.username || "discord staff" } : null;
}

// username or id -> roblox user id + name
async function resolve(input: string): Promise<{ id: string; name: string } | null> {
  const q = input.trim();
  if (/^[1-9][0-9]{0,18}$/.test(q)) {
    const { data } = await db.from("players").select("username").eq("user_id", q).maybeSingle();
    return { id: q, name: data?.username || q };
  }
  if (!/^[A-Za-z0-9_]{3,20}$/.test(q)) return null;
  const { data } = await db.from("players").select("user_id, username").ilike("username", q).limit(1).maybeSingle();
  if (data) return { id: String(data.user_id), name: data.username };
  const res = await fetch("https://users.roblox.com/v1/usernames/users", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ usernames: [q], excludeBannedUsers: false }),
  }).catch(() => null);
  const found = res?.ok ? (await res.json()).data?.[0] : null;
  return found ? { id: String(found.id), name: found.name } : null;
}

async function latestReplay(userId: string) {
  const { data } = await db
    .from("replays")
    .select("id, token, kind, samples, events, meta, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return data;
}

async function checkEmbed(p: { id: string; name: string }) {
  const [{ data: pl }, { data: ban }, replay] = await Promise.all([
    db.from("players").select("*").eq("user_id", p.id).maybeSingle(),
    db.from("bans").select("*").eq("user_id", p.id).maybeSingle(),
    latestReplay(p.id),
  ]);
  const banned = ban?.active && (!ban.expires_at || new Date(ban.expires_at) > new Date());
  const fields = [
    { name: "Score", value: pl ? `${Math.round(pl.trust_score)} (peak ${Math.round(pl.peak_score)})` : "never seen", inline: true },
    { name: "Flags", value: String(pl?.total_flags ?? 0), inline: true },
    { name: "Kicks", value: String(pl?.kicks ?? 0), inline: true },
    { name: "Status", value: banned ? `**Banned**: ${ban!.reason || "no reason"}` : "Not banned", inline: false },
  ];
  if (pl?.alt_of) fields.push({ name: "Possible alt", value: `of ${pl.alt_of} (${Math.round((pl.alt_score ?? 0) * 100)}% match)`, inline: false });
  if (pl?.last_seen) fields.push({ name: "Last seen", value: `<t:${Math.floor(new Date(pl.last_seen).getTime() / 1000)}:R>`, inline: true });

  let description = `[Open in dashboard](${playerLink(p.id)}) · [Roblox profile](https://www.roblox.com/users/${p.id}/profile)`;
  if (replay) {
    const file = caseFile({
      name: p.name, events: replay.events as ReplayEvent[], samples: replay.samples as Sample[], kind: replay.kind,
      kickScore: (replay.meta as any)?.kickScore, walkSpeed: (replay.meta as any)?.walkSpeed, score: (replay.meta as any)?.score,
    });
    description += `\n\n**Latest recording:**\n${file.lines.slice(0, 3).join("\n")}\n[▶ Watch replay](${replayLink(replay.id)})`;
  }
  return { title: p.name, description, color: banned ? 0xf43f5e : 0x22d3ee, fields };
}

async function run(name: string, opts: Record<string, string | number>, who: Staff) {
  const target = await resolve(String(opts.player ?? ""));
  if (!target) return { content: "Couldn't find that player." };

  if (name === "check") return { embeds: [await checkEmbed(target)] };

  if (name === "ban") {
    const reason = String(opts.reason ?? "").slice(0, 200);
    const hours = typeof opts.hours === "number" ? Math.min(87600, Math.max(1, Math.trunc(opts.hours))) : null;
    const expires = hours ? new Date(Date.now() + hours * 3600_000).toISOString() : null;
    const { error } = await db.from("bans").upsert({
      user_id: target.id, reason, active: true, banned_by: `${who.name} (discord)`,
      expires_at: expires, updated_at: new Date().toISOString(), roblox_synced: false,
    });
    if (error) return { content: "Ban failed, try again." };
    await db.from("actions").insert({ user_id: target.id, action: "ban", reason, actor: `${who.name} (discord)` });
    return { content: `**${target.name}** banned ${hours ? `for ${hours}h` : "permanently"}. They're out of every server within a second or two.` };
  }

  if (name === "unban") {
    const { data } = await db
      .from("bans")
      .update({ active: false, updated_at: new Date().toISOString(), roblox_synced: false })
      .eq("user_id", target.id)
      .eq("active", true)
      .select("user_id");
    if (!data?.length) return { content: `${target.name} isn't banned.` };
    await db.from("actions").insert({ user_id: target.id, action: "unban", reason: "", actor: `${who.name} (discord)` });
    return { content: `**${target.name}** unbanned.` };
  }

  if (name === "replay") {
    const replay = await latestReplay(target.id);
    if (!replay) return { content: `No replays recorded for ${target.name} yet.` };
    const file = caseFile({
      name: target.name, events: replay.events as ReplayEvent[], samples: replay.samples as Sample[], kind: replay.kind,
      kickScore: (replay.meta as any)?.kickScore, walkSpeed: (replay.meta as any)?.walkSpeed, score: (replay.meta as any)?.score,
    });
    return {
      embeds: [{
        title: `${target.name}: replay #${replay.id}`,
        url: replayLink(replay.id),
        description: `${file.lines.join("\n")}\n\n*${file.verdict}*\n**[▶ Watch in 3D](${replayLink(replay.id)})**`,
        image: { url: renderLink(replay.id, replay.token) },
        color: 0xf43f5e,
        timestamp: replay.created_at,
      }],
    };
  }
  return { content: "Unknown command." };
}

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // one-time command registration, only our own database can trigger it
  if (req.method === "POST" && url.searchParams.get("setup") === "1") {
    if (!(await fromDatabase(req))) return json(401, { error: "auth" });
    return json(200, await registerCommands());
  }

  if (req.method !== "POST") return json(405, { error: "method" });
  const body = await req.text();
  if (body.length > 100_000 || !(await verify(req, body))) return new Response("bad signature", { status: 401 });

  const i = JSON.parse(body);
  if (i.type === 1) return json(200, { type: 1 });
  if (i.type !== 2) return json(400, { error: "type" });

  const discordId: string = i.member?.user?.id ?? i.user?.id ?? "";
  const who = /^\d{5,25}$/.test(discordId) ? await staff(discordId) : null;
  if (!who) {
    return json(200, { type: 4, data: { content: "You're not on the anticheat staff list.", flags: EPHEMERAL } });
  }

  const opts: Record<string, string | number> = {};
  for (const o of i.data?.options ?? []) opts[o.name] = o.value;

  // answer "thinking..." right away, then fill it in (discord only waits 3 seconds)
  EdgeRuntime.waitUntil((async () => {
    let result: Record<string, unknown>;
    try {
      result = await run(String(i.data?.name), opts, who);
    } catch (e) {
      console.error("discord command", e);
      result = { content: "Something went wrong." };
    }
    await fetch(`${API}/webhooks/${i.application_id}/${i.token}/messages/@original`, {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...result, allowed_mentions: { parse: [] } }),
    });
  })());
  return json(200, { type: 5, data: { flags: EPHEMERAL } });
});
