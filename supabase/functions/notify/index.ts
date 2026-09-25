import { fromDatabase, json, secret } from "../_shared/util.ts";

// the database pings this whenever a ban changes. it publishes straight into every live
// roblox server through open cloud messaging, so bans land in about a second

const ID_RE = /^[1-9][0-9]{0,18}$/;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method" });
  if (!(await fromDatabase(req))) return json(401, { error: "auth" });

  let body: { id?: unknown; active?: unknown; reason?: unknown };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "json" });
  }
  if (typeof body.id !== "string" || !ID_RE.test(body.id) || typeof body.active !== "boolean") {
    return json(400, { error: "payload" });
  }

  const [key, universe] = await Promise.all([secret("open_cloud_key"), secret("universe_id")]);
  // no key means relay-only mode, servers still pick bans up on their next sync
  if (!key || !universe) return json(200, { sent: false, reason: "no open cloud key" });

  const message = JSON.stringify({
    id: body.id,
    active: body.active,
    reason: typeof body.reason === "string" ? body.reason.slice(0, 200) : "",
  });

  const res = await fetch(`https://apis.roblox.com/cloud/v2/universes/${universe}:publishMessage`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": key },
    body: JSON.stringify({ topic: "AC_Ban", message }),
  });
  if (!res.ok) {
    console.error("open cloud", res.status, (await res.text()).slice(0, 300));
    return json(502, { sent: false, status: res.status });
  }
  return json(200, { sent: true });
});
