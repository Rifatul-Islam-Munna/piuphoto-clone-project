import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import { componentTagger } from "lovable-tagger";

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  server: {
    host: "::",
    port: 8080,
    hmr: {
      overlay: false,
    },
    proxy: {
      "/api": {
        target: "http://localhost:4000",
        changeOrigin: true,
        secure: false,
      },
      "/user": {
        target: "http://localhost:4000",
        changeOrigin: true,
        secure: false,
      },
      "/subscription-plan": {
        target: "http://localhost:4000",
        changeOrigin: true,
        secure: false,
      },
      "/event": {
        target: "http://localhost:4000",
        changeOrigin: true,
        secure: false,
      },
      "/eventImage": {
        target: "http://localhost:4000",
        changeOrigin: true,
        secure: false,
      },
      "/auth": {
        target: "http://localhost:4000",
        changeOrigin: true,
        secure: false,
      },
      "/image": {
        target: "http://localhost:4000",
        changeOrigin: true,
        secure: false,
      },
    },
  },
  plugins: [react(), mode === "development" && componentTagger()].filter(Boolean),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
}));
