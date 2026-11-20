'use strict';

(() => {
  const $ = (id) => document.getElementById(id);
  const api = window.vpn;

  const state = {
    countries: [],
    tab: 'all',
    query: '',
    sort: 'name',
    status: { phase: 'disconnected' },
    favorites: new Set(loadJson('favorites', [])),
    lastCountry: loadJson('lastCountry', null),
    openVpnInstalled: true,
    platform: 'win32',
    loading: false,
  };

  // ---------- storage helpers (storage can be unavailable) ----------
  function loadJson(key, fallback) {
    try {
      const v = localStorage.getItem(key);
      return v === null ? fallback : JSON.parse(v);
    } catch {
      return fallback;
    }
  }
  function saveJson(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* ignore */ }
  }

  // ---------- formatting ----------
  function formatBytes(n) {
    if (!n || n < 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    let v = n;
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i += 1; }
    return `${v.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
  }
  function formatSpeed(bps) {
    const mbps = (bps || 0) / 1e6;
    return mbps >= 10 ? `${Math.round(mbps)} Mbps` : `${mbps.toFixed(1)} Mbps`;
  }
  function formatDuration(ms) {
    const s = Math.max(0, Math.floor(ms / 1000));
    const pad = (x) => String(x).padStart(2, '0');
    return `${pad(Math.floor(s / 3600))}:${pad(Math.floor((s % 3600) / 60))}:${pad(s % 60)}`;
  }
  function rating(bps) {
    const mbps = (bps || 0) / 1e6;
    if (mbps >= 100) return 5;
    if (mbps >= 50) return 4.5;
    if (mbps >= 20) return 4;
    if (mbps >= 5) return 3.5;
    return 3;
  }
  function starText(value) {
    const full = Math.floor(value);
    return `${'★'.repeat(full)}${'☆'.repeat(5 - full)} ${value.toFixed(1)}`;
  }

  function el(tag, attrs = {}, children = []) {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (k === 'class') node.className = v;
      else if (k === 'text') node.textContent = v;
      else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
      else node.setAttribute(k, v);
    }
    for (const c of [].concat(children)) if (c) node.append(c);
    return node;
  }

  function flag(code) {
    const safe = String(code || '').toLowerCase().replace(/[^a-z]/g, '').slice(0, 2);
    const img = el('img', { class: 'flag', alt: `${code} flag`, loading: 'lazy', src: `https://flagcdn.com/w80/${safe}.png` });
    img.addEventListener('error', () => img.replaceWith(el('div', { class: 'flag-fallback', text: safe.toUpperCase() || '??' })), { once: true });
    return img;
  }

  // ---------- toast ----------
  let toastTimer = null;
  function toast(msg, ok = false) {
    const t = $('toast');
    t.textContent = msg;
    t.classList.toggle('ok', ok);
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.hidden = true; }, 6000);
  }

  // ---------- servers ----------
  async function loadServers(force) {
    if (state.loading) return;
    state.loading = true;
    $('refresh').disabled = true;
    if (!state.countries.length) renderSkeleton();
    try {
      const res = await api.listServers(force);
      state.countries = res.countries || [];
      $('updated').textContent = res.updatedAt
        ? `Server list updated ${new Date(res.updatedAt).toLocaleTimeString()}${res.fromCache ? ' (saved)' : ''}`
        : '';
      if (res.error) toast(res.error);
      else if (force) toast(`Found ${state.countries.length} countries with free servers.`, true);
    } catch (err) {
      toast(`Could not load servers: ${err.message || err}`);
    } finally {
      state.loading = false;
      $('refresh').disabled = false;
      render();
    }
  }

  function visibleCountries() {
    let list = state.countries;
    const q = state.query.trim().toLowerCase();
    if (q) list = list.filter((c) => c.name.toLowerCase().includes(q) || c.code.toLowerCase() === q);
    if (state.tab === 'favorites') list = list.filter((c) => state.favorites.has(c.code));
    const sorters = {
      name: (a, b) => a.name.localeCompare(b.name),
      speed: (a, b) => b.bestSpeed - a.bestSpeed,
      ping: (a, b) => a.bestPing - b.bestPing,
      servers: (a, b) => b.servers.length - a.servers.length,
    };
    const sort = state.tab === 'fastest' ? 'speed' : state.sort;
    list = [...list].sort(sorters[sort] || sorters.name);
    if (state.tab === 'fastest') list = list.slice(0, 12);
    return list;
  }

  function fastestCodes() {
    return new Set([...state.countries].sort((a, b) => b.bestSpeed - a.bestSpeed).slice(0, 3).map((c) => c.code));
  }

  function renderSkeleton() {
    const grid = $('grid');
    grid.replaceChildren(...Array.from({ length: 8 }, () => el('div', { class: 'skeleton' })));
    grid.setAttribute('aria-busy', 'true');
    $('empty').hidden = true;
  }

  function render() {
    const grid = $('grid');
    grid.setAttribute('aria-busy', 'false');
    const list = visibleCountries();
    const titles = { all: 'Free VPN servers by country', fastest: 'Fastest countries right now', favorites: 'Your favorite countries' };
    $('results-title').textContent = titles[state.tab];
    $('results-count').textContent = state.countries.length
      ? `${list.length} ${list.length === 1 ? 'result' : 'results'}${state.query ? ` for "${state.query}"` : ''}`
      : '';

    const empty = $('empty');
    if (!list.length) {
      grid.replaceChildren();
      empty.hidden = false;
      let title = 'No servers found';
      let text = 'Try another search, or refresh the server list.';
      if (!state.countries.length) {
        title = 'The free server list is not available';
        text = 'Check your internet connection and press "Refresh servers".';
      } else if (state.tab === 'favorites' && !state.query) {
        title = 'No favorites yet';
        text = 'Tap the ☆ on any country to save it here.';
      }
      empty.replaceChildren(el('h3', { text: title }), el('p', { text }));
      return;
    }
    empty.hidden = true;

    const fast = fastestCodes();
    const current = state.status.server && state.status.phase !== 'disconnected' ? state.status.server.countryCode : null;
    grid.replaceChildren(...list.map((c) => countryCard(c, fast.has(c.code), current === c.code)));
  }

  function countryCard(c, isFast, isCurrent) {
    const busy = state.status.phase === 'connecting' || state.status.phase === 'disconnecting';
    const fav = state.favorites.has(c.code);
    const r = rating(c.bestSpeed);
    const favBtn = el('button', {
      class: `fav${fav ? ' on' : ''}`, title: fav ? 'Remove from favorites' : 'Add to favorites',
      'aria-label': fav ? 'Remove from favorites' : 'Add to favorites', text: fav ? '★' : '☆',
      onclick: () => toggleFavorite(c.code),
    });
    const connectBtn = isCurrent && state.status.phase === 'connected'
      ? el('button', { class: 'btn btn-orange', text: 'Disconnect', onclick: () => disconnect() })
      : el('button', { class: 'btn btn-yellow', text: isCurrent && busy ? 'Connecting…' : 'Connect', onclick: () => connect({ countryCode: c.code }) });
    if (busy) connectBtn.disabled = true;

    return el('article', { class: `country${isCurrent ? ' current' : ''}` }, [
      isCurrent ? el('span', { class: 'badge', text: state.status.phase === 'connected' ? 'Connected' : 'Connecting' })
        : isFast ? el('span', { class: 'badge fast', text: 'Fastest' }) : null,
      el('div', { class: 'country-top' }, [flag(c.code), el('div', { class: 'country-name', text: c.name }), favBtn]),
      el('div', { class: 'stars', title: `Speed rating ${r} out of 5` }, [
        document.createTextNode(starText(r)),
        el('span', { text: `${c.servers.length} ${c.servers.length === 1 ? 'server' : 'servers'}` }),
      ]),
      el('div', { class: 'meta' }, [
        document.createTextNode('Up to '), el('b', { text: formatSpeed(c.bestSpeed) }),
        document.createTextNode(c.bestPing < 9999 ? ` · ${c.bestPing} ms ping` : ''),
      ]),
      el('div', { class: 'price' }, [el('span', { class: 'free', text: 'FREE' }), el('span', { class: 'prime', text: 'no sign-up' })]),
      el('div', { class: 'country-actions' }, [
        connectBtn,
        el('button', { class: 'btn btn-white', text: 'Servers', onclick: () => openServers(c) }),
      ]),
    ]);
  }

  function toggleFavorite(code) {
    if (state.favorites.has(code)) state.favorites.delete(code);
    else state.favorites.add(code);
    saveJson('favorites', [...state.favorites]);
    render();
  }

  // ---------- server modal ----------
  let modalCountry = null;
  function openServers(c) {
    modalCountry = c;
    $('modal-title').textContent = `${c.name} — ${c.servers.length} free ${c.servers.length === 1 ? 'server' : 'servers'}`;
    renderModal();
    $('modal').hidden = false;
    $('modal-close').focus();
  }
  function renderModal() {
    if (!modalCountry) return;
    const busy = state.status.phase === 'connecting' || state.status.phase === 'disconnecting';
    const rows = [el('div', { class: 'server-row head' }, [
      el('div', { text: 'Server' }), el('div', { text: 'Ping' }), el('div', { text: 'Speed' }), el('div', { text: 'Type' }), el('div'),
    ])];
    for (const s of modalCountry.servers) {
      const isCurrent = state.status.server && state.status.server.id === s.id && state.status.phase === 'connected';
      const btn = isCurrent
        ? el('button', { class: 'btn btn-orange', text: 'Disconnect', onclick: () => { closeModal(); disconnect(); } })
        : el('button', { class: 'btn btn-yellow', text: 'Connect', onclick: () => { closeModal(); connect({ serverId: s.id }); } });
      if (busy) btn.disabled = true;
      rows.push(el('div', { class: 'server-row' }, [
        el('div', { class: 'host' }, [document.createTextNode(s.hostName), el('small', { text: `${s.ip} · ${s.sessions} users online` })]),
        el('div', { text: s.ping > 0 ? `${s.ping} ms` : '—' }),
        el('div', { text: formatSpeed(s.speed) }),
        el('div', { text: s.protocol }),
        btn,
      ]));
    }
    $('modal-body').replaceChildren(...rows);
  }
  function closeModal() {
    $('modal').hidden = true;
    modalCountry = null;
  }

  // ---------- connection ----------
  async function connect(args) {
    if (!state.openVpnInstalled) {
      showOpenVpnBanner();
      toast('Please install OpenVPN first (see the yellow box at the top).');
      return;
    }
    const country = args.countryCode || (state.countries.find((c) => c.servers.some((s) => s.id === args.serverId)) || {}).code;
    if (country) {
      state.lastCountry = country;
      saveJson('lastCountry', country);
    }
    try {
      const res = await api.connect(args);
      if (!res.ok && res.error === 'OPENVPN_MISSING') {
        state.openVpnInstalled = false;
        showOpenVpnBanner();
      } else if (!res.ok && res.error) {
        toast(res.error);
      } else if (res.ok) {
        toast(`Connected to ${state.status.server ? state.status.server.countryName : 'VPN'}.`, true);
      }
    } catch (err) {
      toast(err.message || String(err));
    }
  }

  async function disconnect() {
    try {
      await api.disconnect();
    } catch (err) {
      toast(err.message || String(err));
    }
  }

  function quickConnect() {
    if (!state.countries.length) {
      toast('The server list is still loading. Please try again in a moment.');
      return;
    }
    const last = state.countries.find((c) => c.code === state.lastCountry);
    if (last) {
      connect({ countryCode: last.code });
      return;
    }
    let best = null;
    for (const c of state.countries) {
      if (c.servers.length && (!best || c.servers[0].score > best.servers[0].score)) best = c;
    }
    if (best) connect({ countryCode: best.code });
  }

  function onPower() {
    const { phase } = state.status;
    if (phase === 'connected' || phase === 'connecting') disconnect();
    else if (phase === 'disconnected') quickConnect();
  }

  let lastPhase = 'disconnected';
  let selFlagCode = null;
  function applyStatus(s) {
    state.status = s;
    const phase = s.phase;
    const labels = { disconnected: 'Not connected', connecting: 'Connecting…', connected: 'Protected', disconnecting: 'Disconnecting…' };
    $('power').dataset.phase = phase;
    $('power').setAttribute('aria-label', phase === 'disconnected' ? 'Connect' : 'Disconnect');
    $('power').disabled = phase === 'disconnecting';
    const phaseEl = $('phase');
    phaseEl.textContent = s.error && phase === 'disconnected' ? 'Connection failed' : labels[phase];
    phaseEl.className = `phase ${phase === 'connected' ? 'connected' : s.error && phase === 'disconnected' ? 'error' : ''}`;
    let detail = s.detail || '';
    if (phase === 'connecting' && s.attempt > 1) detail += ` (trying server ${s.attempt})`;
    if (phase === 'disconnected') detail = s.error || 'Pick a country or press the button for the fastest free server.';
    if (phase === 'connected' && s.server) detail = `Your traffic now goes through ${s.server.countryName}.`;
    $('detail').textContent = detail;

    const showSel = s.server && phase !== 'disconnected';
    $('selected').hidden = !showSel;
    if (showSel) {
      if (selFlagCode !== s.server.countryCode) {
        selFlagCode = s.server.countryCode;
        $('sel-flag').replaceChildren(flag(selFlagCode));
      }
      $('sel-name').textContent = s.server.countryName;
      $('sel-host').textContent = `${s.server.hostName} · ${s.server.ip}`;
    }
    $('down').textContent = formatBytes(s.bytesIn);
    $('up').textContent = formatBytes(s.bytesOut);
    $('connect-btn').hidden = phase !== 'disconnected';
    $('disconnect-btn').hidden = phase === 'disconnected';
    $('disconnect-btn').disabled = phase === 'disconnecting';
    $('disconnect-btn').textContent = phase === 'connecting' ? 'Cancel' : 'Disconnect';

    const navStatus = $('nav-status');
    navStatus.textContent = phase === 'connected' ? `Protected · ${s.server ? s.server.countryCode : ''}` : labels[phase];
    navStatus.classList.toggle('on', phase === 'connected');

    if (phase !== lastPhase) {
      if (phase === 'connected' || phase === 'disconnected') refreshIp(phase === 'connected' ? 1500 : 800);
      lastPhase = phase;
      render();
      renderModal();
    }
    updateTimer();
  }

  function updateTimer() {
    const s = state.status;
    $('timer').textContent = s.phase === 'connected' && s.connectedAt ? formatDuration(Date.now() - s.connectedAt) : '00:00:00';
  }

  let ipTimer = null;
  let ipRequest = 0;
  function refreshIp(delay = 0) {
    clearTimeout(ipTimer);
    ipTimer = setTimeout(async () => {
      const req = ++ipRequest;
      $('nav-ip').textContent = 'Checking…';
      try {
        const info = await api.publicIp();
        if (req !== ipRequest) return;
        const text = info.ip ? `${info.ip}${info.countryCode ? ` (${info.countryCode})` : ''}` : 'Unavailable';
        $('nav-ip').textContent = text;
        $('ip').textContent = info.ip || '—';
      } catch {
        if (req === ipRequest) $('nav-ip').textContent = 'Unavailable';
      }
    }, delay);
  }

  // ---------- OpenVPN setup banner ----------
  function showOpenVpnBanner() {
    const help = {
      win32: 'MRMZone VPN uses the free, open-source OpenVPN engine. Download the Windows installer, install it with default options, then restart this app.',
      darwin: 'MRMZone VPN uses the free, open-source OpenVPN engine. Install it with Homebrew: open Terminal and run "brew install openvpn", then restart this app.',
      linux: 'MRMZone VPN uses the free, open-source OpenVPN engine. Install it with your package manager, for example "sudo apt install openvpn", then restart this app.',
    };
    $('openvpn-help').textContent = help[state.platform] || help.linux;
    $('openvpn-banner').hidden = false;
  }

  // ---------- events ----------
  $('search-form').addEventListener('submit', (e) => { e.preventDefault(); state.query = $('search').value; render(); });
  $('search').addEventListener('input', (e) => { state.query = e.target.value; render(); });
  $('sort').addEventListener('change', (e) => { state.sort = e.target.value; render(); });
  for (const tab of document.querySelectorAll('.tab[data-tab]')) {
    tab.addEventListener('click', () => {
      state.tab = tab.dataset.tab;
      document.querySelectorAll('.tab[data-tab]').forEach((t) => t.classList.toggle('active', t === tab));
      render();
    });
  }
  $('refresh').addEventListener('click', () => loadServers(true));
  $('power').addEventListener('click', onPower);
  $('connect-btn').addEventListener('click', quickConnect);
  $('disconnect-btn').addEventListener('click', disconnect);
  $('modal-close').addEventListener('click', closeModal);
  $('modal').addEventListener('click', (e) => { if (e.target === $('modal')) closeModal(); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !$('modal').hidden) closeModal(); });
  $('vpngate-link').addEventListener('click', (e) => { e.preventDefault(); api.openExternal('https://www.vpngate.net/en/'); });
  $('openvpn-download').addEventListener('click', () => {
    api.openExternal(state.platform === 'darwin' ? 'https://formulae.brew.sh/formula/openvpn' : 'https://openvpn.net/community-downloads/');
  });

  api.onStatus(applyStatus);
  setInterval(updateTimer, 1000);

  // ---------- start ----------
  (async () => {
    try {
      const check = await api.checkOpenVpn();
      state.platform = check.platform;
      state.openVpnInstalled = check.installed;
      if (!check.installed) showOpenVpnBanner();
    } catch { /* ignore */ }
    try { applyStatus(await api.getStatus()); } catch { /* ignore */ }
    refreshIp();
    await loadServers(false);
  })();
})();
