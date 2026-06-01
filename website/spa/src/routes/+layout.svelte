<script lang="ts">
	import './layout.css';
	import favicon from '$lib/assets/favicon.svg';

	let { children } = $props();
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
	<title>FastTrack — Social</title>
	<meta name="description" content="Discover public leaderboards and driver profiles on FastTrack." />
</svelte:head>

<nav>
	<a class="nav-brand" href="/">
		<img src="/static/img/app-icon.png" alt="" width="24" height="24" />
		FastTrack
	</a>
	<div class="nav-links">
		<a href="/leaderboard">Leaderboard</a>
		<a href="/find">Find People</a>
	</div>
</nav>

{@render children()}

<footer class="container" style="margin-top: 80px; border-top: 1px solid var(--border); padding-top: 24px; color: var(--muted); font-size: 0.85rem;">
	<span>&copy; FastTrack</span>
	<span>
		<a href="https://fast.toper.dev">App</a> · 
		<a href="mailto:testflight@fasttrack.app?subject=TestFlight%20Access%20Request">Request TestFlight</a>
	</span>
</footer>
