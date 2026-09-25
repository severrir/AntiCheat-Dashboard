// reads the test runner output on stdin, writes public/badge.json (shields endpoint) and public/badge.svg
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'

const out = readFileSync(0, 'utf8')
process.stdout.write(out)
const line = out.split('\n').find((l) => l.startsWith('BADGE:'))
if (!line) {
  console.error('no BADGE line in test output')
  process.exit(1)
}
const badge = JSON.parse(line.slice(6))
const colors = { brightgreen: '#4c1', yellow: '#dfb317', red: '#e05d44' }
const fill = colors[badge.color] ?? '#9f9f9f'
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;')
// rough width, verdana 11px averages ~6.5px per char
const w = (s) => Math.round(s.length * 6.5) + 12
const lw = w(badge.label)
const mw = w(badge.message)
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${lw + mw}" height="20" role="img" aria-label="${esc(badge.label)}: ${esc(badge.message)}">
<rect width="${lw}" height="20" fill="#555"/><rect x="${lw}" width="${mw}" height="20" fill="${fill}"/>
<g fill="#fff" font-family="Verdana,DejaVu Sans,sans-serif" font-size="11" text-anchor="middle">
<text x="${lw / 2}" y="14">${esc(badge.label)}</text><text x="${lw + mw / 2}" y="14">${esc(badge.message)}</text>
</g></svg>`
mkdirSync('public', { recursive: true })
writeFileSync('public/badge.json', JSON.stringify(badge))
writeFileSync('public/badge.svg', svg)
