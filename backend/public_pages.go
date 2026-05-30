package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

const publicPageCSS = `:root{color-scheme:dark;background:#0b1020;color:#f8fafc;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}body{margin:0;background:radial-gradient(circle at top,#172554 0%,#0b1020 55%,#020617 100%)}main{max-width:880px;margin:0 auto;padding:72px 24px 56px}h1,h2{line-height:1.1;margin:0 0 16px}h1{font-size:clamp(2.5rem,6vw,4.5rem)}h2{font-size:1.6rem;margin-top:40px}p,li{color:#cbd5e1;font-size:1rem;line-height:1.7}a{color:#7dd3fc}a:hover{color:#bae6fd}.eyebrow{color:#93c5fd;font-size:.85rem;font-weight:700;letter-spacing:.18em;text-transform:uppercase}.hero{padding:28px;border:1px solid rgba(148,163,184,.22);border-radius:24px;background:rgba(15,23,42,.72);backdrop-filter:blur(16px);box-shadow:0 24px 80px rgba(2,6,23,.38)}.cta{display:flex;gap:12px;flex-wrap:wrap;margin-top:28px}.button{display:inline-block;padding:12px 18px;border-radius:999px;background:#38bdf8;color:#082f49;font-weight:700;text-decoration:none}.button.secondary{background:transparent;color:#e2e8f0;border:1px solid rgba(148,163,184,.32)}.grid{display:grid;gap:18px;margin-top:28px}.card{padding:20px;border-radius:18px;border:1px solid rgba(148,163,184,.18);background:rgba(15,23,42,.62)}footer{margin-top:40px;color:#94a3b8;font-size:.95rem}ul{padding-left:20px}.meta{margin:18px 0 28px;color:#94a3b8}`

const homePageHTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#07070B">
<meta name="color-scheme" content="dark">
<meta name="description" content="FastTrack records speed, route, and acceleration data for your performance driving runs.">
<meta property="og:title" content="FastTrack — Performance Driving App">
<meta property="og:description" content="Track 0-60, quarter mile, and G-force with your iPhone.">
<meta name="twitter:card" content="summary">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🏎️</text></svg>">
<title>FastTrack — Performance Driving App</title>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{--bg:#07070B;--surface:#121216;--surface-alt:#18181D;--card:#1C1C1E;--border:rgba(255,255,255,0.06);--border-hover:rgba(255,255,255,0.12);--blue:#0A84FF;--blue-dim:rgba(10,132,255,0.12);--amber:#FF6B35;--green:#30D158;--text:#F5F5F7;--muted:#98989D;--radius:12px}
body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;line-height:1.6;-webkit-font-smoothing:antialiased;min-height:100vh;overflow-x:hidden}
a{color:var(--blue);text-decoration:none;transition:color .15s}
a:hover{color:#5EACFF}
nav{display:flex;align-items:center;justify-content:space-between;padding:16px 24px;border-bottom:1px solid var(--border);background:rgba(7,7,11,.8);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);position:sticky;top:0;z-index:100}
.nav-brand{display:flex;align-items:center;gap:10px;font-size:1.1rem;font-weight:700;color:var(--text)}
.nav-brand svg{width:24px;height:24px;fill:var(--blue);flex-shrink:0}
.nav-links{display:flex;gap:20px;font-size:.9rem}
.nav-links a{color:var(--muted);padding:4px 0;border-bottom:2px solid transparent;transition:color .15s,border-color .15s}
.nav-links a:hover{color:var(--text);border-bottom-color:var(--blue)}
.hero{text-align:center;padding:100px 24px 60px;max-width:720px;margin:0 auto;position:relative}
.hero-badge{display:inline-block;background:rgba(10,132,255,.15);color:var(--blue);border:1px solid rgba(10,132,255,.3);border-radius:20px;padding:5px 14px;font-size:.8rem;font-weight:600;letter-spacing:.05em;margin-bottom:20px}
.hero h1{font-size:clamp(2.4rem,6vw,4rem);font-weight:800;letter-spacing:-.03em;line-height:1.1;margin-bottom:20px}
.hero h1 span{background:linear-gradient(135deg,var(--blue),var(--amber));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.hero p{font-size:1.15rem;color:var(--muted);max-width:520px;margin:0 auto 32px}
.hero-cta{display:flex;gap:12px;justify-content:center;flex-wrap:wrap}
.btn{display:inline-flex;align-items:center;gap:8px;padding:12px 24px;border-radius:var(--radius);font-weight:600;font-size:.9rem;transition:all .15s;cursor:pointer;border:none;text-decoration:none!important}
.btn-primary{background:var(--blue);color:#fff}
.btn-primary:hover{background:#0058CC}
.btn-secondary{background:var(--surface);color:var(--text);border:1px solid var(--border)}
.btn-secondary:hover{border-color:var(--border-hover);background:var(--surface-alt)}
.btn-amber{background:var(--amber);color:#fff}
.btn-amber:hover{opacity:.85}
.strip{max-width:800px;margin:0 auto 20px;padding:0 24px}
.strip-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}
.strip-card{background:linear-gradient(135deg,var(--surface) 0%,var(--surface-alt) 100%);border:1px solid var(--border);border-radius:var(--radius);padding:28px 24px;text-align:center}
.strip-value{font-family:ui-monospace,SFMono-Regular,SF Mono,Menlo,Consolas,monospace;font-size:2.2rem;font-weight:700;line-height:1.2;letter-spacing:-.02em}
.strip-value.amber{color:var(--amber)}
.strip-value.blue{color:var(--blue)}
.strip-value.green{color:var(--green)}
.strip-divider{width:40px;height:3px;background:linear-gradient(90deg,var(--blue),var(--amber));border-radius:2px;margin:12px auto}
.strip-label{font-size:.7rem;text-transform:uppercase;letter-spacing:.1em;color:var(--muted);margin-top:6px;font-weight:600}
.section-divider{max-width:960px;margin:0 auto;padding:0 24px}
.section-divider hr{border:none;height:1px;background:var(--border)}
.features{max-width:960px;margin:0 auto;padding:60px 24px 40px}
.features h2{text-align:center;font-size:1.8rem;font-weight:700;margin-bottom:8px}
.features .subtitle{text-align:center;color:var(--muted);margin-bottom:40px;font-size:1rem}
.features-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px}
.feature-card{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:24px;transition:border-color .15s,transform .15s}
.feature-card:hover{border-color:rgba(10,132,255,.3);transform:translateY(-4px)}
.feature-icon{font-size:1.8rem;margin-bottom:12px;display:block}
.feature-card h3{font-size:1rem;font-weight:700;margin-bottom:6px}
.feature-card p{font-size:.85rem;color:var(--muted);line-height:1.5}
.early-access{text-align:center;padding:80px 24px;max-width:560px;margin:0 auto}
.early-access h2{font-size:1.5rem;font-weight:700;margin-bottom:8px}
.early-access p{color:var(--muted);margin-bottom:28px;font-size:.95rem}
.early-access .ea-note{font-size:.82rem;margin-top:16px;opacity:.7}
footer{max-width:960px;margin:0 auto;padding:24px;color:var(--muted);font-size:.85rem;display:flex;justify-content:space-between;flex-wrap:wrap;gap:12px;border-top:1px solid var(--border)}
footer a{color:var(--muted)}
footer a:hover{color:var(--text)}
@media(max-width:640px){
.hero{padding:60px 16px 40px}
.strip-grid{grid-template-columns:1fr;gap:8px}
.strip-value{font-size:1.8rem}
.features{padding:40px 16px 40px}
.features-grid{grid-template-columns:1fr}
}
</style>
</head>
<body>
<nav>
  <a class="nav-brand" href="/">
    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>
    FastTrack
  </a>
  <div class="nav-links">
    <a href="/leaderboard">Leaderboard</a>
  </div>
</nav>
<section class="hero">
  <div class="hero-badge">Private Beta — Join the TestFlight</div>
  <h1>Track real-world <span>performance</span> drives with your iPhone.</h1>
  <p>FastTrack combines GPS, motion sensors, and live maps to record 0-60 times, quarter mile runs, G-force, and more — then syncs everything to the cloud.</p>
  <div class="hero-cta">
    <a class="btn btn-primary" href="/leaderboard">View Leaderboard</a>
    <a class="btn btn-amber" href="mailto:testflight@fasttrack.app?subject=TestFlight%20Access%20Request">Request TestFlight Access</a>
  </div>
</section>
<div class="strip">
  <div class="strip-grid">
    <div class="strip-card">
      <div class="strip-value amber">2.7s</div>
      <div class="strip-divider"></div>
      <div class="strip-label">Best 0-60</div>
    </div>
    <div class="strip-card">
      <div class="strip-value blue">119.9</div>
      <div class="strip-divider"></div>
      <div class="strip-label">Top Speed (mph)</div>
    </div>
    <div class="strip-card">
      <div class="strip-value green">1.6G</div>
      <div class="strip-divider"></div>
      <div class="strip-label">Peak G-Force</div>
    </div>
  </div>
</div>
<div class="section-divider"><hr></div>
<div class="features">
  <h2>Built for drivers</h2>
  <p class="subtitle">Everything you need to measure and improve your performance.</p>
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
</div>
<div class="early-access">
  <h2>Get Early Access</h2>
  <p>FastTrack is currently in private beta. Join the TestFlight to be the first to track your drives.</p>
  <a class="btn btn-primary" href="mailto:testflight@fasttrack.app?subject=TestFlight%20Access%20Request">Request Invite</a>
  <p class="ea-note">Limited spots available. No spam, ever.</p>
</div>
<footer>
  <span>&copy; FastTrack</span>
  <span><a href="/leaderboard">Leaderboard</a> &middot; <a href="/privacy">Privacy</a> &middot; <a href="/terms">Terms</a></span>
</footer>
</body>
</html>`

const privacyPageHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>FastTrack Privacy Policy</title>
  <style>` + publicPageCSS + `</style>
</head>
<body>
  <main>
    <div class="eyebrow">FastTrack</div>
    <h1>Privacy Policy</h1>
    <p class="meta">Last updated: May 30, 2026</p>
    <p>FastTrack collects the information needed to authenticate your account, store your profile, and sync your recorded drives across devices.</p>
    <h2>Information we collect</h2>
    <ul>
      <li>Account details returned by Sign in with Apple or Google Sign-In, such as your provider identifier, email address, and name when shared.</li>
      <li>Profile data you save in the app, including username, country, garage details, car stats, avatar, and display preferences.</li>
      <li>Drive data you choose to record, including route, timestamps, speed metrics, and related performance statistics.</li>
    </ul>
    <h2>How we use information</h2>
    <ul>
      <li>Authenticate you and restore your profile data after sign-in or token refresh.</li>
      <li>Store and sync your recorded drives and associated stats.</li>
      <li>Operate the service, troubleshoot issues, and protect the platform.</li>
    </ul>
    <h2>Account deletion</h2>
    <p>You can request account deletion from inside the app. Deletion removes your account data from FastTrack's backend, including your profile, follows, avatar, and recorded drives.</p>
    <footer>
      <a href="/">FastTrack</a> &middot; <a href="/terms">Terms of Service</a>
    </footer>
  </main>
</body>
</html>`

const termsPageHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>FastTrack Terms of Service</title>
  <style>` + publicPageCSS + `</style>
</head>
<body>
  <main>
    <div class="eyebrow">FastTrack</div>
    <h1>Terms of Service</h1>
    <p class="meta">Last updated: May 30, 2026</p>
    <p>By using FastTrack, you agree to use the app and service responsibly and only in ways that comply with applicable law.</p>
    <h2>Use of the service</h2>
    <ul>
      <li>You are responsible for complying with traffic laws and operating your vehicle safely at all times.</li>
      <li>Do not use FastTrack in a way that endangers yourself or others.</li>
      <li>You are responsible for the accuracy of any information you add to your profile or share through the service.</li>
    </ul>
    <h2>Availability</h2>
    <p>FastTrack is provided on an as-is basis. We may update, suspend, or discontinue features as the product evolves.</p>
    <h2>Contact</h2>
    <p>Questions about these terms can be sent to <a href="mailto:support@fast.toper.dev">support@fast.toper.dev</a>.</p>
    <footer>
      <a href="/">FastTrack</a> &middot; <a href="/privacy">Privacy Policy</a>
    </footer>
  </main>
</body>
</html>`

func registerPublicPageRoutes(r *gin.Engine) {
	r.GET("/", servePublicPage(homePageHTML))
	r.GET("/privacy", servePublicPage(privacyPageHTML))
	r.GET("/terms", servePublicPage(termsPageHTML))
}

func servePublicPage(html string) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(html))
	}
}
