# FastTrack Public Social SPA

This is the thin, public-only (no-auth) SvelteKit SPA for FastTrack social discovery.

It is built as a static site (using `@sveltejs/adapter-static` with `fallback: 'index.html'`) and is intended to be served by the backend alongside the existing public pages and API.

## Key pages
- `/` – Public landing with CTAs to the app
- `/leaderboard` – Public global leaderboard with filters
- `/find` – Search public users
- `/u/[username]` – Public profile with live follower/following lists

## Development
```bash
cd website/spa
npm run dev
```

## Production build
```bash
npm run build   # outputs to build/ (static files)
```

The built assets are meant to be served from the backend (e.g. mounted under social routes) so that API calls can be relative (`/api/v1`).

See the root `docs/plans/2026-05-31-public-social-mirror-thin-spa-and-high-value-features.md` for full context and roadmap.

**Note:** This SPA consumes only public API endpoints. Authenticated features live in the iOS app.

(Copilot review feedback addressed in this version)

## Developing

Once you've created a project and installed dependencies with `npm install` (or `pnpm install` or `yarn`), start a development server:

```sh
npm run dev

# or start the server and open the app in a new browser tab
npm run dev -- --open
```

## Building

To create a production version of your app:

```sh
npm run build
```

You can preview the production build with `npm run preview`.

> To deploy your app, you may need to install an [adapter](https://svelte.dev/docs/kit/adapters) for your target environment.
