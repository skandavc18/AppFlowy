import { defineConfig } from "vite";

// The bundle is served from an ephemeral loopback server with an
// unpredictable path, so every URL in it has to be relative.
export default defineConfig({
  base: "./",
  build: {
    outDir: "dist",
    emptyOutDir: true,
    target: "es2022",
    // One file each keeps the offline bundle small enough to ship as an asset
    // and removes any chance of a chunk being requested from a CDN.
    rollupOptions: {
      output: {
        entryFileNames: "excalidraw-host.js",
        chunkFileNames: "excalidraw-host-[name].js",
        assetFileNames: "excalidraw-host.[ext]",
      },
    },
  },
  optimizeDeps: {
    esbuildOptions: {
      target: "es2022",
      treeShaking: true,
    },
  },
});
