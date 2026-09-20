import vue from '@vitejs/plugin-vue'
import Icons from 'unplugin-icons/vite'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  plugins: [vue(), Icons({ compiler: 'vue3' })],
  test: {
    environment: 'jsdom',
    setupFiles: ['src/test/setup.ts'],
    // The palette library contains extensionless ESM imports; let Vite resolve them.
    server: { deps: { inline: ['@material/material-color-utilities'] } },
  },
})
