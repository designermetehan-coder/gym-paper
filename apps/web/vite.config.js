import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { VitePWA } from 'vite-plugin-pwa'
import { viteSingleFile } from 'vite-plugin-singlefile'
import path from 'node:path'

export default defineConfig(({ mode }) => ({
  define: { __APP_BUILD__: JSON.stringify(new Date().toISOString()) },
  resolve: { alias: { '@': path.resolve(import.meta.dirname, 'src'), ...(mode === 'single' ? { 'virtual:pwa-register': path.resolve(import.meta.dirname, 'src/lib/pwa-stub.js') } : {}) } },
  plugins: [
    react(),
    tailwindcss(),
    mode === 'single'
      ? viteSingleFile()
      : VitePWA({
          registerType: 'prompt',
          injectRegister: false,
          includeAssets: ['apple-touch-icon.png', 'favicon.png'],
          manifest: {
            id: '/',
            name: 'Ballı',
            short_name: 'Ballı',
            description: 'Kendi antrenman ve beslenme programın',
            lang: 'tr',
            display: 'standalone',
            orientation: 'portrait',
            start_url: '/',
            background_color: '#0a0a0a',
            theme_color: '#0a0a0a',
            icons: [
              { src: 'icon-192.png', sizes: '192x192', type: 'image/png' },
              { src: 'icon-512.png', sizes: '512x512', type: 'image/png' },
              { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
            ],
          },
          workbox: {
            globPatterns: ['**/*.{js,css,html,png,svg,woff2}'],
            maximumFileSizeToCacheInBytes: 3000000,
            cleanupOutdatedCaches: true,
            // hareket görselleri ilk açılışta değil, kullanıldıkça önbelleğe alınır
            runtimeCaching: [{ urlPattern: ({ url }) => url.pathname.startsWith('/assets/') && url.pathname.endsWith('.jpg'), handler: 'CacheFirst', options: { cacheName: 'ex-img', expiration: { maxEntries: 400, maxAgeSeconds: 31536000 } } }],
          },
        }),
  ],
  build: { outDir: mode === 'single' ? 'dist-single' : 'dist' },
}))
