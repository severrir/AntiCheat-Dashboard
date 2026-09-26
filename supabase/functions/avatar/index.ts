// textures for the replay viewer's avatar: shirt and pants templates, the face/head texture and
// accessory textures, by roblox image asset id. roblox's own thumbnail service is public but doesn't
// let browsers read the pixels, so this passes the png through with CORS. it only talks to roblox
//
//   ?asset=123  -> that image as a 420x420 png

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
};
const ID_RE = /^[1-9][0-9]{0,18}$/;
const HEADERS = {
  accept: "application/json, image/png, */*",
  "user-agent": "Mozilla/5.0 (compatible; AntiCheatDashboard/1.0; +https://severrir.github.io/AntiCheat-Dashboard/)",
};

const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...CORS } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "GET") return reply(405, { error: "method" });
  const asset = new URL(req.url).searchParams.get("asset") ?? "";
  if (!ID_RE.test(asset)) return reply(400, { error: "ask for ?asset=<image id>" });

  const thumb = await fetch(
    `https://thumbnails.roblox.com/v1/assets?assetIds=${asset}&size=420x420&format=Png&isCircular=false`,
    { headers: HEADERS },
  ).catch(() => null);
  if (!thumb?.ok) return reply(502, { error: "thumbnails", status: thumb?.status });
  const entry = (await thumb.json())?.data?.[0];
  // rendered on demand, the viewer asks again in a moment
  if (!entry || entry.state !== "Completed" || typeof entry.imageUrl !== "string") {
    return reply(202, { pending: true, state: entry?.state ?? "missing" });
  }
  const url = new URL(entry.imageUrl);
  if (!/\.rbxcdn\.com$/.test(url.hostname)) return reply(502, { error: "host" });

  const img = await fetch(url, { headers: HEADERS }).catch(() => null);
  if (!img?.ok) return reply(502, { error: "cdn", status: img?.status });
  return new Response(img.body, {
    headers: {
      "content-type": img.headers.get("content-type") ?? "image/png",
      "cache-control": "public, max-age=86400",
      ...CORS,
    },
  });
});
