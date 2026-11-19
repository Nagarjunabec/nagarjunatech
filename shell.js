/* ==========================================================================
   shell.js – Azure-style left navigation + slim top bar for every logged-in page (v47)
   buildShell('dash' | 'create' | 'email' | 'students' | 'sub:<subjectCode>')
   Sidebar:  Dashboard
             Subjects  >  <subject>  >  Students · Syllabus · Lesson Plan · Materials · Video Lessons · Theory Marks · Notices · Lab Programs · Lab Marks · CR
             Create Subject · Students · Email  (admin only)
             Profile · Log out
   Subjects come from the database (the last list is cached for the session). Only the front end changed in v47.
   ========================================================================== */
const ICONS = {
  home:'<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>',
  plus:'<line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>',
  mail:'<path d="M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z"/><polyline points="22,6 12,13 2,6"/>',
  logout:'<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>',
  menu:'<line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="18" x2="21" y2="18"/>',
  book:'<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>',
  users:'<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  bell:'<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/>',
  flask:'<path d="M9 3h6"/><path d="M10 3v6L4 19a2 2 0 0 0 2 3h12a2 2 0 0 0 2-3l-6-10V3"/>',
  layers:'<polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/><polyline points="2 12 12 17 22 12"/>',
  clock:'<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
  shield:'<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
  file:'<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="8" y1="13" x2="16" y2="13"/><line x1="8" y1="17" x2="16" y2="17"/>',
  play:'<circle cx="12" cy="12" r="10"/><polygon points="10 8 16 12 10 16 10 8"/>',
  table:'<rect x="3" y="3" width="18" height="18" rx="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="3" y1="15" x2="21" y2="15"/><line x1="9" y1="3" x2="9" y2="21"/>',
  list:'<line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/>',
  chev:'<polyline points="9 18 15 12 9 6"/>',
  panel:'<rect x="3" y="3" width="18" height="18" rx="2"/><line x1="9" y1="3" x2="9" y2="21"/>',
  inbox:'<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/><path d="M5.45 5.11L2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>'
};
const ico = n => '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + ICONS[n] + '</svg>';

/* the features (tabs) of a subject: the same list and rules the subject page uses */
const FEATS = [['students','Students','users'],['syllabus','Syllabus','book'],['lessonplan','Lesson Plan','list'],['materials','Materials','file'],['videos','Video Lessons','play'],
  ['marks','Theory Marks','table'],['notices','Notices','bell'],['labs','Lab Programs','flask'],['labsheet','Lab Marks','table'],['crs','CR','shield']];
const FEAT_N = { students: 'students', materials: 'materials', notices: 'notices', labs: 'labs', videos: 'videos' };   // counts that subjects_list already returns
const featsFor = kind => FEATS
  .filter(t => (t[0] != 'labs' && t[0] != 'labsheet') || kind == 'lab')
  .filter(t => ROLE == 'student' ? t[0] != 'students' && t[0] != 'crs' : ROLE == 'admin' || t[0] != 'crs');

const HTMLEL = document.documentElement, WIDE = () => matchMedia('(min-width:901px)').matches;
const chev = () => ico('chev').replace('class="ic"', 'class="ic chev"');
function setCollapsed(c, save) {                                         // desktop / tablet: icons only (c = true) or icons + labels
  HTMLEL.classList.toggle('sbc', c); hideTip();
  if (save) try { localStorage.ng_sbc = c ? '1' : '0'; } catch (e) {}
  const b = $('#burger'); if (b) b.setAttribute('aria-expanded', String(!c));
}

/* tooltips for the icon-only sidebar */
let tipEl = null;
function hideTip() { if (tipEl) tipEl.hidden = true; }
function showTip(t) {
  if (!HTMLEL.classList.contains('sbc') || !WIDE()) return hideTip();
  if (!tipEl) { tipEl = document.createElement('div'); tipEl.className = 'tip'; tipEl.setAttribute('role', 'tooltip'); document.body.appendChild(tipEl); }
  const r = t.getBoundingClientRect();
  tipEl.textContent = t.dataset.tip; tipEl.style.left = (r.right + 8) + 'px'; tipEl.style.top = (r.top + r.height / 2) + 'px'; tipEl.hidden = false;
}

function buildShell(active) {
  const name = localStorage.ng_name || 'User', sub = localStorage.ng_sub || '';
  const dash = { k: 'dash', l: 'Dashboard', i: 'home', h: 'dashboard' };
  const more = ROLE == 'admin' ? [{ k: 'create', l: 'Create Subject', i: 'plus', h: 'subjects' }, { k: 'students', l: 'Students', i: 'users', h: 'students' }, { k: 'email', l: 'Email', i: 'mail', h: 'email' }] : [];
  const link = x => '<a href="' + page(x.h) + '" class="it' + (x.k == active ? ' on' : '') + '" data-tip="' + esc(x.l) + '">' + ico(x.i) + '<span class="lb">' + esc(x.l) + '</span></a>';

  document.body.classList.add('busy');                                   // thin progress bar until the page has drawn its content
  const main = $('#main');
  if (main && window.MutationObserver) {
    const done = () => { document.body.classList.remove('busy'); mo.disconnect(); };
    const mo = new MutationObserver(() => { if (main.firstElementChild && !main.querySelector(':scope > .skel')) done(); });
    mo.observe(main, { childList: true });
    setTimeout(done, 15000);
  }

  const gOpen = localStorage.ng_sbg != '0';
  $('#side').innerHTML =
    '<div class="brand"><img src="' + BASE + 'assets/logo-sm.webp" width="26" height="26" alt="" decoding="async"><div class="bt"><b>Nagarjuna</b><span>Tech Academy</span></div></div>' +
    '<nav class="menu" aria-label="Main">' + link(dash) +
      '<div class="nd grp' + (gOpen ? ' open' : '') + '" id="gsub"><button type="button" class="it grpb" aria-expanded="' + gOpen + '" data-tip="Subjects">' + ico('layers') + '<span class="lb">Subjects</span>' + chev() + '</button>' +
        '<div class="pn"><div class="pi"><div id="sidesubs" class="subs"><div class="menu-sk"><div class="sk-s"></div><div class="sk-s"></div><div class="sk-s"></div></div></div></div></div></div>' +
      (more.length ? '<div class="sbsep"></div>' + more.map(link).join('') : '') + '</nav>' +
    '<div class="sbf">' +
      '<button type="button" class="it meb" onclick="openProfile()" data-tip="My profile"><span id="meav">' + avatar(name, localStorage.ng_photo) + '</span><span class="lb me-t"><b>' + esc(name) + '</b><small>' + esc(sub) + '</small></span></button>' +
      '<button type="button" class="it out" onclick="logout()" data-tip="Log out">' + ico('logout') + '<span class="lb">Log out</span></button></div>';

  const cur = [dash].concat(more).find(x => x.k == active);
  $('#top').innerHTML = '<button type="button" class="burger" id="burger" aria-label="Show or hide the menu" title="Show or hide the menu">' + ico('panel') + '</button>' +
    '<div class="top-t" id="topt"></div>' +
    '<button type="button" class="bellb" aria-label="Refresh" title="Refresh" onclick="hardRefresh(this)">' + REFRESH_ICO + '</button>';
  setCrumb(active.startsWith('sub:') ? ['Subjects', active.slice(4)] : [cur ? cur.l : 'Nagarjuna Tech Academy']);

  const close = () => document.body.classList.remove('drawer');
  $('#burger').onclick = () => WIDE() ? setCollapsed(!HTMLEL.classList.contains('sbc'), true) : document.body.classList.toggle('drawer');
  $('#scrim').onclick = close;
  addEventListener('keydown', e => { if (e.key == 'Escape') close(); });
  addEventListener('resize', () => { if (WIDE()) close(); hideTip(); });
  setCollapsed(HTMLEL.classList.contains('sbc'));

  const side = $('#side');
  side.addEventListener('mouseover', e => { const t = e.target.closest('[data-tip]'); t ? showTip(t) : hideTip(); });
  side.addEventListener('mouseleave', hideTip);
  side.addEventListener('focusin', e => { const t = e.target.closest('[data-tip]'); t ? showTip(t) : hideTip(); });
  side.addEventListener('focusout', hideTip);
  side.addEventListener('click', e => {
    const g = e.target.closest('.grpb');                                    // "Subjects" group
    if (g) {
      if (!WIDE() || !HTMLEL.classList.contains('sbc')) { const nd = g.closest('.nd'), o = !nd.classList.contains('open'); nd.classList.toggle('open', o); g.setAttribute('aria-expanded', String(o)); try { localStorage.ng_sbg = o ? '1' : '0'; } catch (e) {} }
      return;
    }
    const sb = e.target.closest('.sbtn');                                   // one subject: open its features, close the others
    if (sb) {
      const sg = sb.closest('.sg'), code = sg.dataset.code;
      const rail = WIDE() && HTMLEL.classList.contains('sbc');                          // icon-only bar: widen it first, then show this subject's features
      if (rail) setCollapsed(false, true);
      const was = sg.classList.contains('open') && !rail;
      side.querySelectorAll('#sidesubs .sg.open').forEach(x => { x.classList.remove('open'); x.querySelector('.sbtn').setAttribute('aria-expanded', 'false'); });
      if (!was) { sg.classList.add('open'); sb.setAttribute('aria-expanded', 'true'); }
      window.SIDE_OPEN = was ? '' : code; try { localStorage.ng_sbo = SIDE_OPEN; } catch (e) {}
      hideTip();
      return;
    }
    const a = e.target.closest('a');
    if (!a) return;
    if (a.classList.contains('sf') && window.SIDE_ACTIVE == 'sub:' + a.dataset.code && typeof window.go == 'function') {   // same subject: switch the feature without reloading
      e.preventDefault(); window.go(a.dataset.tab);
    }
    close();
  });

  loadSide(active);
  /* keep name / photo in step with the database (the photo may have been changed on another device) - not urgent, so it waits a moment */
  setTimeout(() => T('profile_get').then(p => { if (!p) return; localStorage.ng_name = p.name; if (p.photo) localStorage.ng_photo = p.photo; else delete localStorage.ng_photo; refreshMe(); }).catch(() => {}), 1200);
}

/* breadcrumb in the top bar:  Subjects > DS-2026-2027 > Students */
function setCrumb(parts) {
  const el = $('#topt'); if (!el) return;
  el.innerHTML = parts.map((p, i) => i == parts.length - 1 ? '<b>' + esc(p) + '</b>' : '<span>' + esc(p) + '</span><em>›</em>').join('');
}
/* the subject page calls this whenever it draws a feature: highlights it in the sidebar, fills the counts, updates the breadcrumb */
function sideTab(t, counts) {
  window.SIDE_TAB = t;
  const code = (window.SIDE_ACTIVE || '').slice(4); if (!code) return;
  document.querySelectorAll('#sidesubs .sf').forEach(a => {
    if (a.dataset.code != code) return;
    a.classList.toggle('on', a.dataset.tab == t);
    if (counts) {
      const n = counts[a.dataset.tab]; let i = a.querySelector('.ct');
      if (n === undefined || n === '') { if (i) i.remove(); }
      else { if (!i) { i = document.createElement('i'); i.className = 'ct'; a.appendChild(i); } i.textContent = n; }
    }
  });
  const f = FEATS.find(x => x[0] == t); setCrumb(['Subjects', code, f ? f[1] : t]);
}

function refreshMe() {
  const n = localStorage.ng_name || 'User';
  if ($('#meav')) $('#meav').innerHTML = avatar(n, localStorage.ng_photo);
  if ($('#topav')) $('#topav').innerHTML = avatar(n, localStorage.ng_photo);
  const b = document.querySelector('.me-t b'); if (b) b.textContent = n;
}

/* my profile: photo for everybody, own password for students (CR and admin passwords: only the admin / SQL file) */
function openProfile() {
  const n = localStorage.ng_name || 'User';
  modal('<h3>My profile</h3><div class="prof">' + avatar(n, localStorage.ng_photo, 'lg') +
    '<div><b>' + esc(n) + '</b><br><span class="sm">' + esc(localStorage.ng_sub || '') + '</span>' +
    '<div class="row" style="margin:10px 0 0"><label class="btn alt" style="cursor:pointer">Change photo<input type="file" id="pf" accept="image/*" hidden></label>' +
    (localStorage.ng_photo ? '<button class="btn alt" id="pr">Remove photo</button>' : '') + '</div></div></div>' +
    (ROLE == 'student' ? '<h3 style="margin-top:20px;font-size:17px">Change password</h3>' +
      '<label class="fld">Current password<input id="po" type="password" autocomplete="current-password"></label>' +
      '<label class="fld">New password<input id="pn" type="password" autocomplete="new-password"></label>' +
      '<label class="fld">New password again<input id="pn2" type="password" autocomplete="new-password"></label>' +
      '<div class="row" style="margin:0"><button class="btn y" id="ps">Change password</button></div>' +
      '<p class="sm">You do not have to change it. If you forget it, use "Forgot password" on the login page: it goes back to your Reg No.</p>' :
      ROLE == 'cr' ? '<p class="sm" style="margin-top:14px">Your password is set by the admin. Only the admin can reset it.</p>' : '') +
    '<div class="row" style="margin:14px 0 0"><button class="btn alt" onclick="closeModal()">Close</button></div>');
  const save = async p => { await T('profile_photo_set', { p }); if (p) localStorage.ng_photo = p; else delete localStorage.ng_photo; refreshMe(); openProfile(); toast(p ? 'Photo saved' : 'Photo removed'); };
  $('#pf').onchange = e => run(async () => save(await photoFromFile(e.target.files[0])));
  if ($('#pr')) $('#pr').onclick = e => run(() => save(null), e.target);
  if ($('#ps')) $('#ps').onclick = e => run(async () => {
    const v = { o: $('#po').value, n: $('#pn').value, n2: $('#pn2').value };       // read before the popup closes
    if (v.n != v.n2) throw new Error('The two new passwords are not the same');
    await T('password_change', { old: v.o, nw: v.n });
    closeModal(); toast('Password changed');
  }, e.target);
}

/* Subjects > one row per subject (click = open / close its features) > the features as links.
   The last list is kept for this session, so the menu is drawn at once and then refreshed from the database.
   Pages can await SUBS (call loadSide again after creating / deleting a subject). */
function paintSide(list, active) {
  const el = $('#sidesubs'); if (!el) return;
  const cur = active && active.startsWith('sub:') ? active.slice(4) : '';
  window.SIDE_ACTIVE = active;
  if (window.SIDE_OPEN === undefined) window.SIDE_OPEN = cur || localStorage.ng_sbo || '';
  el.innerHTML = list.map(s => {
    const open = s.code == SIDE_OPEN, tip = esc(s.full_name || s.code);
    return '<div class="nd sg' + (open ? ' open' : '') + (s.code == cur ? ' cur' : '') + '" data-code="' + esc(s.code) + '">' +
      '<button type="button" class="it sbtn" aria-expanded="' + open + '" data-tip="' + tip + '">' + ico('book') + '<span class="lb">' + esc(s.code) + '</span>' + chev() + '</button>' +
      '<div class="pn"><div class="pi">' + featsFor(s.kind).map(f => {
        const n = FEAT_N[f[0]] ? s[FEAT_N[f[0]]] : undefined;
        return '<a href="' + subUrl(s.code, f[0]) + '" class="it sf' + (s.code == cur && f[0] == window.SIDE_TAB ? ' on' : '') + '" data-code="' + esc(s.code) + '" data-tab="' + f[0] + '" data-tip="' + esc(f[1]) + '">' +
          ico(f[2]) + '<span class="lb">' + esc(f[1]) + '</span>' + (n === undefined || n === null ? '' : '<i class="ct">' + esc(n) + '</i>') + '</a>';
      }).join('') + '</div></div></div>';
  }).join('') || '<div class="menu-empty">' + (ROLE == 'admin' ? 'No subjects yet' : 'No subjects assigned') + '</div>';
  if (cur && window.SIDE_TAB) sideTab(SIDE_TAB);
}
function loadSide(active) {
  window.SIDE_ACTIVE = active;
  const c = cachedSubs(); if (c) paintSide(c, active);
  const p = window.SUBS_P || T('subjects_list'); window.SUBS_P = null;                 // a page may already have asked for the list
  window.SUBS = p.then(list => { keepSubs(list); paintSide(list, active); return list; });
  return SUBS.catch(e => toast(e.message, 1));
}

/* simple modal */
function modal(html) { const m = $('#modal'); m.innerHTML = '<div class="mb">' + html + '</div>'; m.hidden = false; m.onclick = e => { if (e.target == m) closeModal(); }; }
function closeModal() { $('#modal').hidden = true; $('#modal').innerHTML = ''; }

/* shared page frame: html for the pages (the pages only contain <div id="app">) */
function needLogin(roles) {
  if (!tok()) { location.href = HOME; return false; }
  if (roles && !roles.includes(ROLE)) { location.href = page('dashboard'); return false; }
  return true;
}
