// ─── Leaderboard ──────────────────────────────────────

const LEADERBOARD_API = '/api/v1/leaderboard'
const USER_API = '/api/v1/users'
const CAR_MODELS_API = '/api/v1/cars/models'

let lbState = {
  category: 'top_speed',
  scope: 'global',
  period: 'all_time',
  car_make: '',
  car_model: ''
}

const CATEGORY_LABELS = {
  top_speed: 'Top Speed',
  best_060: '0-60',
  total_distance: 'Distance',
  drive_count: 'Drives'
}

const CATEGORY_UNITS = {
  top_speed: '<span class="lb-unit">mph</span>',
  best_060: '<span class="lb-unit">s</span>',
  total_distance: '<span class="lb-unit">mi</span>',
  drive_count: ''
}

function initLeaderboard() {
  bindFilterClicks()
  bindFilterSelects()
  updateValueHeader()
  fetchLeaderboard()
}

function bindFilterClicks() {
  document.querySelectorAll('[data-filter]').forEach(el => {
    el.addEventListener('click', () => {
      const group = el.dataset.group
      const value = el.dataset.filter
      if (!group || !value) return

      lbState[group] = value

      document.querySelectorAll(`[data-group="${group}"]`).forEach(s => {
        s.classList.remove('active', 'active-amber', 'active-green')
      })

      if (group === 'category' && value === 'top_speed') {
        el.classList.add('active-amber')
      } else {
        el.classList.add('active')
      }

      if (group === 'category') updateValueHeader()
      fetchLeaderboard()
    })
  })
}

function bindFilterSelects() {
  document.querySelectorAll('[data-filter-select]').forEach(sel => {
    sel.addEventListener('change', () => {
      const group = sel.dataset.filterSelect
      lbState[group] = sel.value

      if (group === 'car_make') {
        lbState.car_model = ''
        const modelSel = document.querySelector('[data-filter-select="car_model"]')
        if (modelSel) modelSel.value = ''
        populateModels(lbState.car_make)
      }

      fetchLeaderboard()
    })
  })
}

function updateValueHeader() {
  const th = document.querySelector('#lb-table th:last-child')
  if (th) th.textContent = CATEGORY_LABELS[lbState.category] || 'Value'
}

function populateModels(make) {
  const sel = document.querySelector('[data-filter-select="car_model"]')
  if (!sel) return
  sel.innerHTML = '<option value="">All Models</option>'
  sel.disabled = !make
  if (!make) return
  fetch(`${CAR_MODELS_API}?make=${encodeURIComponent(make)}`)
    .then(r => r.ok ? r.json() : [])
    .then(models => {
      models.forEach(m => {
        const opt = document.createElement('option')
        opt.value = m
        opt.textContent = m
        sel.appendChild(opt)
      })
    })
    .catch(() => {})
}

function fetchLeaderboard() {
  const tbody = document.querySelector('#lb-table tbody')
  if (!tbody) return

  tbody.classList.add('lb-loading')

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
    .then(data => {
      renderLeaderboard(data)
      // Double rAF to let the browser paint new rows at 0.3 opacity,
      // then remove loading class so they transition smoothly to 1.0.
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          tbody.classList.remove('lb-loading')
        })
      })
    })
    .catch(() => {
      tbody.innerHTML = '<tr><td colspan="4" class="lb-empty">Failed to load leaderboard</td></tr>'
      tbody.classList.remove('lb-loading')
    })
}

function renderLeaderboard(entries) {
  const tbody = document.querySelector('#lb-table tbody')
  if (!tbody) return

  const unit = CATEGORY_UNITS[lbState.category] || ''
  const isSpeed = lbState.category === 'top_speed'
  const isPerformance = lbState.category === 'best_060'

  if (!entries || entries.length === 0) {
    tbody.innerHTML = '<tr><td colspan="4" class="lb-empty">No results found</td></tr>'
    tbody.classList.remove('lb-loading')
    return
  }

  tbody.innerHTML = entries.map(e => {
    const rankClass = e.rank === 1 ? 'gold' : e.rank === 2 ? 'silver' : e.rank === 3 ? 'bronze' : ''
    const valueClass = isSpeed ? 'speed' : isPerformance ? 'performance' : ''
    const avatarHtml = e.avatar_url
      ? `<img class="lb-avatar" src="${e.avatar_url}" alt="">`
      : `<span class="lb-avatar-placeholder">${e.username.charAt(0).toUpperCase()}</span>`
    const value = formatValue(e.value, lbState.category)
    const carStr = e.car_make || e.car_model ? `${e.car_make || ''} ${e.car_model || ''}`.trim() : '—'

    return `<tr class="lb-row" data-username="${e.username}">
      <td><span class="lb-rank ${rankClass}">#${e.rank}</span></td>
      <td>${avatarHtml}<a class="lb-user" href="/u/${e.username}">${e.username}</a></td>
      <td class="lb-car">${carStr}</td>
      <td class="lb-value ${valueClass}">${value} ${unit}</td>
    </tr>`
  }).join('')

  tbody.classList.remove('lb-loading')
  bindRowClicks()
}

function bindRowClicks() {
  document.querySelectorAll('.lb-row').forEach(row => {
    row.addEventListener('click', e => {
      if (e.target.closest('a')) return
      const username = row.dataset.username
      if (username) showUserStats(username)
    })
  })
}

function formatValue(val, category) {
  if (val == null || val === 0) return '—'
  switch (category) {
    case 'top_speed': return (val * 2.23694).toFixed(1)
    case 'best_060': return val.toFixed(1)
    case 'total_distance': return (val / 1609.34).toFixed(1)
    case 'drive_count': return val.toLocaleString()
    default: return val.toLocaleString()
  }
}

// ─── Leaderboard Row Stats Popover ──────────────────

function showUserStats(username) {
  const existing = document.getElementById('stats-popover')
  if (existing) existing.remove()

  const overlay = document.createElement('div')
  overlay.className = 'stats-overlay'
  overlay.id = 'stats-popover'
  overlay.innerHTML = '<div class="stats-panel"><div class="stats-loading">Loading…</div></div>'
  document.body.appendChild(overlay)

  overlay.addEventListener('click', e => {
    if (e.target === overlay) overlay.remove()
  })
  document.addEventListener('keydown', closeOnEsc)

  fetch(`${USER_API}/${username}`)
    .then(r => {
      if (!r.ok) throw new Error('Not found')
      return r.json()
    })
    .then(data => renderStatsPopover(data, overlay))
    .catch(() => {
      overlay.querySelector('.stats-panel').innerHTML = '<div class="stats-error">Could not load stats</div>'
    })
}

function renderStatsPopover(data, overlay) {
  const avatarHtml = data.avatar_url
    ? `<img class="sp-avatar" src="${data.avatar_url}" alt="">`
    : `<div class="sp-avatar-placeholder">${data.username.charAt(0).toUpperCase()}</div>`

  const garage = (() => {
    try { return JSON.parse(data.garage || '[]') } catch { return [] }
  })()

  overlay.querySelector('.stats-panel').innerHTML = `
    <button class="stats-close">&times;</button>
    <div class="sp-header">
      ${avatarHtml}
      <div>
        <div class="sp-name">${data.full_name || data.username}</div>
        <a class="sp-username" href="/u/${data.username}">@${data.username}</a>
        ${data.country ? '<div class="sp-country">' + data.country + '</div>' : ''}
      </div>
    </div>
    <div class="sp-stats">
      <div class="sp-stat">
        <div class="sp-value speed">${data.top_speed ? formatValue(data.top_speed, 'top_speed') : '—'}</div>
        <div class="sp-label">Top Speed</div>
      </div>
      <div class="sp-stat">
        <div class="sp-value performance">${data.best_060_time ? data.best_060_time.toFixed(1) : '—'}</div>
        <div class="sp-label">0-60</div>
      </div>
      <div class="sp-stat">
        <div class="sp-value default">${data.drive_count}</div>
        <div class="sp-label">Drives</div>
      </div>
      <div class="sp-stat">
        <div class="sp-value default">${data.total_distance ? formatValue(data.total_distance, 'total_distance') : '—'}</div>
        <div class="sp-label">Distance</div>
      </div>
    </div>
    ${garage.length ? '<div class="sp-garage">' + garage.map(c => '<span class="sp-car">' + (c.nickname || c.make + ' ' + c.model) + '</span>').join('') + '</div>' : ''}
    <div class="sp-footer">
      <a href="/u/${data.username}">View full profile &rarr;</a>
    </div>
  `

  overlay.querySelector('.stats-close').addEventListener('click', () => overlay.remove())
}

function closeOnEsc(e) {
  if (e.key === 'Escape') {
    const el = document.getElementById('stats-popover')
    if (el) el.remove()
    document.removeEventListener('keydown', closeOnEsc)
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

// ─── Follow / Unfollow ────────────────────────────

function initFollowButtons() {
  document.querySelectorAll('.follow-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const username = btn.dataset.username
      const token = btn.dataset.jwt
      const isFollowing = btn.classList.contains('following')

      if (!token) return

      btn.disabled = true
      btn.textContent = '...'

      try {
        const response = await fetch(`/api/v1/users/${username}/follow`, {
          method: isFollowing ? 'DELETE' : 'POST',
          headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json'
          }
        })

        if (!response.ok) {
          // Refresh page on error to get fresh state
          location.reload()
          return
        }

        btn.classList.toggle('following')
        btn.textContent = isFollowing ? 'Follow' : 'Following'
      } catch {
        // Refresh page on error to get fresh state
        location.reload()
      } finally {
        btn.disabled = false
      }
    })
  })
}

// ─── Init on page load ────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  if (document.getElementById('lb-table')) initLeaderboard()
  if (document.querySelector('[data-modal]')) initProfile()
  if (document.querySelector('.follow-btn')) initFollowButtons()
})
