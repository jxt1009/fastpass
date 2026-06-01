<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { page } from '$app/stores';

	let driveId = $derived($page.params.id);

	interface PublicDrive {
		id: number;
		username: string;
		full_name: string;
		avatar_url: string;
		start_time: string;
		end_time: string;
		max_speed: number;
		avg_speed: number;
		distance: number;
		duration: number;
		best_060_time: number | null;
		car_make: string | null;
		car_model: string | null;
		car_year: number | null;
		car_trim: string | null;
		car_nickname: string | null;
		route_data: string | null;
		zero_to_sixty_attempts: ZeroToSixtyAttempt[] | null;
	}

	interface ZeroToSixtyAttempt {
		start_index: number;
		end_index: number;
		start_timestamp: number;
		end_timestamp: number;
		elapsed_seconds: number;
		start_latitude: number;
		start_longitude: number;
		end_latitude: number;
		end_longitude: number;
	}

	interface RoutePoint {
		lat: number;
		lng: number;
		speed: number;
		ts: number;
	}

	let drive = $state<PublicDrive | null>(null);
	let loading = $state(true);
	let error = $state('');
	let mapEl: HTMLDivElement | null = null;
	let map: any = null;
	let leaflet: any = null;
	let resizeObserver: ResizeObserver | null = null;

	const API = '/api/v1';

	async function loadDrive() {
		loading = true;
		error = '';
		try {
			const res = await fetch(`${API}/drives/${driveId}/public`);
			if (res.status === 404) {
				error = 'This drive is private or no longer available.';
				return;
			}
			if (!res.ok) {
				throw new Error(`HTTP ${res.status}`);
			}
			drive = await res.json();
		} catch (e) {
			error = 'Could not load this drive.';
		} finally {
			loading = false;
		}
	}

	function parseRoute(): { points: RoutePoint[]; attempts: ZeroToSixtyAttempt[] } {
		if (!drive) return { points: [], attempts: [] };
		let points: RoutePoint[] = [];
		if (drive.route_data) {
			try {
				const json = JSON.parse(drive.route_data);
				if (json && json.v === 2 && Array.isArray(json.points)) {
					points = json.points as RoutePoint[];
				} else if (Array.isArray(json)) {
					points = json as RoutePoint[];
				}
			} catch {
				// ignore malformed route
			}
		}
		const attempts = drive.zero_to_sixty_attempts ?? [];
		return { points, attempts };
	}

	function formatSpeed(ms: number) {
		return (ms * 2.23694).toFixed(1);
	}

	function formatDistance(m: number) {
		return (m / 1609.34).toFixed(1);
	}

	function formatDuration(seconds: number) {
		const h = Math.floor(seconds / 3600);
		const m = Math.floor((seconds % 3600) / 60);
		const s = Math.floor(seconds % 60);
		if (h > 0) return `${h}h ${m}m`;
		return `${m}m ${s}s`;
	}

	$effect(() => {
		if (driveId) loadDrive();
	});

	async function ensureLeaflet() {
		if (typeof window === 'undefined') return null;
		if (leaflet) return leaflet;
		// Inject Leaflet CSS once
		if (!document.querySelector('link[data-leaflet]')) {
			const link = document.createElement('link');
			link.rel = 'stylesheet';
			link.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
			link.crossOrigin = '';
			link.setAttribute('data-leaflet', '1');
			document.head.appendChild(link);
		}
		// Load Leaflet JS if not already on the page
		if (!(window as any).L) {
			await new Promise<void>((resolve, reject) => {
				const script = document.createElement('script');
				script.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
				script.crossOrigin = '';
				script.onload = () => resolve();
				script.onerror = () => reject(new Error('Failed to load Leaflet'));
				document.head.appendChild(script);
			});
		}
		leaflet = (window as any).L;
		return leaflet;
	}

	async function renderMap() {
		if (!mapEl || !drive) return;
		const { points, attempts } = parseRoute();
		if (points.length < 2) return;

		const L = await ensureLeaflet();
		if (!L) return;

		if (!map) {
			map = L.map(mapEl, { zoomControl: true, attributionControl: true });
		} else {
			map.eachLayer((layer: any) => {
				if (layer instanceof L.TileLayer || layer instanceof L.Polyline || layer instanceof L.Marker) {
					map.removeLayer(layer);
				}
			});
		}
		// Fix sizing if the container was hidden on first mount
		setTimeout(() => map && map.invalidateSize(), 0);

		L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
			attribution: '© OpenStreetMap',
			maxZoom: 19
		}).addTo(map);

		const latlngs: [number, number][] = points.map((p) => [p.lat, p.lng]);
		L.polyline(latlngs, { color: '#3b82f6', weight: 4, opacity: 0.8 }).addTo(map);

		// Start / end markers
		L.circleMarker(latlngs[0], { radius: 7, color: '#22c55e', fillOpacity: 1 })
			.bindTooltip('Start')
			.addTo(map);
		L.circleMarker(latlngs[latlngs.length - 1], { radius: 7, color: '#ef4444', fillOpacity: 1 })
			.bindTooltip('End')
			.addTo(map);

		// 0-60 attempt polylines + speech-bubble labels
		const fastest = attempts.length > 0 ? Math.min(...attempts.map((a) => a.elapsed_seconds)) : null;
		for (const attempt of attempts) {
			const startIdx = Math.max(0, Math.min(points.length - 1, attempt.start_index));
			const endIdx   = Math.max(startIdx, Math.min(points.length - 1, attempt.end_index));
			if (endIdx <= startIdx) continue;
			const segment = points.slice(startIdx, endIdx + 1).map((p) => [p.lat, p.lng]) as [number, number][];
			const isPB = attempt.elapsed_seconds === fastest;
			L.polyline(segment, {
				color: isPB ? '#facc15' : '#f97316',
				weight: 6,
				opacity: 1
			}).addTo(map);
			const mid = segment[Math.floor(segment.length / 2)];
			const icon = L.divIcon({
				className: 'zero-sixty-bubble',
				html: `<div class="bubble ${isPB ? 'pb' : ''}">${attempt.elapsed_seconds.toFixed(1)}s</div>`,
				iconSize: [60, 26],
				iconAnchor: [30, 26]
			});
			L.marker(mid, { icon, interactive: false }).addTo(map);
		}

		// Fit bounds
		const bounds = L.latLngBounds(latlngs);
		map.fitBounds(bounds, { padding: [30, 30] });

		// Resize observer for responsive layout
		if (!resizeObserver && mapEl) {
			resizeObserver = new ResizeObserver(() => {
				if (map) map.invalidateSize();
			});
			resizeObserver.observe(mapEl);
		}
	}

	$effect(() => {
		// Re-render the map whenever the drive data changes
		if (drive) renderMap();
	});

	onMount(() => {
		return () => {
			if (resizeObserver) resizeObserver.disconnect();
			resizeObserver = null;
			if (map) {
				map.remove();
				map = null;
			}
		};
	});
</script>

<div class="container" style="padding-top: 40px;">
	{#if loading}
		<div>Loading drive…</div>
	{:else if error || !drive}
		<div style="text-align:center; padding: 80px 0;">
			<h1 style="font-size: 2rem; margin-bottom: 8px;">Drive unavailable</h1>
			<p style="color: var(--muted);">{error || 'This drive is private or has been removed.'}</p>
			<a href="/leaderboard" style="display: inline-block; margin-top: 24px;">Back to Leaderboard</a>
		</div>
	{:else}
		<div class="drive-header">
			<a class="back" href={`/u/${encodeURIComponent(drive.username)}`}>← @{drive.username}</a>
			<h1>Drive on {new Date(drive.start_time).toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric', year: 'numeric' })}</h1>
			<div class="car-line">
				{#if drive.car_nickname || drive.car_make}
					{drive.car_year ?? ''} {drive.car_make ?? ''} {drive.car_model ?? ''} {drive.car_trim ?? ''} {drive.car_nickname ? `“${drive.car_nickname}”` : ''}
				{:else}
					Unknown car
				{/if}
			</div>
		</div>

		<div class="stats-row">
			<div class="stat-card">
				<div class="stat-value speed">{formatSpeed(drive.max_speed)}</div>
				<div class="stat-label">Top Speed (mph)</div>
			</div>
			<div class="stat-card">
				<div class="stat-value default">{formatDistance(drive.distance)}</div>
				<div class="stat-label">Distance (mi)</div>
			</div>
			<div class="stat-card">
				<div class="stat-value default">{formatDuration(drive.duration)}</div>
				<div class="stat-label">Duration</div>
			</div>
			<div class="stat-card">
				<div class="stat-value performance">{drive.best_060_time ? drive.best_060_time.toFixed(1) + 's' : '—'}</div>
				<div class="stat-label">Best 0-60</div>
			</div>
		</div>

		<div bind:this={mapEl} class="map"></div>

		{#if (drive.zero_to_sixty_attempts?.length ?? 0) > 0}
			{@const fastest = Math.min(...(drive.zero_to_sixty_attempts ?? []).map((a) => a.elapsed_seconds))}
			<div class="legend">
				<span class="legend-pill orange"></span>0-60 attempts
				<span class="legend-pill yellow"></span>personal best
				<span class="legend-count">{drive.zero_to_sixty_attempts!.length} capture{drive.zero_to_sixty_attempts!.length === 1 ? '' : 's'}</span>
				<span class="legend-fastest">fastest: {fastest.toFixed(2)}s</span>
			</div>
		{/if}
	{/if}
</div>

<style>
	.drive-header {
		margin-bottom: 20px;
	}
	.back {
		display: inline-block;
		color: var(--muted);
		text-decoration: none;
		font-size: 0.9rem;
		margin-bottom: 8px;
	}
	.back:hover {
		color: var(--text);
	}
	.drive-header h1 {
		font-size: 1.6rem;
		margin: 0 0 4px;
	}
	.car-line {
		color: var(--muted);
		font-size: 0.95rem;
	}
	.stats-row {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: 12px;
		margin-bottom: 20px;
	}
	@media (max-width: 640px) {
		.stats-row { grid-template-columns: repeat(2, 1fr); }
	}
	.stat-card {
		background: var(--card, #1a1a1a);
		border: 1px solid var(--border);
		border-radius: 8px;
		padding: 16px;
		text-align: center;
	}
	.stat-value {
		font-size: 1.6rem;
		font-weight: 700;
	}
	.stat-value.speed { color: var(--amber, #f59e0b); }
	.stat-value.performance { color: var(--green, #22c55e); }
	.stat-label {
		font-size: 0.8rem;
		color: var(--muted);
		margin-top: 4px;
	}
	.map {
		height: 460px;
		width: 100%;
		border-radius: 12px;
		border: 1px solid var(--border);
		overflow: hidden;
	}
	.legend {
		margin-top: 12px;
		display: flex;
		gap: 16px;
		align-items: center;
		color: var(--muted);
		font-size: 0.85rem;
	}
	.legend-pill {
		display: inline-block;
		width: 24px;
		height: 6px;
		border-radius: 3px;
		vertical-align: middle;
		margin-right: 6px;
	}
	.legend-pill.orange { background: #f97316; }
	.legend-pill.yellow { background: #facc15; }
	.legend-count {
		margin-left: auto;
	}
	.legend-fastest {
		font-weight: 600;
		color: var(--text);
	}

	/* Speech-bubble annotation styling for Leaflet divIcon */
	:global(.zero-sixty-bubble) { background: transparent; border: 0; }
	:global(.zero-sixty-bubble .bubble) {
		display: inline-block;
		background: #f97316;
		color: white;
		font-weight: 700;
		font-size: 12px;
		padding: 4px 8px;
		border-radius: 6px;
		border: 1.5px solid white;
		box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
		position: relative;
		text-align: center;
		min-width: 40px;
	}
	:global(.zero-sixty-bubble .bubble.pb) {
		background: #facc15;
		color: black;
	}
	:global(.zero-sixty-bubble .bubble::after) {
		content: '';
		position: absolute;
		left: 50%;
		bottom: -6px;
		transform: translateX(-50%);
		border-left: 5px solid transparent;
		border-right: 5px solid transparent;
		border-top: 6px solid #f97316;
	}
	:global(.zero-sixty-bubble .bubble.pb::after) {
		border-top-color: #facc15;
	}
</style>
