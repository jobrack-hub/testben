import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [sveltekit()],
	server: {
		host: true,
		allowedHosts: 'all',
		proxy: {
			'/api': {
				target: 'https://bold-bush-3730.fly.dev',
				changeOrigin: true,
			}
		}
	}
});
