<script lang="ts">
	import { onMount } from 'svelte';

	interface LbEntry {
		rank: number;
		username: string;
		value: number;
		car_make: string;
		car_model: string;
		avatar_url?: string;
	}

	const API = '/api/v1';

	let topSpeed = $state<{ value: string; driver: string } | null>(null);
	let best060 = $state<{ value: string; driver: string } | null>(null);
	let topDistance = $state<{ value: string; driver: string } | null>(null);
	let statsLoading = $state(true);

	onMount(() => {
		fetchStat('top_speed', (v) => `${(v * 2.23694).toFixed(1)}<span class="su"> mph</span>`, (e) => setTopSpeed(e));
		fetchStat('best_060', (v) => `${v.toFixed(1)}<span class="su">s</span>`, (e) => setBest060(e));
		fetchStat('total_distance', (v) => `${(v / 1609.34).toFixed(1)}<span class="su"> mi</span>`, (e) => setTopDistance(e));
	});

	function setTopSpeed(e: LbEntry) { topSpeed = { value: fmtSpeed(e.value), driver: driverLabel(e) }; }
	function setBest060(e: LbEntry) { best060 = { value: fmt060(e.value), driver: driverLabel(e) }; }
	function setTopDistance(e: LbEntry) { topDistance = { value: `${(e.value / 1609.34).toFixed(1)}<span class="su"> mi</span>`, driver: driverLabel(e) }; }

	function fmtSpeed(ms: number) { return `${(ms * 2.23694).toFixed(1)}<span class="su"> mph</span>`; }
	function fmt060(s: number) { return `${s.toFixed(1)}<span class="su">s</span>`; }
	function driverLabel(e: LbEntry) {
		return e.car_make ? `${e.username} · ${e.car_make}${e.car_model ? ' ' + e.car_model : ''}` : e.username;
	}

	async function fetchStat(cat: string, fmt: (v: number) => string, set: (e: LbEntry) => void) {
		try {
			const res = await fetch(`${API}/leaderboard?category=${cat}&scope=global&period=all_time`);
			const entries: LbEntry[] = res.ok ? await res.json() : [];
			if (entries.length) set(entries[0]);
		} catch { /* keep null */ }
		statsLoading = false;
	}
</script>

<!-- Hero -->
<section class="hero">
	<div class="hero-badge">Private Beta — Join the TestFlight</div>
	<h1>Track real-world <span>performance</span> drives with your iPhone.</h1>
	<p>FastTrack combines GPS, motion sensors, and live maps to record 0-60 times, quarter mile runs, G-force, and more — then syncs everything to the cloud.</p>
	<div class="hero-cta">
		<a href="/leaderboard" class="btn btn-primary">View Leaderboard</a>
		<a href="mailto:testflight@fasttrack.app?subject=TestFlight%20Access%20Request" class="btn btn-amber">Request TestFlight Access</a>
	</div>
</section>

<!-- Stats strip -->
<div class="strip">
	<div class="strip-grid">
		<div class="strip-card">
			{#if statsLoading}
				<div class="strip-skel"></div>
			{:else if topSpeed}
				<div class="strip-value amber">{@html topSpeed.value}</div>
				<div class="strip-divider"></div>
				<div class="strip-label">Top Speed</div>
				<div class="strip-driver">{topSpeed.driver}</div>
			{:else}
				<div class="strip-value amber">—</div>
				<div class="strip-divider"></div>
				<div class="strip-label">Top Speed</div>
				<div class="strip-driver">Be the first</div>
			{/if}
		</div>
		<div class="strip-card">
			{#if statsLoading}
				<div class="strip-skel"></div>
			{:else if best060}
				<div class="strip-value green">{@html best060.value}</div>
				<div class="strip-divider"></div>
				<div class="strip-label">Best 0-60</div>
				<div class="strip-driver">{best060.driver}</div>
			{:else}
				<div class="strip-value green">—</div>
				<div class="strip-divider"></div>
				<div class="strip-label">Best 0-60</div>
				<div class="strip-driver">Be the first</div>
			{/if}
		</div>
		<div class="strip-card">
			{#if statsLoading}
				<div class="strip-skel"></div>
			{:else if topDistance}
				<div class="strip-value blue">{@html topDistance.value}</div>
				<div class="strip-divider"></div>
				<div class="strip-label">Total Distance</div>
				<div class="strip-driver">{topDistance.driver}</div>
			{:else}
				<div class="strip-value blue">—</div>
				<div class="strip-divider"></div>
				<div class="strip-label">Total Distance</div>
				<div class="strip-driver">Be the first</div>
			{/if}
		</div>
	</div>
</div>

<!-- Features -->
<section class="features">
	<h2>Built for drivers</h2>
	<p class="features-subtitle">Everything you need to measure and improve your performance.</p>
	<div class="features-grid">
		<div class="feature-card">
			<span class="feature-icon">⚡</span>
			<h3>0-60 Timing</h3>
			<p>Precision acceleration measurement from a standstill. Get your real-world 0-60 mph time on any road.</p>
		</div>
		<div class="feature-card">
			<span class="feature-icon">🏁</span>
			<h3>Quarter Mile</h3>
			<p>Track your quarter mile elapsed time and trap speed. Compare runs and measure improvements over time.</p>
		</div>
		<div class="feature-card">
			<span class="feature-icon">🌀</span>
			<h3>G-Force Monitor</h3>
			<p>Real-time cornering, braking, and acceleration forces. See how your car performs through every turn.</p>
		</div>
		<div class="feature-card">
			<span class="feature-icon">🗺️</span>
			<h3>Drive Replay</h3>
			<p>Review your route with speed-colored overlays and event markers for every turn, brake, and lane change.</p>
		</div>
		<div class="feature-card">
			<span class="feature-icon">🏆</span>
			<h3>Leaderboards</h3>
			<p>Compare your times with drivers worldwide. Filter by car make, model, time period, and more.</p>
		</div>
		<div class="feature-card">
			<span class="feature-icon">🔧</span>
			<h3>Garage &amp; Stats</h3>
			<p>Keep multiple cars with per-vehicle performance stats. Switch between them and track each one separately.</p>
		</div>
	</div>
</section>

<!-- Early Access -->
<section class="early-access">
	<h2>Get Early Access</h2>
	<p>FastTrack is currently in private beta. Join the TestFlight to be the first to track your drives.</p>
	<a href="mailto:testflight@fasttrack.app?subject=TestFlight%20Access%20Request" class="btn btn-primary">Request Invite</a>
	<p class="ea-note">Limited spots available. No spam, ever.</p>
</section>

<style>
	.hero {
		text-align: center;
		padding: 100px 24px 60px;
		max-width: 720px;
		margin: 0 auto;
	}

	.hero-badge {
		display: inline-block;
		background: var(--blue-dim);
		color: var(--blue);
		border: 1px solid rgba(10,132,255,0.3);
		border-radius: 20px;
		padding: 5px 14px;
		font-size: .8rem;
		font-weight: 600;
		letter-spacing: .05em;
		margin-bottom: 20px;
	}

	.hero h1 {
		font-size: clamp(2.4rem, 6vw, 4rem);
		font-weight: 800;
		letter-spacing: -.03em;
		line-height: 1.1;
		margin-bottom: 20px;
	}

	.hero h1 span {
		background: linear-gradient(135deg, var(--blue), var(--amber));
		-webkit-background-clip: text;
		-webkit-text-fill-color: transparent;
		background-clip: text;
	}

	.hero p {
		font-size: 1.15rem;
		color: var(--muted);
		max-width: 520px;
		margin: 0 auto 32px;
	}

	.hero-cta {
		display: flex;
		gap: 12px;
		justify-content: center;
		flex-wrap: wrap;
	}

	/* Stats strip */
	.strip {
		max-width: 800px;
		margin: 0 auto 20px;
		padding: 0 24px;
	}

	.strip-grid {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 12px;
	}

	.strip-card {
		background: linear-gradient(135deg, var(--surface) 0%, var(--surface-alt) 100%);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 28px 24px;
		text-align: center;
		position: relative;
	}

	.strip-value {
		font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, Consolas, monospace;
		font-size: 2.2rem;
		font-weight: 700;
		line-height: 1.2;
		letter-spacing: -.02em;
	}

	.strip-value :global(.su) {
		font-weight: 400;
		font-size: .75rem;
		color: var(--muted);
		margin-left: 2px;
	}

	.strip-value.amber { color: var(--amber); }
	.strip-value.green  { color: var(--green); }
	.strip-value.blue   { color: var(--blue); }

	.strip-divider {
		width: 40px;
		height: 3px;
		background: linear-gradient(90deg, var(--blue), var(--amber));
		border-radius: 2px;
		margin: 12px auto;
	}

	.strip-label {
		font-size: .7rem;
		text-transform: uppercase;
		letter-spacing: .1em;
		color: var(--muted);
		margin-top: 6px;
		font-weight: 600;
	}

	.strip-driver {
		font-size: .7rem;
		color: var(--muted);
		margin-top: 4px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.strip-skel {
		height: 68px;
		border-radius: 6px;
		background: linear-gradient(90deg, var(--surface-alt) 0%, var(--border) 50%, var(--surface-alt) 100%);
		background-size: 200% 100%;
		animation: shimmer 1.4s ease-in-out infinite;
	}

	@keyframes shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}

	/* Features */
	.features {
		max-width: 960px;
		margin: 0 auto;
		padding: 60px 24px 40px;
	}

	.features h2 {
		text-align: center;
		font-size: 1.8rem;
		font-weight: 700;
		margin-bottom: 8px;
	}

	.features-subtitle {
		text-align: center;
		color: var(--muted);
		margin-bottom: 40px;
		font-size: 1rem;
	}

	.features-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
		gap: 12px;
	}

	.feature-card {
		background: var(--card);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 24px;
		transition: border-color .15s, transform .15s;
	}

	.feature-card:hover {
		border-color: rgba(10,132,255,0.3);
		transform: translateY(-4px);
	}

	.feature-icon {
		font-size: 1.8rem;
		margin-bottom: 12px;
		display: block;
	}

	.feature-card h3 {
		font-size: 1rem;
		font-weight: 700;
		margin-bottom: 6px;
	}

	.feature-card p {
		font-size: .85rem;
		color: var(--muted);
		line-height: 1.5;
	}

	/* Early Access */
	.early-access {
		text-align: center;
		padding: 80px 24px;
		max-width: 560px;
		margin: 0 auto;
	}

	.early-access h2 {
		font-size: 1.5rem;
		font-weight: 700;
		margin-bottom: 8px;
	}

	.early-access p {
		color: var(--muted);
		margin-bottom: 28px;
		font-size: .95rem;
	}

	.ea-note {
		font-size: .82rem;
		margin-top: 16px;
		opacity: .7;
	}

	@media (max-width: 640px) {
		.hero { padding: 60px 16px 40px; }
		.strip-grid { grid-template-columns: 1fr; gap: 8px; }
		.strip-value { font-size: 1.8rem; }
		.features { padding: 40px 16px 40px; }
		.features-grid { grid-template-columns: 1fr; }
	}
</style>