import { barsPng } from "../_shared/draw.ts";
import { db, DASHBOARD, fromDatabase, json, secret } from "../_shared/util.ts";

// daily report to discord, fired by pg_cron at 10:00 tbilisi

const COLORS: Record<string, string> = {
  Movement: "#22d3ee", Character: "#a78bfa", Remote: "#fbbf24", Statistical: "#34d399",
  Timing: "#fb923c", Honeypot: "#f43f5e", Client: "#60a5fa", Combat: "#f472b6", Custom: "#94a3b8",
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method" });
  if (!(await fromDatabase(req))) return json(401, { error: "auth" });

  const webhook = await secret("discord_webhook");
  if (!webhook) return json(200, { sent: false, reason: "no webhook" });

  const since = new Date(Date.now() - 86_400_000).toISOString();
  const [flags, actions, appeals, players] = await Promise.all([
    db.from("flags").select("check_name, hits, created_at, user_id").gte("created_at", since).limit(20000),
    db.from("actions").select("action, created_at").gte("created_at", since).limit(5000),
    db.from("appeals").select("status").gte("decided_at", since).limit(1000),
    db.from("players").select("user_id", { count: "exact", head: true }).gte("last_seen", since),
  ]);

  const byCheck = new Map<string, number>();
  const byHour = new Array(24).fill(0);
  const flagged = new Set<number>();
  for (const f of flags.data ?? []) {
    byCheck.set(f.check_name, (byCheck.get(f.check_name) ?? 0) + f.hits);
    // tbilisi is utc+4
    byHour[(new Date(f.created_at).getUTCHours() + 4) % 24] += f.hits;
    flagged.add(f.user_id);
  }
  const count = (a: string) => (actions.data ?? []).filter((x) => x.action === a).length;
  const kicks = count("kick"), bans = count("ban"), unbans = count("unban");
  const approved = (appeals.data ?? []).filter((a) => a.status === "approved").length;
  const busiest = byHour.indexOf(Math.max(...byHour));
  const top = [...byCheck.entries()].sort((a, b) => b[1] - a[1]);

  const png = await barsPng(
    top.map(([label, value]) => ({ label, value, color: COLORS[label] ?? COLORS.Custom })),
    "Flags in the last 24 hours",
  );

  const lines = [
    `**${kicks}** kicked, **${bans}** banned, **${unbans}** unbanned`,
    `**${flagged.size}** of ${players.count ?? 0} players tripped at least one check`,
    top[0] ? `Most common: **${top[0][0]}** (${top[0][1]})` : "Nothing flagged at all",
    top[0] ? `Busiest hour: **${String(busiest).padStart(2, "0")}:00** Tbilisi time` : "",
    `Appeals approved (wrong bans): **${approved}**`,
  ].filter(Boolean);

  const form = new FormData();
  form.append("payload_json", JSON.stringify({
    username: "AntiCheat",
    allowed_mentions: { parse: [] },
    embeds: [{
      title: "Daily anticheat report",
      url: DASHBOARD,
      description: lines.join("\n"),
      color: 0x22d3ee,
      image: { url: "attachment://report.png" },
      timestamp: new Date().toISOString(),
    }],
  }));
  form.append("files[0]", new Blob([png], { type: "image/png" }), "report.png");

  const res = await fetch(webhook, { method: "POST", body: form });
  return json(200, { sent: res.ok });
});
