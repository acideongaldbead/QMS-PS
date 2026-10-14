import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    }
  },
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true
      }
    }
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    // The heavy editors are the reason this is raised: Mermaid's own diagram
    // chunks are individually small but numerous.
    chunkSizeWarningLimit: 1500
    /*
     * Deliberately NO manualChunks here.
     *
     * Mermaid registers every diagram type through its own dynamic imports, so
     * Rollup already emits each one as a separate lazy chunk and the browser
     * fetches only the ones a page actually renders. A manualChunks rule keyed on
     * 'node_modules/mermaid' overrides that: it merges all sixty chunks into one,
     * and importing any of it then downloads the lot -- 3.1 MB instead of the
     * ~0.7 MB the fishbone editor needs. Leaving the splitting to Rollup is the
     * correct configuration, and it is verified by e2e/lazy-load.mjs, which
     * records what the browser really requests when the D4 tab opens.
     */
  }
})
