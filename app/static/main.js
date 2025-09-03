(function () {
  'use strict';

  // --- DOM ---
  const f = document.getElementById('f');
  const dir = document.getElementById('dir');           // <input type="file" webkitdirectory>
  const drop = document.getElementById('drop');         // div dropzone
  const pick = document.getElementById('pick');         // przycisk "Wybierz katalog"
  const go = document.getElementById('go');             // submit
  const clearBtn = document.getElementById('clear');    // reset
  const stats = document.getElementById('stats');
  const filesBox = document.getElementById('filesBox');
  const fileList = document.getElementById('fileList');
  const msg = document.getElementById('msg');

  let currentPairs = []; // [{file, rel}]

  // --- utils ---
  function setBusy(b) {
    go.disabled = b;
    go.querySelector('.txt').innerHTML = b ? '<span class="spinner"></span> Przetwarzam…' : 'Konwertuj do PDF';
  }

  function renderStats(pairs) {
    const md = pairs.filter(p => p.rel.toLowerCase().endsWith('.md')).length;
    const imgs = pairs.filter(p => /\.(png|jpe?g|gif|webp|svg)$/i.test(p.rel)).length;
    stats.textContent = `Plików: ${pairs.length} · .md: ${md} · obrazy: ${imgs}`;
    filesBox.hidden = pairs.length === 0;
  }

  function renderList(pairs) {
    if (!pairs.length) { fileList.textContent = ''; return; }
    const lines = pairs
      .slice(0, 200)
      .sort((a,b)=>a.rel.localeCompare(b.rel))
      .map(p => p.rel)
      .join('\n');
    fileList.textContent = lines + (pairs.length > 200 ? `\n… (${pairs.length-200} więcej)` : '');
  }

  // --- drag&drop katalogów ---
  async function collect(entry, prefix, out) {
    return new Promise((resolve, reject) => {
      if (entry.isFile) {
        out.push({ entry, rel: prefix + entry.name });
        resolve();
      } else if (entry.isDirectory) {
        const reader = entry.createReader();
        const batch = () => reader.readEntries(async entries => {
          if (!entries.length) return resolve();
          for (const e of entries) await collect(e, prefix + entry.name + '/', out);
          batch();
        }, reject);
        batch();
      } else resolve();
    });
  }
  function toFile(fileEntry) { return new Promise((res, rej) => fileEntry.file(res, rej)); }

  async function pairsFromDataTransfer(dt) {
    const items = [...(dt.items || [])].filter(i => i.kind === 'file');
    const entries = items.map(i => i.webkitGetAsEntry?.()).filter(Boolean);
    if (!entries.length) return [...(dt.files || [])].map(f => ({ file: f, rel: f.name }));
    const tmp = [];
    for (const e of entries) await collect(e, '', tmp);
    return Promise.all(tmp.map(async t => ({ file: await toFile(t.entry), rel: t.rel })));
  }

  function pairsFromInput(input) {
    return [...(input.files || [])].map(f => ({ file: f, rel: f.webkitRelativePath || f.name }));
  }

  function setPairs(pairs) {
    currentPairs = pairs;
    renderStats(currentPairs);
    renderList(currentPairs);
  }

  // --- zdarzenia UI ---
  pick.addEventListener('click', () => dir.click());

  dir.addEventListener('change', () => {
    setPairs(pairsFromInput(dir));
    msg.textContent = '';
    msg.className = '';
  });

  ['dragenter', 'dragover'].forEach(ev =>
    drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.add('hover'); })
  );
  ['dragleave', 'drop'].forEach(ev =>
    drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.remove('hover'); })
  );
  drop.addEventListener('drop', async e => {
    const pairs = await pairsFromDataTransfer(e.dataTransfer);
    setPairs(pairs);
    dir.value = ''; // odłącz input
  });

  clearBtn.addEventListener('click', () => {
    dir.value = '';
    currentPairs = [];
    renderStats(currentPairs);
    renderList(currentPairs);
    msg.textContent = '';
    msg.className = '';
  });

  // --- submit -> /convert ---
  f.addEventListener('submit', async e => {
    e.preventDefault();
    msg.textContent = 'Przygotowuję dane…'; msg.className = '';

    const pairs = currentPairs.length ? currentPairs : pairsFromInput(dir);
    if (!pairs.length) { msg.textContent = 'Najpierw wybierz katalog.'; msg.className = 'err'; return; }
    if (!pairs.some(p => p.rel.toLowerCase().endsWith('.md'))) { msg.textContent = 'Brak plików .md w katalogu.'; msg.className = 'err'; return; }

    const fd = new FormData();
    for (const { file, rel } of pairs) fd.append('files', file, rel);

    setBusy(true);
    try {
      const res = await fetch('/convert', { method: 'POST', body: fd });
      const raw = await res.clone().text();
      if (!res.ok) {
        try { const j = JSON.parse(raw); msg.textContent = 'Błąd: ' + (j.detail || res.statusText); }
        catch { msg.textContent = 'Błąd HTTP ' + res.status + ': ' + raw.slice(0, 500); }
        msg.className = 'err'; return;
      }
      const blob = await res.blob();
      const cd = res.headers.get('Content-Disposition') || '';
      let fname = 'report.pdf';
      const m = /filename\*=UTF-8''([^;]+)|filename="([^"]+)"/i.exec(cd);
      if (m) fname = decodeURIComponent(m[1] || m[2]);

      const url = URL.createObjectURL(blob);
      const a = Object.assign(document.createElement('a'), { href: url, download: fname });
      document.body.appendChild(a); a.click(); a.remove();
      msg.innerHTML = `Gotowe. Pobieranie: <strong>${fname}</strong>. Jeśli blokada pobierania, <a href="${url}" download="${fname}">kliknij</a>.`;
      msg.className = 'ok';
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
    } catch (err) {
      msg.textContent = 'Błąd sieci: ' + err; msg.className = 'err';
    } finally { setBusy(false); }
  });
})();
