<script lang="ts">
	import { page } from '$app/stores';

	let username = $derived($page.params.username);

	interface PublicProfile {
		username: string;
		full_name: string;
		country: string;
		avatar_url: string;
		member_since: string;
		top_speed: number;
		total_distance: number;
		drive_count: number;
		best_060_time: number | null;
		follower_count: number;
		following_count: number;
		garage?: any[];
	}

	interface FollowUser {
		user_id: number;
		username: string;
		country: string;
	}

	let profile = $state<PublicProfile | null>(null);
	let followers = $state<FollowUser[]>([]);
	let following = $state<FollowUser[]>([]);
	let loading = $state(true);
	let error = $state('');

	const API = 'https://fast.toper.dev/api/v1';

	async function loadProfile() {
		loading = true;
		error = '';

		try {
			const [profileRes, followersRes, followingRes] = await Promise.all([
				fetch(`${API}/users/${username}`),
				fetch(`${API}/users/${username}/followers`),
				fetch(`${API}/users/${username}/following`)
			]);

			if (!profileRes.ok) throw new Error('User not found');

			profile = await profileRes.json();
			followers = await followersRes.json();
			following = await followingRes.json();
		} catch (e) {
			error = 'Profile not found or unavailable.';
		} finally {
			loading = false;
		}
	}

	$effect(() => {
		if (username) loadProfile();
	});

	function formatSpeed(ms: number) {
		return (ms * 2.23694).toFixed(1);
	}

	function formatDistance(m: number) {
		return (m / 1609.34).toFixed(1);
	}
</script>

<div class="container" style="padding-top: 40px;">
	{#if loading}
		<div>Loading profile…</div>
	{:else if error || !profile}
		<div style="text-align:center; padding: 80px 0;">
			<h1 style="font-size: 2rem; margin-bottom: 8px;">Profile not found</h1>
			<p style="color: var(--muted);">This driver is either private or does not exist.</p>
			<a href="/leaderboard" style="display: inline-block; margin-top: 24px;">Back to Leaderboard</a>
		</div>
	{:else}
		<!-- Profile Header -->
		<div class="profile-hero">
			<div class="profile-header">
				{#if profile.avatar_url}
					<img class="profile-avatar" src={profile.avatar_url} alt={profile.username} />
				{:else}
					<div class="profile-avatar-placeholder">{profile.username[0].toUpperCase()}</div>
				{/if}
				<div class="profile-name">
					<h1>{profile.full_name || profile.username}</h1>
					<div class="username">@{profile.username}</div>
					<div class="meta">
						{profile.country ? profile.country + ' · ' : ''}Member since {new Date(profile.member_since).toLocaleDateString('en-US', { month: 'short', year: 'numeric' })}
					</div>
				</div>
			</div>

			<!-- Stats -->
			<div class="profile-stats">
				<div class="stat-card">
					<div class="stat-value speed">{profile.top_speed ? formatSpeed(profile.top_speed) : '—'}</div>
					<div class="stat-label">Top Speed</div>
				</div>
				<div class="stat-card">
					<div class="stat-value default">{profile.drive_count}</div>
					<div class="stat-label">Drives</div>
				</div>
				<div class="stat-card">
					<div class="stat-value default">{profile.total_distance ? formatDistance(profile.total_distance) : '—'}</div>
					<div class="stat-label">Total Distance</div>
				</div>
				<div class="stat-card">
					<div class="stat-value performance">{profile.best_060_time ? profile.best_060_time.toFixed(1) + 's' : '—'}</div>
					<div class="stat-label">Best 0-60</div>
				</div>
			</div>
		</div>

		<!-- Garage -->
		{#if profile.garage && profile.garage.length > 0}
			<div class="section">
				<div class="section-title">Garage</div>
				<div class="garage-grid">
					{#each profile.garage as car}
						<div class="garage-card">
							<div class="car-nickname">{car.nickname || `${car.make} ${car.model}`}</div>
							<div class="car-model">{car.year || ''} {car.make} {car.model} {car.trim || ''}</div>
						</div>
					{/each}
				</div>
			</div>
		{/if}

		<!-- Social -->
		<div class="section">
			<div class="section-title">Social</div>
			<div class="social-row">
				<span class="social-stat"><strong>{profile.follower_count}</strong> followers</span>
				<span class="social-stat"><strong>{profile.following_count}</strong> following</span>
			</div>
		</div>

		<!-- Followers / Following lists -->
		<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 24px; margin-top: 24px;">
			<div>
				<div class="section-title">Followers ({followers.length})</div>
				{#each followers as user}
					<a href="/u/{user.username}" class="social-user">
						<div class="su-name">{user.username}</div>
						{#if user.country}<div class="su-country">{user.country}</div>{/if}
					</a>
				{:else}
					<p style="color: var(--muted); font-size: 0.9rem;">No followers yet</p>
				{/each}
			</div>

			<div>
				<div class="section-title">Following ({following.length})</div>
				{#each following as user}
					<a href="/u/{user.username}" class="social-user">
						<div class="su-name">{user.username}</div>
						{#if user.country}<div class="su-country">{user.country}</div>{/if}
					</a>
				{:else}
					<p style="color: var(--muted); font-size: 0.9rem;">Not following anyone yet</p>
				{/each}
			</div>
		</div>
	{/if}
</div>

<style>
	/* Reuses global .profile-hero, .social-user etc. from layout.css */
	.social-user {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 10px 0;
		border-bottom: 1px solid var(--border);
		color: var(--text);
	}
	.social-user:last-child {
		border-bottom: none;
	}
	.su-name {
		font-weight: 600;
	}
	.su-country {
		color: var(--muted);
		font-size: 0.8rem;
	}
</style>
