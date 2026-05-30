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
  <title>FastTrack</title>
  <style>` + publicPageCSS + `</style>
</head>
<body>
  <main>
    <section class="hero">
      <div class="eyebrow">FastTrack</div>
      <h1>Track real-world performance runs with your iPhone.</h1>
      <p>FastTrack records speed, route, and acceleration data, syncs your drives to the cloud, and restores your garage and profile after sign-in.</p>
      <div class="cta">
        <a class="button" href="/privacy">Privacy Policy</a>
        <a class="button secondary" href="/terms">Terms of Service</a>
      </div>
    </section>
    <section class="grid">
      <article class="card">
        <h2>Built for actual drives</h2>
        <p>The iOS app combines GPS, motion sensors, live maps, and cloud sync so recorded drives and profile settings stay with your account.</p>
      </article>
      <article class="card">
        <h2>Account sync</h2>
        <p>Apple sign-in and token refresh restore your profile, garage, car stats, avatar, and display settings across devices.</p>
      </article>
    </section>
    <footer>
      FastTrack &middot; <a href="/privacy">Privacy Policy</a> &middot; <a href="/terms">Terms of Service</a>
    </footer>
  </main>
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
