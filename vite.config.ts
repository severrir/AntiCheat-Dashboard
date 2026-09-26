import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig, type Plugin } from 'vite'

const SUPABASE = 'kapvjoemzsdqiealluzl.supabase.co'

const csp: Plugin = {
  name: 'csp',
  apply: 'build',
  transformIndexHtml(html) {
    const policy = [
      "default-src 'self'",
      "script-src 'self'",
      "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
      'font-src https://fonts.gstatic.com',
      "img-src 'self' data: https://cdn.discordapp.com",
      `connect-src 'self' https://${SUPABASE} wss://${SUPABASE}`,
      "base-uri 'self'",
      "form-action 'self'",
    ].join('; ')
    return html.replace(
      '<meta charset="UTF-8" />',
      `<meta charset="UTF-8" />\n    <meta http-equiv="Content-Security-Policy" content="${policy}" />`,
    )
  },
}

export default defineConfig({
  base: './',
  plugins: [react(), tailwindcss(), csp],
  build: { sourcemap: false },
})
