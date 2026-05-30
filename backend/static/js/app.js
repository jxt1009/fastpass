// ─── Leaderboard ──────────────────────────────────────

const LEADERBOARD_API = '/api/v1/leaderboard'

let lbState = {
  category: 'top_speed',
  scope: 'global',
  period: 'all_time',
  car_make: '',
  car_model: ''
}

function initLeaderboard() {
  bindFilterClicks()
  bindFilterSelects()
  fetchLeaderboard()
}

function bindFilterClicks() {
  document.querySelectorAll('[data-filter]').forEach(el => {
    el.addEventListener('click', () => {
      const group = el.dataset.group
      const value = el.dataset.filter
      if (!group || !value) return

      lbState[group] = value

      // Update active class within this group
      const siblings = document.querySelectorAll(`[data-group="${group}"]`)
      siblings.forEach(s => {
        s.classList.remove('active', 'active-amber', 'active-green')
        // Apply appropriate active style based on the group
        if (group === 'category') {
          if (s.dataset.filter === 'top_speed') s.classList.add('active-amber')
          else s.classList.add('active')
        }
      })
      el.classList.add(group === 'category' && value === 'top_speed' ? 'active-amber' : 'active')
      fetchLeaderboard()
    })
  })
}

function bindFilterSelects() {
  document.querySelectorAll('[data-filter-select]').forEach(sel => {
    sel.addEventListener('change', () => {
      const group = sel.dataset.filterSelect
      lbState[group] = sel.value
      fetchLeaderboard()
    })
  })
}

function fetchLeaderboard() {
  const tbody = document.querySelector('#lb-table tbody')
  if (!tbody) return

  tbody.innerHTML = '<tr><td colspan="5" class="lb-loading">Loading…</td></tr>'

  const params = new URLSearchParams({
    category: lbState.category,
    scope: lbState.scope,
    period: lbState.period
  })
  if (lbState.car_make) params.set('car_make', lbState.car_make)
  if (lbState.car_model) params.set('car_model', lbState.car_model)

  fetch(`${LEADERBOARD_API}?${params}`)
    .then(r => {
      if (!r.ok) throw new Error('Failed to fetch')
      return r.json()
    })
    .then(data => renderLeaderboard(data))
    .catch(() => {
      tbody.innerHTML = '<tr><td colspan="5" class="lb-loading">Failed to load leaderboard</td></tr>'
    })
}

function renderLeaderboard(entries) {
  const tbody = document.querySelector('#lb-table tbody')
  if (!tbody) return

  if (!entries || entries.length === 0) {
    tbody.innerHTML = '<tr><td colspan="5" class="lb-empty">No results found</td></tr>'
    return
  }

  const valueLabel = {
    top_speed: 'mph',
    best_060: 's',
    total_distance: 'mi',
    drive_count: ''
  }[lbState.category] || ''

  const isSpeed = lbState.category === 'top_speed'
  const isPerformance = lbState.category === 'best_060'

  tbody.innerHTML = entries.map(e => {
    const rankClass = e.rank === 1 ? 'gold' : e.rank === 2 ? 'silver' : e.rank === 3 ? 'bronze' : ''
    const valueClass = isSpeed ? 'speed' : isPerformance ? 'performance' : ''
    const avatarHtml = e.avatar_url
      ? `<img class="lb-avatar" src="${e.avatar_url}" alt="">`
      : `<span class="lb-avatar-placeholder">${e.username.charAt(0).toUpperCase()}</span>`
    const value = formatValue(e.value, lbState.category)
    const carStr = e.car_make || e.car_model ? `${e.car_make || ''} ${e.car_model || ''}`.trim() : '—'

    return `<tr>
      <td><span class="lb-rank ${rankClass}">#${e.rank}</span></td>
      <td>${avatarHtml}<a class="lb-user" href="/u/${e.username}">${e.username}</a></td>
      <td class="lb-car">${carStr}</td>
      <td class="lb-value ${valueClass}">${value} ${valueLabel}</td>
    </tr>`
  }).join('')
}

function formatValue(val, category) {
  if (val == null || val === 0) return '—'
  switch (category) {
    case 'top_speed': return (val * 2.23694).toFixed(1) // m/s to mph
    case 'best_060': return val.toFixed(1)
    case 'total_distance': return (val / 1609.34).toFixed(1) // m to mi
    case 'drive_count': return val.toLocaleString()
    default: return val.toLocaleString()
  }
}

// ─── Profile social modal ─────────────────────────────

function initProfile() {
  document.querySelectorAll('[data-modal]').forEach(btn => {
    btn.addEventListener('click', () => {
      const target = document.getElementById(btn.dataset.modal)
      if (target) target.classList.add('open')
    })
  })
  document.querySelectorAll('.social-modal-close, .social-modal').forEach(el => {
    el.addEventListener('click', (e) => {
      if (e.target === el || e.target.closest('.social-modal-close')) {
        el.closest('.social-modal')?.classList.remove('open')
      }
    })
  })
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      document.querySelectorAll('.social-modal.open').forEach(m => m.classList.remove('open'))
    }
  })
}

// ─── Init on page load ────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  if (document.getElementById('lb-table')) initLeaderboard()
  if (document.querySelector('[data-modal]')) initProfile()
})
