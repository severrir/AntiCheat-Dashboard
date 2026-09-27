import { createClient } from "npm:@supabase/supabase-js@2";

export const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
export const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
export const DASHBOARD = "https://severrir.github.io/AntiCheat-Dashboard/";

export const db = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const cache = new Map<string, { value: string | null; at: number }>();

export async function secret(name: string): Promise<string | null> {
  const hit = cache.get(name);
  if (hit && Date.now() - hit.at < 60_000) return hit.value;
  const { data } = await db.rpc("game_secret", { p_name: name });
  const value = typeof data === "string" && data ? data : null;
  cache.set(name, { value, at: Date.now() });
  return value;
}

export async function gameSecret(game: number, name: "discord_webhook" | "open_cloud_key"): Promise<string | null> {
  const key = `${game}:${name}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < 60_000) return hit.value;
  const { data } = await db.rpc("game_secret_for", { p_game: game, p_name: name });
  const value = typeof data === "string" && data ? data : null;
  cache.set(key, { value, at: Date.now() });
  return value;
}

const games = new Map<string, { id: number | null; at: number }>();

export async function gameForKey(key: string): Promise<number | null> {
  if (!key || key.length > 200) return null;
  const hash = await sha256(key);
  const hit = games.get(hash);
  if (hit && Date.now() - hit.at < 60_000) return hit.id;
  const { data, error } = await db.rpc("game_auth", { p_hash: hash });
  if (error) return null;
  const id = typeof data === "number" ? data : null;
  if (id !== null) {
    if (games.size > 500) games.clear();
    games.set(hash, { id, at: Date.now() });
  }
  return id;
}

export const json = (status: number, body: unknown, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...headers },
  });

export async function sha256(text: string) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function sameString(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function fromDatabase(req: Request) {
  const key = req.headers.get("x-cron-key") ?? "";
  const expected = await secret("cron_key");
  return !!expected && key.length === expected.length && sameString(key, expected);
}

export const replayLink = (id: number) => `${DASHBOARD}#/replay/${id}`;
export const playerLink = (id: string | number, game?: number) =>
  `${DASHBOARD}#/player/${id}${game ? `/${game}` : ""}`;
export const renderLink = (id: number, token: string) =>
  `${SUPABASE_URL}/functions/v1/render?id=${id}&t=${token}`;
