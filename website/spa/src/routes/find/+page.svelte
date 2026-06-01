<script lang="ts">
	let query = $state('');
	let results = $state<any[]>([]);
	let loading = $state(false);
	let hasSearched = $state(false);

	const API = 'https://fast.toper.dev/api/v1';

	async function search() {
		const q = query.trim();
		if (q.length < 2) return;

		loading = true;
		hasSearched = true;

		try {
			const res = await fetch(`${API}/users/search?q=${encodeURIComponent(q)}`);
			results = await res.json();
		} catch (e) {
			results = [];
		} finally {
			loading = false;
		}
	}
</script>

<div class="container" style="padding-top: 40px;">
	<h1 style="font-size: 1.8rem; font-weight: 800; margin-bottom: 8px;">Find People</h1>
	<p style="color: var(--muted); margin-bottom: 24px;">Search public FastTrack drivers</p>

	<input
		type="text"
		placeholder="Search by username or name..."
		bind:value={query}
		oninput={search}
		style="width: 100%; max-width: 400px; padding: 12px 16px; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); color: var(--text); font-size: 1rem;"
	/>

	{#if loading}
		<div style="margin-top: 24px; color: var(--muted);">Searching…</div>
	{:else if hasSearched && results.length === 0}
		<div style="margin-top: 32px; color: var(--muted);">No public profiles found.</div>
	{:else if results.length > 0}
		<div style="margin-top: 24px;">
			{#each results as user}
				<a href="/u/{user.username}" style="display: flex; align-items: center; gap: 12px; padding: 12px 0; border-bottom: 1px solid var(--border);">
					{#if user.avatar_url}
						<img src={user.avatar_url} alt="" style="width: 36px; height: 36px; border-radius: 50%;" />
					{:else}
						<div style="width: 36px; height: 36px; border-radius: 50%; background: var(--blue-dim); display: flex; align-items: center; justify-content: center; color: var(--blue); font-weight: 700;">
							{user.username[0].toUpperCase()}
						</div>
					{/if}
					<div>
						<div style="font-weight: 600;">@{user.username}</div>
						{#if user.full_name}<div style="color: var(--muted); font-size: 0.85rem;">{user.full_name}</div>{/if}
					</div>
				</a>
			{/each}
		</div>
	{/if}

	<div style="margin-top: 40px; font-size: 0.9rem; color: var(--muted);">
		Sign in with the app for follow status and more powerful discovery.
	</div>
</div>
