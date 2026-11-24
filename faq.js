/* faq.js — "ask the panel" experience for #faq on the Vicaro homepage.
   Reads questions and answers from the <details> list in the DOM (single
   source of truth — no answer strings are duplicated here). Client-side
   token matching only: no model, no network calls. */
(() => {
  "use strict";
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const el = html => { const t = document.createElement("template"); t.innerHTML = html.trim(); return t.content.firstElementChild; };

  const panel = $("#faq-panel"), thread = $("#fq-thread"), input = $("#fq-input"),
        opts = $("#fq-opts"), chipsEl = $("#faq-chips"), allWrap = $(".faq-all");
  if (!panel || !thread || !input || !allWrap) return;

  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const CWS = "https://chromewebstore.google.com/detail/vicaro-beta/inemnoeadlodgmheeijooeknmladelok";
  const TOPICS = { safety: "Safety", privacy: "Privacy", models: "Models", setup: "Setup", pricing: "Pricing & license" };
  const LINK_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 13a5 5 0 007.54.54l3-3a5 5 0 00-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 00-7.54-.54l-3 3a5 5 0 007.07 7.07l1.71-1.71"/></svg>';

  /* -- read the DOM list (source of truth) -- */
  const items = $$(".faq > details", allWrap).map(d => {
    const a = $("p", d);
    return {
      id: d.id,
      q: $("summary", d).textContent.replace(/\s+/g, " ").trim(),
      aHTML: a ? a.innerHTML : "",
      aText: a ? a.textContent.replace(/\s+/g, " ").trim() : "",
      topic: d.dataset.topic || "",
      src: d.dataset.sources || "",
      node: d,
    };
  });
  const byId = Object.fromEntries(items.map(i => [i.id, i]));
  let topic = "all", asked = new Set(), typing = 0, matches = [], active = -1;

  const scrollThread = smooth => thread.scrollTo({ top: thread.scrollHeight, behavior: smooth && !reduceMotion ? "smooth" : "instant" });

  /* -- copy link -- */
  function copyLink(id, btn) {
    const url = location.origin + location.pathname + "#" + id;
    const flash = () => {
      btn.classList.add("done");
      const t = btn.querySelector("span");
      if (t) t.textContent = "Copied";
      setTimeout(() => { btn.classList.remove("done"); if (t) t.textContent = "Copy link"; }, 1600);
    };
    const fallback = () => {
      const ta = document.createElement("textarea");
      ta.value = url;
      document.body.append(ta);
      ta.select();
      try { document.execCommand("copy"); } catch (e) {}
      ta.remove();
      flash();
    };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(url).then(flash, fallback);
    else fallback();
  }
  // small copy-link button on every list item
  items.forEach(i => {
    const b = el(`<button type="button" class="fq-linkbtn" aria-label="Copy link to this answer">${LINK_ICON}</button>`);
    b.addEventListener("click", e => { e.preventDefault(); e.stopPropagation(); copyLink(i.id, b); });
    i.node.querySelector("summary").append(b);
  });

  /* -- progressive enhancement -- */
  panel.hidden = false;
  allWrap.open = false;

  /* -- home state -- */
  const suggButton = i => {
    const b = el(`<button type="button" class="sugg"><b></b><span></span></button>`);
    $("b", b).textContent = i.q;
    $("span", b).textContent = TOPICS[i.topic] || i.topic;
    b.addEventListener("click", () => ask(i.id));
    return b;
  };
  function fillSuggestions(list) {
    list.innerHTML = "";
    items.filter(i => topic === "all" || i.topic === topic).forEach(i => list.append(suggButton(i)));
  }
  function renderHome() {
    thread.innerHTML = "";
    const home = el(`<div class="fq-home"><p class="fq-home-q">What do you want to know?</p><div class="sugg-list fq-suggs"></div></div>`);
    fillSuggestions($(".fq-suggs", home));
    thread.append(home);
  }

  /* -- topic chips -- */
  chipsEl && chipsEl.addEventListener("click", e => {
    const b = e.target.closest(".faq-chip");
    if (!b) return;
    topic = b.dataset.topic;
    $$(".faq-chip", chipsEl).forEach(c => c.setAttribute("aria-pressed", String(c === b)));
    items.forEach(i => { i.node.hidden = !(topic === "all" || i.topic === topic); });
    const list = $(".fq-suggs", thread);
    if (list) fillSuggestions(list);
  });

  /* -- asking -- */
  function ask(id) {
    const it = byId[id];
    if (!it) return;
    asked.add(id);
    hideOpts();
    input.value = "";
    const u = el(`<div class="vp-user"><p></p></div>`);
    $("p", u).textContent = it.q;
    const ans = el(`<div class="vp-answer"><span class="vh" aria-live="polite"></span><p class="fq-typed" aria-hidden="true"></p></div>`);
    thread.append(u, el(`<p class="vp-label"><b>VICARO</b> · NOW</p>`), ans);
    scrollThread();
    $(".vh", ans).textContent = it.aText; // full text announced once for screen readers
    const typed = $(".fq-typed", ans);
    const finish = () => { extras(it, ans); scrollThread(true); };
    if (reduceMotion) { typed.innerHTML = it.aHTML; finish(); return; }
    const words = it.aText.split(/\s+/);
    const step = Math.max(12, Math.round(700 / words.length));
    const my = ++typing;
    let i = 0;
    (function tick() {
      if (my !== typing) { typed.innerHTML = it.aHTML; return; } // superseded: fill instantly
      typed.textContent = words.slice(0, ++i).join(" ");
      scrollThread();
      if (i >= words.length) { typed.innerHTML = it.aHTML; finish(); }
      else setTimeout(tick, step);
    })();
  }

  function extras(it, ans) {
    if (it.src) {
      const s = el(`<p class="fq-sources"><b>SOURCES</b></p>`);
      it.src.split(",").forEach(pair => {
        const [label, href] = pair.split("|");
        const a = document.createElement("a");
        a.href = (href || "").trim();
        a.textContent = (label || "").trim();
        s.append(a);
      });
      ans.append(s);
    }
    if (WIDGETS[it.id]) ans.append(WIDGETS[it.id]());
    const cp = el(`<button type="button" class="fq-copy">${LINK_ICON}<span>Copy link</span></button>`);
    cp.addEventListener("click", () => copyLink(it.id, cp));
    const acts = el(`<div class="fq-actions"></div>`);
    acts.append(cp);
    ans.append(acts);
    const rel = items.filter(i => i.topic === it.topic && i.id !== it.id && !asked.has(i.id)).slice(0, 3);
    if (rel.length) {
      const wrap = el(`<div><p class="fq-rel-label">RELATED</p><div class="fq-rels"></div></div>`);
      rel.forEach(r => {
        const c = el(`<button type="button" class="fq-rel"></button>`);
        c.textContent = r.q;
        c.addEventListener("click", () => ask(r.id));
        $(".fq-rels", wrap).append(c);
      });
      ans.append(wrap);
    }
  }

  function replyNoMatch(text) {
    const u = el(`<div class="vp-user"><p></p></div>`);
    $("p", u).textContent = text;
    const ans = el(`<div class="vp-answer">
      <span class="vh" aria-live="polite">I couldn't find that in these answers.</span>
      <p>I couldn't find that in these answers.</p>
      <div class="fq-actions"><a class="fq-go">Email the team</a><a class="fq-go" href="support.html">Support</a></div>
    </div>`);
    $(".fq-go", ans).href = "mailto:hello@creativeducks.com?subject=" + encodeURIComponent("Question: " + text);
    thread.append(u, el(`<p class="vp-label"><b>VICARO</b> · NOW</p>`), ans);
    scrollThread(true);
  }

  /* -- search -- */
  const GROUPS = [
    ["cost", "price", "free", "pay"], ["windows", "linux", "pc", "ubuntu"],
    ["privacy", "data", "cloud", "server", "upload", "send"],
    ["model", "llm", "ollama", "gpt", "openai", "local"],
    ["safe", "risk", "danger", "delete", "mistake", "undo"],
    ["install", "terminal", "curl", "setup", "download"],
    ["uninstall", "remove", "app"], ["login", "account", "google", "sign"],
    ["open", "source", "github", "code"], ["sleep", "asleep", "offline", "background"],
    ["cursor", "claude", "mcp", "codex"], ["trick", "injection", "attack", "hack"],
    ["web", "app", "console", "dashboard", "ui", "browser app"],
  ];
  const terms = tok => {
    const out = new Set([tok]);
    GROUPS.forEach(g => { if (g.includes(tok)) g.forEach(t => out.add(t)); });
    return [...out];
  };
  function find(text) {
    const toks = text.toLowerCase().replace(/[^a-z0-9+/.~]+/g, " ").split(/\s+/).filter(t => t.length > 1);
    if (!toks.length) return [];
    const rx = (x, wb) => new RegExp("\\b" + x.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + (wb ? "\\b" : ""), "i");
    const hit = (txt, ts, wb) => ts.some(x => rx(x, wb).test(txt));
    return items.map(i => {
      const q = i.q.toLowerCase(), a = i.aText.toLowerCase();
      let s = 0;
      for (const t of toks) {
        const ts = terms(t);
        if (hit(q, ts, true)) s += 3;         // whole-word hits in questions weigh more
        else if (hit(a, ts, false)) s += 1;
      }
      if (s && q.includes(text.trim())) s += 10;  // exact phrase in the question wins
      return { i, s };
    }).filter(x => x.s > 0).sort((a, b) => b.s - a.s);
  }

  /* -- combobox -- */
  function hideOpts() {
    opts.hidden = true;
    opts.innerHTML = "";
    input.setAttribute("aria-expanded", "false");
    input.removeAttribute("aria-activedescendant");
    active = -1;
  }
  function renderOpts() {
    if (!matches.length) { hideOpts(); return; }
    opts.innerHTML = "";
    matches.forEach((m, idx) => {
      const o = el(`<div class="fq-opt" role="option" id="fq-opt-${idx}" aria-selected="false"><span class="fq-oq"></span><small></small></div>`);
      $(".fq-oq", o).textContent = m.i.q;
      $("small", o).textContent = TOPICS[m.i.topic] || m.i.topic;
      o.addEventListener("mousedown", e => e.preventDefault());
      o.addEventListener("click", () => ask(m.i.id));
      opts.append(o);
    });
    opts.hidden = false;
    input.setAttribute("aria-expanded", "true");
  }
  input.addEventListener("input", () => { matches = find(input.value).slice(0, 4); active = -1; renderOpts(); });
  input.addEventListener("keydown", e => {
    const n = matches.length;
    if (e.key === "ArrowDown" && n) { e.preventDefault(); active = (active + 1) % n; }
    else if (e.key === "ArrowUp" && n) { e.preventDefault(); active = (active - 1 + n) % n; }
    else if (e.key === "Escape") { input.value = ""; matches = []; hideOpts(); return; }
    else if (e.key === "Enter") {
      e.preventDefault();
      if (active >= 0 && matches[active]) ask(matches[active].i.id);
      else submit();
      return;
    } else return;
    [...opts.children].forEach((o, idx) => o.setAttribute("aria-selected", String(idx === active)));
    if (active >= 0) {
      input.setAttribute("aria-activedescendant", "fq-opt-" + active);
      opts.children[active].scrollIntoView({ block: "nearest" });
    } else input.removeAttribute("aria-activedescendant");
  });
  input.addEventListener("blur", () => setTimeout(hideOpts, 150));
  function submit() {
    const text = input.value.trim();
    if (!text) return;
    const m = find(text);
    if (m.length && m[0].s >= 3 && (!m[1] || m[0].s > m[1].s)) ask(m[0].i.id);
    else replyNoMatch(text);
  }
  $("#fq-send").addEventListener("click", submit);

  /* -- new chat -- */
  $("#fq-new").addEventListener("click", () => {
    typing++;
    asked.clear();
    input.value = "";
    matches = [];
    hideOpts();
    renderHome();
  });

  /* -- "show me" + widgets -- */
  function showMe(targetSel, inputSel) {
    const inp = $(inputSel);
    if (inp) inp.click();
    const t = $(targetSel);
    if (t) t.scrollIntoView({ behavior: reduceMotion ? "instant" : "smooth" });
  }
  function actWidget(defs) {
    const w = el(`<div class="fq-widget"><div class="fq-actions"></div></div>`);
    defs.forEach(([label, target, sel]) => {
      const b = el(`<button type="button" class="fq-go"></button>`);
      b.textContent = label;
      b.addEventListener("click", () => showMe(target, sel));
      $(".fq-actions", w).append(b);
    });
    return w;
  }

  async function detectCompat() {
    const rows = [];
    let plat = "", platVer = null, arch = null, brands = [], winFlag = false;
    const ua = navigator.userAgent;
    try {
      const uad = navigator.userAgentData;
      if (uad) {
        plat = uad.platform || "";
        const hi = await uad.getHighEntropyValues(["platformVersion", "architecture", "fullVersionList"]).catch(() => null);
        if (hi) { platVer = hi.platformVersion; arch = hi.architecture; brands = hi.fullVersionList || []; }
        if (!brands.length) brands = uad.brands || [];
      }
    } catch (e) {}
    plat = plat || navigator.platform || "";

    if (/Android|iPhone|iPad|iPod/.test(ua) || /android|ios/i.test(plat)) rows.push(["bad", "Open this page on your Mac."]);
    else if (/mac/i.test(plat)) {
      if (platVer) {
        const [maj, min] = platVer.split(".").map(Number);
        rows.push((maj > 13 || (maj === 13 && min >= 5)) ? ["ok", `macOS ${platVer}`] : ["bad", `macOS ${platVer} — needs 13.5 or newer`]);
      } else rows.push(["warn", "macOS detected. Check that you're on 13.5 or newer."]);
    }
    else if (/win/i.test(plat)) { rows.push(["warn", "Windows — support is coming soon."]); winFlag = true; }
    else if (/cros/i.test(plat)) rows.push(["bad", "ChromeOS — not supported yet."]);
    else if (/linux/i.test(plat)) rows.push(["bad", "Linux — helper in progress."]);
    else rows.push(["warn", "Could not detect your OS."]);

    const gc = brands.find(b => b.brand === "Google Chrome");
    const chromium = brands.some(b => /Chrom/.test(b.brand)) || /Chrome|CriOS|Edg|Brave|OPR/.test(ua);
    if (gc) rows.push(parseInt(gc.version, 10) >= 116 ? ["ok", `Chrome ${gc.version}`] : ["bad", `Chrome ${gc.version} — update Chrome`]);
    else if (chromium) rows.push(["warn", "Vicaro is built and tested for Chrome"]);
    else rows.push(["bad", "Vicaro needs Chrome 116+"]);

    if (arch === "arm") rows.push(["ok", "Apple Silicon"]);
    else if (arch === "x86") rows.push(["ok", "Intel"]);
    else rows.push(["warn", "Apple Silicon and Intel are both supported"]);

    const hasBad = rows.some(r => r[0] === "bad"), hasWarn = rows.some(r => r[0] === "warn");
    if (!hasBad && !hasWarn) return { rows, verdict: "Looks good.", cta: ["Add to Chrome", CWS] };
    if (winFlag) return { rows, verdict: "Not on this computer yet. Windows support is coming soon.", cta: ["Follow releases", "https://github.com/sandeshwar/vicaro-public/releases"] };
    if (hasBad) return { rows, verdict: "Not on this computer yet.", cta: ["Follow releases", "https://github.com/sandeshwar/vicaro-public/releases"] };
    return { rows, verdict: "Probably fine. Check the items above.", cta: null };
  }
  function wCompat() {
    const w = el(`<div class="fq-widget"><p class="fq-wlabel">BASED ON WHAT YOUR BROWSER REPORTS.</p><div class="fq-rows"></div><p class="fq-verdict"></p><div class="fq-actions"></div></div>`);
    const ICONS = { ok: "✓", warn: "!", bad: "✕" };
    detectCompat().then(({ rows, verdict, cta }) => {
      rows.forEach(([k, msg]) => {
        const r = el(`<div class="fq-row"><span class="fq-ic ${k}">${ICONS[k]}</span><span></span></div>`);
        r.lastElementChild.textContent = msg;
        $(".fq-rows", w).append(r);
      });
      $(".fq-verdict", w).textContent = verdict;
      if (cta) {
        const a = el(`<a class="btn small"></a>`);
        a.href = cta[1];
        a.textContent = cta[0];
        $(".fq-actions", w).append(a);
      }
      scrollThread();
    }).catch(() => {
      $(".fq-rows", w).append(el(`<div class="fq-row"><span class="fq-ic warn">!</span><span>Could not check automatically.</span></div>`));
      $(".fq-verdict", w).textContent = "Probably fine. Check the items above.";
    });
    return w;
  }

  function wPicker() {
    const questions = [
      "Must page content stay on your Mac?",
      "Do you want Vicaro to use screenshots?",
      "Do you already pay for an AI API?",
    ];
    const state = [null, null, null];
    const w = el(`<div class="fq-widget fq-picker"><div class="fq-result" hidden></div></div>`);
    const result = $(".fq-result", w);
    questions.forEach((q, qi) => {
      const row = el(`<div class="fq-q"><span></span><div class="fq-yn"><button type="button" aria-pressed="false">Yes</button><button type="button" aria-pressed="false">No</button></div></div>`);
      $("span", row).textContent = q;
      const [yes, no] = $$("button", row);
      const set = v => {
        state[qi] = state[qi] === v ? null : v;
        yes.setAttribute("aria-pressed", String(state[qi] === true));
        no.setAttribute("aria-pressed", String(state[qi] === false));
        update();
      };
      yes.addEventListener("click", () => set(true));
      no.addEventListener("click", () => set(false));
      w.insertBefore(row, result);
    });
    function update() {
      const [q1, q2, q3] = state;
      if (q1 === null) { result.hidden = true; result.innerHTML = ""; return; }
      let body, target = "ollama";
      if (q1) body = "Run a local model with Ollama or LM Studio, or mlx / vLLM on another machine on your network. Pick one that supports tool calling.";
      else if (q3) { body = "Use the provider you already pay for: OpenAI, OpenCode or any OpenAI-compatible endpoint with your key. Page content goes to that provider only."; target = "openai"; }
      else body = "Either works: a free local model with Ollama or LM Studio, or a pay-as-you-go hosted provider such as OpenCode.";
      if (q2 === true) body += " Choose a model with vision support so it can read screenshots.";
      else if (q2 === false) body += " A text-only model works too. Vicaro reads the page as text instead.";
      body += " A larger context window helps on long pages.";
      result.innerHTML = "";
      const p = el("<p></p>");
      p.textContent = body;
      const b = el(`<button type="button" class="fq-go">Show the data path</button>`);
      b.addEventListener("click", () => showMe("#models", `input[name="endpoint"][value="${target}"]`));
      result.append(p, b);
      result.hidden = false;
      scrollThread();
    }
    return w;
  }

  const WIDGETS = {
    "faq-compat": wCompat,
    "faq-safe": () => actWidget([["Show me in the autonomy dial", "#autonomy", 'input[name="automode"][value="readonly"]']]),
    "faq-servers": () => actWidget([
      ["Show the data path: local model", "#models", 'input[name="endpoint"][value="ollama"]'],
      ["…with a hosted model", "#models", 'input[name="endpoint"][value="openai"]'],
    ]),
    "faq-model": wPicker,
  };

  /* -- deep links -- */
  function fromHash() {
    const it = byId[location.hash.slice(1)];
    if (!it) return;
    it.node.open = true;
    const sec = $("#faq");
    if (sec) sec.scrollIntoView({ behavior: reduceMotion ? "instant" : "smooth" });
    ask(it.id);
  }
  window.addEventListener("hashchange", fromHash);

  renderHome();
  if (location.hash.length > 1) fromHash();
})();
