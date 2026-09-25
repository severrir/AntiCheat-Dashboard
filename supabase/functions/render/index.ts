import { replayPng } from "../_shared/draw.ts";
import type { ReplayEvent, Sample } from "../_shared/caseFile.ts";
import { db, sameString } from "../_shared/util.ts";

// top-down picture of a replay for discord embeds. public url, but only with the replay's random token

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const id = Number(url.searchParams.get("id"));
  const token = url.searchParams.get("t") ?? "";
  if (!Number.isSafeInteger(id) || id <= 0 || !/^[0-9a-f]{36}$/.test(token)) {
    return new Response("not found", { status: 404 });
  }

  const { data: r } = await db
    .from("replays")
    .select("id, token, user_id, place_id, map_version, samples, events, meta")
    .eq("id", id)
    .maybeSingle();
  if (!r || !sameString(r.token, token)) return new Response("not found", { status: 404 });

  let parts: number[][] = [];
  if (r.place_id && r.map_version) {
    const { data: chunks } = await db
      .from("map_chunks")
      .select("parts")
      .eq("place_id", r.place_id)
      .eq("version", r.map_version)
      .order("idx")
      .limit(10);
    parts = (chunks ?? []).flatMap((c) => c.parts as number[][]);
  }

  const name = (r.meta as Record<string, unknown>)?.name ?? r.user_id;
  const png = await replayPng(r.samples as Sample[], r.events as ReplayEvent[], parts, `${name} · replay #${r.id}`);
  return new Response(png, {
    headers: { "content-type": "image/png", "cache-control": "public, max-age=86400, immutable" },
  });
});
