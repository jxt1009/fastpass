import adapter from '@sveltejs/adapter-static';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	compilerOptions: {
		// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
		runes: ({ filename }) => (filename.split(/[/\\]/).includes('node_modules') ? undefined : true)
	},
	kit: {
		// Static adapter for pure static hosting of the public social SPA (no server needed).
		// fallback enables client-side routing for /leaderboard, /u/:username, search, etc.
		adapter: adapter({
			fallback: 'index.html'
		})
		// No broad prerender: dynamic routes like /u/[username] are handled client-side.
	}
};

export default config;
