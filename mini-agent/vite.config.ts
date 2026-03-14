import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";

export default defineConfig({
	base: "/mini-agent/",
	plugins: [tailwindcss()],
	build: {
		outDir: "dist",
	},
});
