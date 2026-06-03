<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';

	interface LeaderboardEntry {
		rank: number;
		username: string;
		car_make: string;
		car_model: string;
		value: number;
		avatar_url?: string;
	}

	let category = $state<'top_speed' | 'best_060' | 'total_distance' | 'drive_count'>('top_speed');
	let period = $state<'all_time' | 'week'>('all_time');
	let carMake = $state('');
	let carModel = $state('');
	let entries = $state<LeaderboardEntry[]>([]);
	let loading = $state(true);
	let refreshing = $state(false);
	let error = $state('');

	const API = '/api/v1'; // relative for same-origin when served by backend (addressed Copilot)

	const categories = [
		{ value: 'top_speed', label: 'Top Speed', unit: 'mph' },
		{ value: 'best_060', label: '0-60', unit: 's' },
		{ value: 'total_distance', label: 'Distance', unit: 'mi' },
		{ value: 'drive_count', label: 'Drives', unit: '' }
	] as const;

	let initialLoadDone = $state(false);
	let requestId = 0;

	async function loadLeaderboard() {
		const id = ++requestId;
		if (!initialLoadDone) loading = true;
		else refreshing = true;
		error = '';

		const params = new URLSearchParams({
			category,
			scope: 'global',
			period
		});
		if (carMake) params.set('car_make', carMake);
		if (carModel) params.set('car_model', carModel);

		try {
			const res = await fetch(`${API}/leaderboard?${params}`);
			if (!res.ok) throw new Error('Failed to load');
			const data = await res.json();
			if (id !== requestId) return;
			entries = data;
		} catch (e) {
			if (id !== requestId) return;
			error = 'Could not load leaderboard. Try again later.';
			entries = [];
		} finally {
			if (id !== requestId) return;
			loading = false;
			refreshing = false;
			initialLoadDone = true;
		}
	}

	function formatValue(val: number, cat: string) {
		if (val == null || val === 0) return '—';
		if (cat === 'top_speed') return (val * 2.23694).toFixed(1);
		if (cat === 'best_060') return val.toFixed(1);
		if (cat === 'total_distance') return (val / 1609.34).toFixed(1);
		return Math.round(val).toLocaleString();
	}

	function getUnit(cat: string) {
		if (cat === 'top_speed') return 'mph';
		if (cat === 'best_060') return 's';
		if (cat === 'total_distance') return 'mi';
		return '';
	}

	// Simple car make list (same as old web)
	const makes = [
		'Audi', 'BMW', 'Chevrolet', 'Dodge', 'Ferrari', 'Ford', 'Honda', 'Hyundai',
		'Lamborghini', 'Mazda', 'McLaren', 'Mercedes-Benz', 'Nissan', 'Porsche',
		'Subaru', 'Tesla', 'Toyota', 'Volkswagen', 'Volvo'
	];

	onMount(() => {
		loadLeaderboard();
	});
</script>

<div class="container">
	<div class="leaderboard-header">
		<h1>Leaderboard</h1>
		<p>Top performers across all FastTrack drivers (public data)</p>
	</div>

	<div class="filter-bar">
		<!-- Category -->
		<div class="filter-pills">
			{#each categories as cat}
				<button
					class="filter-pill {category === cat.value ? 'active' : ''}"
					onclick={() => { if (category === cat.value) return; category = cat.value; loadLeaderboard(); }}
				>
					{cat.label}
				</button>
			{/each}
		</div>

		<!-- Period -->
		<div class="filter-pills">
			<button class="filter-pill {period === 'all_time' ? 'active' : ''}" onclick={() => { if (period === 'all_time') return; period = 'all_time'; loadLeaderboard(); }}>
				All Time
			</button>
			<button class="filter-pill {period === 'week' ? 'active' : ''}" onclick={() => { if (period === 'week') return; period = 'week'; loadLeaderboard(); }}>
				This Week
			</button>
		</div>

		<!-- Car filters -->
		<select class="filter-select" bind:value={carMake} onchange={() => { carModel = ''; loadLeaderboard(); }}>
			<option value="">All Makes</option>
			{#each makes as make}
				<option value={make}>{make}</option>
			{/each}
		</select>

		<select class="filter-select" bind:value={carModel} onchange={() => loadLeaderboard()} disabled={!carMake}>
			<option value="">All Models</option>
		</select>
	</div>

	{#if error}
		<div class="lb-error">{error}</div>
	{:else if entries.length === 0 && !loading}
		<div class="lb-empty">No results found.</div>
	{:else}
		<div class="lb-table-wrap" class:refreshing>
			{#if refreshing}
				<div class="lb-refreshing" role="status" aria-live="polite">Refreshing…</div>
			{/if}
			<table class="lb-table">
				<colgroup>
					<col style="width:70px">
					<col>
					<col>
					<col style="width:160px">
				</colgroup>
				<thead>
					<tr>
						<th>Rank</th>
						<th>Driver</th>
						<th>Car</th>
						<th style="text-align:right">{categories.find(c => c.value === category)?.label} ({getUnit(category)})</th>
					</tr>
				</thead>
				<tbody>
					{#if loading}
						{#each Array(8) as _, i}
							<tr class="lb-skeleton">
								<td><span class="lb-skel" style="width:28px"></span></td>
								<td>
									<span class="lb-skel lb-skel-avatar"></span>
									<span class="lb-skel" style="width:80px"></span>
								</td>
								<td><span class="lb-skel" style="width:120px"></span></td>
								<td class="lb-value"><span class="lb-skel" style="width:60px"></span></td>
							</tr>
						{/each}
					{:else}
						{#each entries as entry (entry.username)}
							<tr class="lb-row" onclick={() => goto(`/u/${encodeURIComponent(entry.username)}`)}>
								<td><span class="lb-rank {entry.rank === 1 ? 'gold' : entry.rank === 2 ? 'silver' : entry.rank === 3 ? 'bronze' : ''}">#{entry.rank}</span></td>
								<td>
									{#if entry.avatar_url}
										<img class="lb-avatar" src={entry.avatar_url} alt="" />
									{:else}
										<span class="lb-avatar-placeholder">{entry.username[0].toUpperCase()}</span>
									{/if}
									<span class="lb-user">{entry.username}</span>
								</td>
								<td class="lb-car">{entry.car_make} {entry.car_model}</td>
								<td class="lb-value">{formatValue(entry.value, category)} {getUnit(category)}</td>
							</tr>
						{/each}
					{/if}
				</tbody>
			</table>
		</div>
	{/if}

	<div style="margin-top: 32px; padding: 16px; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); font-size: 0.9rem; color: var(--muted);">
		<strong>Tip:</strong> Sign in with the FastTrack app to filter the leaderboard to only drivers you follow.
	</div>
</div>

<style>
	/* Minimal extra styles on top of the global theme */
	.filter-bar {
		display: flex;
		gap: 8px;
		flex-wrap: wrap;
		margin-bottom: 20px;
		align-items: center;
	}

	.filter-pills {
		display: flex;
		gap: 4px;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 4px;
	}

	.filter-pill {
		padding: 6px 14px;
		border-radius: var(--radius-sm);
		font-size: 0.8rem;
		font-weight: 600;
		cursor: pointer;
		border: none;
		background: transparent;
		color: var(--muted);
		transition: all 0.12s;
		white-space: nowrap;
	}

	.filter-pill.active {
		background: var(--blue);
		color: white;
	}

	.filter-select {
		background: var(--surface);
		color: var(--text);
		border: 1px solid var(--border);
		border-radius: var(--radius-sm);
		padding: 6px 12px;
		font-size: 0.85rem;
	}

	.lb-table-wrap {
		position: relative;
	}

	.lb-table-wrap.refreshing .lb-table {
		opacity: 0.55;
	}

	.lb-refreshing {
		position: absolute;
		top: 10px;
		right: 14px;
		font-size: 0.75rem;
		color: var(--muted);
		background: var(--surface-alt);
		border: 1px solid var(--border);
		border-radius: 999px;
		padding: 4px 10px;
		pointer-events: none;
		z-index: 1;
	}

	.lb-table {
		width: 100%;
		table-layout: fixed;
		border-collapse: collapse;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		overflow: hidden;
		transition: opacity 0.2s ease;
	}

	.lb-table th {
		text-align: left;
		padding: 12px 16px;
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--muted);
		border-bottom: 1px solid var(--border);
		background: var(--surface-alt);
	}

	.lb-row {
		cursor: pointer;
		transition: background 0.1s;
	}

	.lb-row:hover {
		background: var(--surface-hover);
	}

	.lb-row td {
		padding: 14px 16px;
		border-bottom: 1px solid var(--border);
	}

	.lb-rank {
		font-family: ui-monospace, monospace;
		font-weight: 700;
	}

	.lb-rank.gold { color: #FFD60A; }
	.lb-rank.silver { color: #C0C0C0; }
	.lb-rank.bronze { color: #CD7F32; }

	.lb-avatar, .lb-avatar-placeholder {
		width: 28px;
		height: 28px;
		border-radius: 50%;
		object-fit: cover;
		margin-right: 10px;
		vertical-align: middle;
	}

	.lb-avatar-placeholder {
		background: var(--blue-dim);
		color: var(--blue);
		display: inline-flex;
		align-items: center;
		justify-content: center;
		font-weight: 700;
		font-size: 0.85rem;
	}

	.lb-user {
		font-weight: 600;
	}

	.lb-car {
		color: var(--muted);
		font-size: 0.9rem;
	}

	.lb-value {
		font-family: ui-monospace, monospace;
		font-weight: 700;
		text-align: right;
	}

	.lb-empty, .lb-error {
		padding: 40px;
		text-align: center;
		color: var(--muted);
	}

	/* Skeleton rows: subtle pulse so the table feels alive on first load */
	.lb-skel {
		display: inline-block;
		height: 12px;
		border-radius: 4px;
		background: linear-gradient(90deg, var(--surface-alt) 0%, var(--border) 50%, var(--surface-alt) 100%);
		background-size: 200% 100%;
		animation: lb-shimmer 1.4s ease-in-out infinite;
		vertical-align: middle;
	}

	.lb-skel-avatar {
		width: 28px;
		height: 28px;
		border-radius: 50%;
		margin-right: 10px;
	}

	.lb-skeleton td {
		padding: 14px 16px;
		border-bottom: 1px solid var(--border);
	}

	.lb-skeleton {
		cursor: default;
	}

	@keyframes lb-shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
</style>
