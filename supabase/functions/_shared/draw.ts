// draws PNGs for discord: a top-down map of a replay, and the daily report chart.
// svg -> png with resvg (wasm), no browser needed
import { initWasm, Resvg } from "npm:@resvg/resvg-wasm@2.6.2";
import type { ReplayEvent, Sample } from "./caseFile.ts";

let ready: Promise<void> | null = null;
let font: Uint8Array | null = null;

async function init() {
  if (!ready) {
    ready = (async () => {
      await initWasm(fetch("https://cdn.jsdelivr.net/npm/@resvg/resvg-wasm@2.6.2/index_bg.wasm"));
      // text is optional, if the font can't be fetched the images just go without labels
      try {
        const res = await fetch("https://raw.githubusercontent.com/google/fonts/main/ofl/roboto/Roboto%5Bwdth,wght%5D.ttf");
        if (res.ok) font = new Uint8Array(await res.arrayBuffer());
      } catch { /* ignore */ }
    })();
  }
  await ready;
}

async function toPng(svg: string, width: number) {
  await init();
  const resvg = new Resvg(svg, {
    fitTo: { mode: "width", value: width },
    font: font ? { fontBuffers: [font], defaultFontFamily: "Roboto", loadSystemFonts: false } : { loadSystemFonts: false },
  });
  // copy into a plain ArrayBuffer so Response/Blob accept it
  return new Uint8Array(resvg.render().asPng());
}

const BG = "#07090d";
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

function shade(color: number, amount: number) {
  const r = (color >> 16) & 255, g = (color >> 8) & 255, b = color & 255;
  const mix = (c: number, bg: number) => Math.round(c * amount + bg * (1 - amount));
  return `rgb(${mix(r, 7)},${mix(g, 9)},${mix(b, 13)})`;
}

// parts: [x, y, z, sx, sy, sz, rx, ry, rz, color, shape]
export async function replayPng(samples: Sample[], events: ReplayEvent[], parts: number[][], title: string) {
  const W = 800, H = 500;
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const s of samples) {
    minX = Math.min(minX, s[1]); maxX = Math.max(maxX, s[1]);
    minY = Math.min(minY, s[2]); maxY = Math.max(maxY, s[2]);
    minZ = Math.min(minZ, s[3]); maxZ = Math.max(maxZ, s[3]);
  }
  const pad = 30;
  let spanX = Math.max(maxX - minX + pad * 2, 80);
  let spanZ = Math.max(maxZ - minZ + pad * 2, 50);
  // keep the aspect ratio of the image
  if (spanX / spanZ > W / H) spanZ = spanX * H / W; else spanX = spanZ * W / H;
  const cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
  const scale = W / spanX;
  const sx = (x: number) => (x - cx) * scale + W / 2;
  const sy = (z: number) => (z - cz) * scale + H / 2;

  const out: string[] = [];
  out.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">`);
  out.push(`<rect width="${W}" height="${H}" fill="${BG}"/>`);

  // map, lower parts first so roofs and platforms sit on top
  const visible = parts
    .filter((p) => {
      const r = Math.max(p[3], p[5]) / 2;
      return p[0] + r > cx - spanX / 2 && p[0] - r < cx + spanX / 2 && p[2] + r > cz - spanZ / 2 && p[2] - r < cz + spanZ / 2
        && p[1] - p[4] / 2 < maxY + 25;
    })
    .sort((a, b) => a[1] + a[4] / 2 - (b[1] + b[4] / 2))
    .slice(-2500);
  for (const p of visible) {
    const w = p[3] * scale, h = p[5] * scale;
    const deg = (-p[7] * 180) / Math.PI;
    const fill = shade(p[9], 0.45);
    if (p[10] === 1) {
      out.push(`<circle cx="${sx(p[0]).toFixed(1)}" cy="${sy(p[2]).toFixed(1)}" r="${(w / 2).toFixed(1)}" fill="${fill}"/>`);
    } else {
      out.push(`<rect x="${(-w / 2).toFixed(1)}" y="${(-h / 2).toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" fill="${fill}" stroke="#1d2531" stroke-width="0.6" transform="translate(${sx(p[0]).toFixed(1)} ${sy(p[2]).toFixed(1)}) rotate(${deg.toFixed(1)})"/>`);
    }
  }

  // path: cyan normally, red around the moments something fired
  const hot = events.map((e) => e[0]);
  const isHot = (t: number) => hot.some((h) => Math.abs(h - t) < 0.35);
  for (let i = 1; i < samples.length; i++) {
    const a = samples[i - 1], b = samples[i];
    if (b[5] === 1) {
      // our own snapback, dashed
      out.push(`<line x1="${sx(a[1]).toFixed(1)}" y1="${sy(a[3]).toFixed(1)}" x2="${sx(b[1]).toFixed(1)}" y2="${sy(b[3]).toFixed(1)}" stroke="#fbbf24" stroke-width="1.5" stroke-dasharray="4 3" opacity="0.8"/>`);
      out.push(`<circle cx="${sx(b[1]).toFixed(1)}" cy="${sy(b[3]).toFixed(1)}" r="4" fill="none" stroke="#fbbf24" stroke-width="1.5"/>`);
      continue;
    }
    const color = isHot(b[0]) ? "#f43f5e" : "#22d3ee";
    out.push(`<line x1="${sx(a[1]).toFixed(1)}" y1="${sy(a[3]).toFixed(1)}" x2="${sx(b[1]).toFixed(1)}" y2="${sy(b[3]).toFixed(1)}" stroke="${color}" stroke-width="3" stroke-linecap="round"/>`);
  }
  const first = samples[0], last = samples[samples.length - 1];
  if (first) out.push(`<circle cx="${sx(first[1]).toFixed(1)}" cy="${sy(first[3]).toFixed(1)}" r="6" fill="#34d399"/>`);
  if (last) {
    const x = sx(last[1]), y = sy(last[3]);
    out.push(`<path d="M${x - 7} ${y - 7}L${x + 7} ${y + 7}M${x + 7} ${y - 7}L${x - 7} ${y + 7}" stroke="#f43f5e" stroke-width="3.5" stroke-linecap="round"/>`);
  }

  out.push(`<rect x="0" y="${H - 34}" width="${W}" height="34" fill="${BG}" opacity="0.85"/>`);
  out.push(`<text x="14" y="${H - 12}" font-size="15" font-family="Roboto" font-weight="600" fill="#e6ebf2">${esc(title)}</text>`);
  out.push(`<text x="${W - 14}" y="${H - 12}" font-size="13" font-family="Roboto" fill="#7d8898" text-anchor="end">● start   ✕ kicked   ○ pulled back   red = flagged</text>`);
  out.push(`</svg>`);
  return toPng(out.join(""), W);
}

export async function barsPng(rows: { label: string; value: number; color: string }[], title: string) {
  const W = 800, rowH = 34, top = 56;
  const H = top + Math.max(rows.length, 1) * rowH + 24;
  const max = Math.max(1, ...rows.map((r) => r.value));
  const out: string[] = [];
  out.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">`);
  out.push(`<rect width="${W}" height="${H}" fill="${BG}"/>`);
  out.push(`<text x="24" y="36" font-size="20" font-family="Roboto" font-weight="600" fill="#e6ebf2">${esc(title)}</text>`);
  rows.forEach((r, i) => {
    const y = top + i * rowH;
    const w = Math.max(4, (r.value / max) * (W - 260));
    out.push(`<text x="24" y="${y + 21}" font-size="15" font-family="Roboto" fill="#7d8898">${esc(r.label)}</text>`);
    out.push(`<rect x="150" y="${y + 6}" width="${w.toFixed(1)}" height="20" rx="4" fill="${r.color}"/>`);
    out.push(`<text x="${(158 + w).toFixed(1)}" y="${y + 21}" font-size="15" font-family="Roboto" font-weight="600" fill="#e6ebf2">${r.value}</text>`);
  });
  if (rows.length === 0) {
    out.push(`<text x="24" y="${top + 20}" font-size="15" font-family="Roboto" fill="#7d8898">quiet day, nothing flagged</text>`);
  }
  out.push(`</svg>`);
  return toPng(out.join(""), W);
}
