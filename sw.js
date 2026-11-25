/* ==========================================================================
   sw.js (v52) – keeps the site files on the device so every page opens fast.
   • Pages (html)                  : network first (always the newest), the saved copy only when the network is slow / offline
   • style.css?v= app.js?v= ...    : saved copy first (the address changes with every version, so they are never old)
   • images / icons                : saved copy first, refreshed in the background
   • Supabase library (jsdelivr)   : saved copy first
   • The database (supabase.co), the e-mail function (/.netlify/) and everything else: NOT touched at all
   The Refresh button of the site removes this cache and reloads.
   ========================================================================== */
const VER = 'nta-v52';
const SUPA = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/';
const CORE = ['style.css?v=52', 'app.js?v=52', 'shell.js?v=52', 'export.js?v=52', 'marks.js?v=52', 'assets/logo-sm.webp', 'assets/logo.png', 'assets/icon-192.png'];

self.addEventListener('install', e => {
  e.waitUntil((async () => {
    const c = await caches.open(VER);
    await Promise.all(CORE.map(u => c.add(u).catch(() => {})));                                   // a missing file must not stop the install
    await c.add(new Request(SUPA + 'dist/umd/supabase.js', { mode: 'cors' })).catch(() => {});
    self.skipWaiting();
  })());
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k !== VER) await caches.delete(k);
    await self.clients.claim();
  })());
});

const put = async (req, res) => { if (res && res.ok && (res.type === 'basic' || res.type === 'cors')) { try { (await caches.open(VER)).put(req, res.clone()); } catch (e) {} } return res; };

async function networkFirst(req, ms) {
  const hit = await caches.match(req);
  const net = fetch(req).then(res => put(req, res));
  if (!hit) return net;
  return Promise.race([net.catch(() => hit), new Promise(r => setTimeout(() => r(hit), ms))]);
}
async function cacheFirst(req) {
  const hit = await caches.match(req);
  return hit || fetch(req).then(res => put(req, res));
}
async function staleWhileRevalidate(req) {
  const hit = await caches.match(req);
  const net = fetch(req).then(res => put(req, res)).catch(() => hit);
  return hit || net;
}

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const u = new URL(req.url);
  if (u.origin !== location.origin) {
    if (u.href.startsWith(SUPA) && req.mode === 'cors') e.respondWith(cacheFirst(req));
    return;                                                                                       // database, e-mail, other libraries: straight to the network
  }
  if (u.pathname.startsWith('/.netlify/') || u.pathname.endsWith('/sw.js')) return;
  if (req.mode === 'navigate') return void e.respondWith(networkFirst(req, 3500));
  if (u.pathname.endsWith('/config.js') || u.pathname.endsWith('/public-info.js')) return void e.respondWith(networkFirst(req, 2500));      // can change without a new version number (public-info.js = the login page's Details + Notices)
  if (u.searchParams.has('v')) return void e.respondWith(cacheFirst(req));
  if (/\.(png|webp|jpg|jpeg|svg|ico|json)$/.test(u.pathname)) return void e.respondWith(staleWhileRevalidate(req));
});
