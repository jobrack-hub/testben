import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [sveltekit()],
	server: {
		host: true,
		allowedHosts: 'all',
		proxy: {
			'/api': 'http://localhost:8080'
		}
	}
});
