/* Vicaro homepage: run replay, autonomy dial, model data-flow, site tabs.
   Progressive enhancement — without this file the page shows final states. */
(() => {
  "use strict";
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  /* ================================================================
     HERO RUN REPLAY
     ================================================================ */
  const stream = $("#replay-stream");
  const pageBox = $("#replay-page");
  const tabTitle = $("#replay-tabtitle");
  const statusEl = $("#replay-status");
  const statsLine = $("#replay-statsline");
  const statsEl = $("#replay-stats");
  const modeEl = $("#replay-mode");
  const frame = $("#replay-frame");
  const pauseBtn = $("#replay-pause");
  const stepBtn = $("#replay-step");
  const tabs = $$(".replay-tab");

  if (stream && pageBox) {

    let runToken = 0;
    let userPaused = false;
    let offscreen = false;
    let beatIndex = 0;
    let pendingResolve = null;   // resolve() for an open approval card
    const isPaused = () => userPaused || offscreen;

    const push = (html) => {
      const tpl = document.createElement("template");
      tpl.innerHTML = html.trim();
      const node = tpl.content.firstElementChild;
      stream.appendChild(node);
      stream.scrollTop = stream.scrollHeight;
      return node;
    };

    const setStatus = (state) => {
      statusEl.className = "vp-status" + (state === "run" ? " run" : state === "need" ? " need" : "");
      statusEl.innerHTML = "<i></i>" + (state === "run" ? "Working" : state === "need" ? "Needs you" : "Done");
    };
    const setStats = (text, running) => {
      statsEl.textContent = text;
      statsLine.classList.toggle("run", !!running);
    };

    const toolChip = (name, result, opts = {}) =>
      `<div class="vp-tool${opts.busy ? " busy" : ""}"><span class="vp-tn">${name}</span>` +
      (opts.tag ? `<span class="vp-tag">${opts.tag}</span>` : "") +
      `<span class="vp-tr">${result}</span></div>`;

    const bubble = (text) => `<div class="vp-user"><p>${text}</p></div>`;
    const label = () => `<p class="vp-label"><b>VICARO</b> · NOW</p>`;
    const folds = (thoughts, tWords, actions, trace, detail) =>
      `<details class="vp-fold"><summary>THOUGHTS · ${tWords} WORDS</summary><div class="vp-fold-in">${thoughts}</div></details>` +
      `<details class="vp-fold"><summary>TRACE · ${actions} ACTIONS · ${trace}</summary><div class="vp-fold-in">${detail || ""}</div></details>`;

    function makeCtx(token) {
      return {
        cancelled: () => token !== runToken,
        push, toolChip, setStats, setStatus,
        // Approval card: resolves "allow" | "deny". In motion mode it
        // auto-allows after ~4s; the visitor can click Allow or Deny first.
        // When ctx.instant is set (static/reduced final-state render) it
        // resolves "allow" immediately without rendering a card.
        confirm({ title, risk, cmd, target, note }) {
          if (this.instant) return Promise.resolve("allow");
          return new Promise((resolve) => {
            const card = push(
              `<div class="vp-confirm">
                <div class="vp-c-head">${title}${risk ? `<span class="vp-c-risk">${risk}</span>` : ""}</div>
                ${cmd ? `<code class="vp-c-cmd">${cmd}</code>` : ""}
                ${target ? `<p class="vp-c-target">${target}</p>` : ""}
                ${note ? `<p class="vp-c-note">${note}</p>` : ""}
                <div class="vp-c-actions">
                  <button type="button" class="vp-allow">Allow</button>
                  <button type="button" class="vp-deny">Deny</button>
                  <span class="vp-c-timer" hidden></span>
                </div>
              </div>`
            );
            setStatus("need");
            let done = false;
            const finish = (res) => {
              if (done) return;
              done = true;
              pendingResolve = null;
              card.remove();
              resolve(res);
            };
            pendingResolve = () => finish("allow");
            $(".vp-allow", card).addEventListener("click", () => finish("allow"));
            $(".vp-deny", card).addEventListener("click", () => finish("deny"));
            if (!reduceMotion) {
              const timer = $(".vp-c-timer", card);
              timer.hidden = false;
              let left = 4;
              timer.textContent = `auto-Allow in ${left}s`;
              const iv = setInterval(() => {
                if (done || token !== runToken) { clearInterval(iv); return; }
                left -= 1;
                if (left <= 0) { clearInterval(iv); finish("allow"); return; }
                timer.textContent = `auto-Allow in ${left}s`;
              }, 1000);
            }
          });
        }
      };
    }

    /* ---- page mocks ------------------------------------------------ */
    const row = (who, sub, news) =>
      `<li class="pm-row${news ? " news" : ""}"><span class="pm-avatar"></span><span class="pm-who"><b>${who}</b><span>${sub}</span></span>${news ? '<span class="pm-tag">Newsletter</span>' : ""}</li>`;

    const PAGES = {
      inbox() {
        return `<div class="pm-head"><h3 class="pm-title">Inbox</h3><span class="pm-sub">214 conversations</span></div>
        <ul class="pm-rows">
          ${row("Maya from Ops", "Re: Thursday deploy window")}
          ${row("The Product Weekly", "Issue 88: onboarding that sticks", true)}
          ${row("Jordan Lee", "Contract draft — second pass")}
          ${row("DevTools Digest", "What's new in Chrome 132", true)}
          ${row("Bank alerts", "Your statement is ready")}
          ${row("Founders' Roundup", "October: pricing experiments", true)}
          ${row("Priya Nair", "Lunch next week?")}
          ${row("Cloud Status", "Daily digest: all systems normal", true)}
          ${row("Calendar", "Invite: design review, Tue 2pm")}
        </ul><span class="pm-fade" aria-hidden="true"></span>`;
      },
      collect() {
        const card = (name, spec, price) =>
          `<div class="pm-card"><div class="pm-img"></div><b>${name}</b><span>${spec}</span><br><span class="pm-price">${price}</span></div>`;
        return `<div class="pm-head"><h3 class="pm-title">Apartments for rent</h3><span class="pm-sub">46 results</span></div>
        <div class="pm-cards">
          ${card("Maple Court 4B", "2 bd · 1 ba · 820 sqft", "$2,650/mo")}
          ${card("The Rowan, Unit 12", "2 bd · 2 ba · 940 sqft", "$2,980/mo")}
          ${card("Cedar Lofts 2J", "2 bd · 1 ba · loft", "$3,400/mo")}
          ${card("8th & Pine Studio", "Studio · 480 sqft", "$1,875/mo")}
        </div>
        <div class="pm-pager"><b id="pm-page">Page 1 of 4</b><span>‹ 1 2 3 4 ›</span></div>
        <span class="pm-fade" aria-hidden="true"></span>`;
      },
      fill() {
        const field = (label, ph, wide) =>
          `<div class="pm-field${wide ? " wide" : ""}"><label>${label}</label><div class="pm-input" data-ph="${ph}"></div></div>`;
        return `<div class="pm-head"><h3 class="pm-title">Job application — Platform Engineer</h3><span class="pm-sub">12 fields · 3 required</span></div>
        <div class="pm-form">
          ${field("Full name *", "Your name")}
          ${field("Email *", "you@example.com")}
          ${field("Phone", "(555) 000-0000")}
          ${field("LinkedIn", "linkedin.com/in/…")}
          ${field("Most recent role *", "Job title")}
          ${field("Years of experience", "e.g. 6")}
          ${field("Cover note", "Why this role?", true)}
        </div>
        <div class="pm-submit"><span class="pm-btn">Submit application</span><span class="pm-sub">autofill from file</span></div>
        <span class="pm-fade" aria-hidden="true"></span>`;
      }
    };

    /* ---- scenarios ------------------------------------------------- */
    const SCENARIOS = [
      {
        key: "inbox", title: "Inbox — 214 conversations", mode: "Ask first",
        page: PAGES.inbox,
        beats: [
          (ctx) => { push(bubble("Archive newsletters older than 30 days.")); setStatus("run"); setStats("52 tok/s · prefill 388 tok/s · ctx 4%", true); },
          (ctx) => { push(label()); push(folds("Newsletters older than 30 days: select them, then archive. The Archive control is in the toolbar.", 21, 4, "2.1S", "rows_list · rows_select · click_named · read_state")); },
          (ctx) => push(toolChip("rows_list", "214 rows")),
          (ctx) => { push(toolChip("rows_select", "37 newsletters selected")); $$(".pm-row.news", pageBox).forEach((r) => r.classList.add("sel")); setStats("61 tok/s · ctx 5%", true); },
          (ctx) => push(toolChip("click_named", "Archive")),
          async (ctx) => {
            const res = await ctx.confirm({
              title: "Archive 37 conversations?", risk: "WRITE",
              cmd: 'click_named { name: "Archive" }', target: "Toolbar button · Archive"
            });
            if (ctx.cancelled()) return;
            if (res === "allow") {
              $$(".pm-row.news", pageBox).forEach((r) => r.classList.add("gone"));
              $(".pm-rows", pageBox).insertAdjacentHTML("afterend", '<p class="pm-toast">37 conversations archived</p>');
              push(`<p class="vp-receipt">Archived 37 · verified · 4 actions · 2.1s</p>`);
              push(`<div class="vp-answer"><p>Done. I archived <b>37 newsletter threads</b> older than 30 days. Everything else in the inbox is untouched.</p></div>`);
            } else {
              $$(".pm-row.news", pageBox).forEach((r) => r.classList.remove("sel"));
              push(`<p class="vp-note">You declined. Nothing changed.</p>`);
              push(`<div class="vp-answer"><p>Understood — I left the inbox as it was. Nothing was archived.</p></div>`);
            }
            setStatus("done"); setStats("48 tok/s · prefill 410 tok/s · ctx 6%", false);
          }
        ]
      },
      {
        key: "collect", title: "Apartments for rent — search", mode: "Read only",
        page: PAGES.collect,
        beats: [
          (ctx) => { push(bubble("Collect every 2-bedroom under $3,000 into a table.")); setStatus("run"); setStats("44 tok/s · prefill 402 tok/s · ctx 3%", true); },
          (ctx) => { push(label()); push(`<p class="vp-note ok">Read only is enough for this one.</p>`); push(folds("Walk all four pages, keep 2-bedrooms under $3,000, return a table. No page changes needed.", 18, 6, "3.8S", "collect_records ×4 · read_state")); },
          async (ctx) => {
            const chip = push(toolChip("collect_records", "walking pages", { busy: true }));
            const pager = $("#pm-page", pageBox);
            for (const p of [2, 3, 4]) {
              await sleep(reduceMotion ? 0 : 550);
              if (ctx.cancelled()) return;
              if (pager) pager.textContent = `Page ${p} of 4`;
            }
            chip.classList.remove("busy");
            $(".vp-tr", chip).textContent = "4 pages · 46 records · coverage complete";
          },
          (ctx) => {
            push(`<table class="vp-table"><thead><tr><th>Listing</th><th>Beds</th><th>Rent</th></tr></thead><tbody>
              <tr><td>Maple Court 4B</td><td>2</td><td>$2,650</td></tr>
              <tr><td>The Rowan, Unit 12</td><td>2</td><td>$2,980</td></tr>
              <tr><td>Juniper House 7A</td><td>2</td><td>$2,790</td></tr>
              <tr class="more"><td colspan="3">+43 more</td></tr></tbody></table>`);
            push(`<p class="vp-receipt">Collected 46 · 0 page changes · read only</p>`);
            push(`<div class="vp-answer"><p>Collected <b>46 two-bedroom listings under $3,000</b> across 4 pages. 12 match exactly; the table is above.</p></div>`);
            setStatus("done"); setStats("44 tok/s · prefill 402 tok/s · ctx 7%", false);
          }
        ]
      },
      {
        key: "fill", title: "Job application — Platform Engineer", mode: "Full auto",
        page: PAGES.fill,
        beats: [
          (ctx) => { push(bubble("Fill this application from ~/Documents/resume.md.")); setStatus("run"); setStats("57 tok/s · prefill 396 tok/s · ctx 8%", true); },
          (ctx) => { push(label()); push(folds("Read the resume, map it onto the form, fill everything, then stop before submit.", 16, 4, "3.4S", "fs_read · inspect_form · fill_form")); },
          (ctx) => push(toolChip("fs_read", "~/Documents/resume.md · 4.2 KB", { tag: "Local files · opt-in" })),
          (ctx) => push(toolChip("inspect_form", "12 fields · 3 required")),
          (ctx) => {
            push(toolChip("fill_form", "12 of 12 filled · preflight ok"));
            const values = ["Maya Reyes", "maya.reyes@example.com", "(415) 555-0119", "linkedin.com/in/mayareyes", "Platform Engineer, Brightline", "6", "I build internal platforms that make other engineers faster — your posting is close to what I do now."];
            $$(".pm-field", pageBox).forEach((f, i) => { f.classList.add("filled"); const inp = $(".pm-input", f); if (inp) inp.textContent = values[i] || ""; });
            setStats("63 tok/s · ctx 9%", true);
          },
          async (ctx) => {
            const res = await ctx.confirm({
              title: "Submit application?", risk: "WRITE",
              cmd: 'click_named { name: "Submit application" }',
              target: "Form footer · Submit application",
              note: "Submit buttons get an extra check, even in Full auto."
            });
            if (ctx.cancelled()) return;
            if (res === "allow") {
              $(".pm-submit", pageBox).insertAdjacentHTML("beforeend", '<p class="pm-toast" style="margin:0">Application submitted</p>');
              push(`<p class="vp-receipt">Submitted · verified · 4 actions · 3.4s</p>`);
              push(`<div class="vp-answer"><p>Submitted. All 12 fields were filled from <b>~/Documents/resume.md</b> and the confirmation page appeared.</p></div>`);
            } else {
              push(`<p class="vp-note">You declined. The form is filled but not submitted.</p>`);
              push(`<div class="vp-answer"><p>Stopped before submit — the filled form is still open for you to review.</p></div>`);
            }
            setStatus("done"); setStats("57 tok/s · prefill 396 tok/s · ctx 9%", false);
          }
        ]
      }
    ];

    /* ---- runner ---------------------------------------------------- */
    let beatTimer = null;
    const buildChrome = (scn, i) => {
      tabTitle.textContent = scn.title;
      modeEl.textContent = scn.mode;
      pageBox.innerHTML = scn.page();
      stream.innerHTML = "";
      setStatus("run");
      tabs.forEach((t, j) => {
        t.setAttribute("aria-selected", j === i ? "true" : "false");
        t.tabIndex = j === i ? 0 : -1;
      });
      frame.setAttribute("aria-labelledby", tabs[i].id);
    };

    const nextScenario = () => startScenario((current + 1) % SCENARIOS.length);
    let current = 0;

    async function runBeats(ctx, scn) {
      const token = runToken;
      while (beatIndex < scn.beats.length) {
        await waitWhilePaused(token);
        if (ctx.cancelled()) return;
        const beat = scn.beats[beatIndex++];
        await beat(ctx);
        if (ctx.cancelled()) return;
        await waitWhilePaused(token);
        if (ctx.cancelled()) return;
        await sleep(reduceMotion ? 0 : 850);
      }
      // finished — hold, then auto-advance
      beatTimer = setTimeout(() => { if (!ctx.cancelled()) nextScenario(); }, 4600);
    }

    const waitWhilePaused = async (token) => {
      while (isPaused() && token === runToken) await sleep(180);
    };

    function startScenario(i) {
      current = i;
      runToken += 1;
      beatIndex = 0;
      stepQueue = null;
      if (pendingResolve) pendingResolve();
      clearTimeout(beatTimer);
      const scn = SCENARIOS[i];
      buildChrome(scn, i);
      if (reduceMotion) {
        // Static final state first; the Step button walks the replay.
        const ctx = makeCtx(runToken);
        ctx.instant = true;
        (async () => {
          for (const beat of scn.beats) {
            if (ctx.cancelled()) return;
            await beat(ctx);
          }
        })();
      } else {
        const ctx = makeCtx(runToken);
        runBeats(ctx, scn);
      }
    }

    // Step button (reduced-motion manual control): restart and walk one beat
    // per press; an open approval resolves as Allow.
    let stepQueue = null;
    const stepMode = () => {
      if (pendingResolve) { pendingResolve(); return; }
      const scn = SCENARIOS[current];
      if (!stepQueue || stepQueue.done) {
        runToken += 1;
        stepQueue = { i: 0, done: false, ctx: makeCtx(runToken) };
        buildChrome(scn, current);
        setStatus("run");
      }
      if (stepQueue.i >= scn.beats.length) { stepQueue.done = true; return; }
      const beat = scn.beats[stepQueue.i++];
      Promise.resolve(beat(stepQueue.ctx)).then(() => {
        if (stepQueue.i >= scn.beats.length) stepQueue.done = true;
      });
    };

    tabs.forEach((tab, i) => {
      tab.addEventListener("click", () => { userPaused = false; setPauseUI(); startScenario(i); });
      tab.addEventListener("keydown", (e) => {
        let j = null;
        if (e.key === "ArrowRight" || e.key === "ArrowDown") j = (i + 1) % tabs.length;
        if (e.key === "ArrowLeft" || e.key === "ArrowUp") j = (i - 1 + tabs.length) % tabs.length;
        if (e.key === "Home") j = 0;
        if (e.key === "End") j = tabs.length - 1;
        if (j !== null) { e.preventDefault(); tabs[j].focus(); tabs[j].click(); }
      });
    });

    const setPauseUI = () => {
      pauseBtn.setAttribute("aria-pressed", String(userPaused));
      $("span", pauseBtn).textContent = userPaused ? "Play" : "Pause";
      pauseBtn.querySelector("svg path").setAttribute("d", userPaused ? "M2 1l7 4-7 4z" : "M2 1h2v8H2zM6 1h2v8H6z");
    };
    pauseBtn.addEventListener("click", () => { userPaused = !userPaused; setPauseUI(); });
    stepBtn.addEventListener("click", stepMode);

    if ("IntersectionObserver" in window) {
      new IntersectionObserver((entries) => {
        offscreen = !entries[0].isIntersecting;
      }, { threshold: 0.08 }).observe($(".hero-visual"));
    }

    if (reduceMotion) { stepBtn.hidden = false; } else { pauseBtn.hidden = false; }
    startScenario(0);
  }

  /* ================================================================
     HEADER — dark while it sits over the dark hero band
     ================================================================ */
  const siteHeader = $(".site-header.over-dark");
  const heroBand = $(".hero");
  if (siteHeader && heroBand && "IntersectionObserver" in window) {
    new IntersectionObserver((entries) => {
      siteHeader.classList.toggle("over-dark", entries[0].isIntersecting);
    }, { rootMargin: "-78px 0px 0px 0px", threshold: 0 }).observe(heroBand);
  }

  /* ================================================================
     AUTONOMY DIAL
     ================================================================ */
  const dial = $("#mode-dial");
  if (dial) {
    const hintEl = $("#mode-hint");
    const noteEl = $("#mode-note");
    const badges = $$("#mode-task .mt-badge");
    const OUT = { run: "Runs", ask: "Asks", block: "Blocked" };
    const MODES = {
      readonly: { hint: "I can read and search pages, but every action that changes one is denied.", out: ["run", "block", "block", "block"], note: "" },
      askfirst: { hint: "I pause before anything that changes a page — clicks, typing, navigation.", out: ["run", "ask", "ask", "ask"], note: "" },
      light: { hint: "Filling, selecting and scrolling run without a prompt. Clicks and navigation still ask.", out: ["run", "run", "ask", "ask"], note: "" },
      full: { hint: "Page actions in scope run without a prompt. Code execution, coordinate clicks and uploads still ask. Use Super to remove those stops.", out: ["run", "run", "run", "ask"], note: "Pay, Delete, Send and Submit buttons get an extra check." },
      super: { hint: "Everything in scope runs, and wider scope is permitted. Save this for unattended work you trust.", out: ["run", "run", "run", "run"], note: "", warn: true }
    };
    dial.addEventListener("change", (e) => {
      const m = MODES[e.target.value];
      if (!m) return;
      hintEl.textContent = m.hint;
      hintEl.classList.toggle("warn", !!m.warn);
      noteEl.textContent = m.note;
      badges.forEach((b, i) => {
        const o = m.out[i];
        if (b.dataset.state === o) return;
        b.dataset.state = o;
        b.textContent = OUT[o];
        b.className = "mt-badge " + o;
        b.classList.remove("flip");
        void b.offsetWidth;
        b.classList.add("flip");
      });
    });
    badges.forEach((b) => { b.dataset.state = b.classList.contains("ask") ? "ask" : b.classList.contains("block") ? "block" : "run"; });
  }

  /* ================================================================
     MODEL DATA-FLOW
     ================================================================ */
  const flow = $("#model-flow");
  if (flow) {
    const epNode = $("#flow-ep");
    const epName = $("#flow-ep-name");
    const epSub = $("#flow-ep-sub");
    const lineEl = $("#model-line");
    const xOut = $("#fl-x-out");
    const slots = { local: $("#ep-local"), lan: $("#ep-lan"), out: $("#ep-out") };
    const EP = {
      ollama: { scope: "local", name: "Ollama", sub: "localhost · OpenAI-compatible", line: "A local model keeps page content and chat on this Mac." },
      lmstudio: { scope: "local", name: "LM Studio", sub: "localhost · OpenAI-compatible", line: "A local model keeps page content and chat on this Mac." },
      lan: { scope: "lan", name: "mlx / vLLM", sub: "another machine on your network", line: "Page content stays on your network." },
      openai: { scope: "hosted", name: "OpenAI", sub: "api.openai.com · your key", x: "HTTPS · your key", line: "Page content goes to OpenAI only, under your key. No Vicaro relay." },
      opencode: { scope: "hosted", name: "OpenCode", sub: "opencode.ai · your key", x: "HTTPS · your key", line: "Page content goes to OpenCode only, under your key. No Vicaro relay." },
      custom: { scope: "custom", name: "Your endpoint", sub: "the URL you enter", x: "HTTPS · your endpoint", line: "Page content goes only to the endpoint you enter." }
    };
    $("#model-sel").addEventListener("change", (e) => {
      const m = EP[e.target.value];
      if (!m) return;
      epName.textContent = m.name;
      epSub.textContent = m.sub;
      lineEl.textContent = m.line;
      xOut.textContent = m.x || "";
      flow.dataset.scope = m.scope;
      const slot = m.scope === "local" ? slots.local : m.scope === "lan" ? slots.lan : slots.out;
      slot.appendChild(epNode);
    });
  }

  /* ================================================================
     WHERE (site-aware suggestions)
     ================================================================ */
  const whereTabs = $$(".where-tab");
  if (whereTabs.length) {
    const select = (tab) => {
      whereTabs.forEach((t) => {
        const on = t === tab;
        t.setAttribute("aria-selected", String(on));
        t.tabIndex = on ? 0 : -1;
        const panel = document.getElementById(t.getAttribute("aria-controls"));
        if (panel) panel.hidden = !on;
      });
    };
    whereTabs.forEach((tab, i) => {
      tab.addEventListener("click", () => select(tab));
      tab.addEventListener("keydown", (e) => {
        let j = null;
        if (e.key === "ArrowRight" || e.key === "ArrowDown") j = (i + 1) % whereTabs.length;
        if (e.key === "ArrowLeft" || e.key === "ArrowUp") j = (i - 1 + whereTabs.length) % whereTabs.length;
        if (e.key === "Home") j = 0;
        if (e.key === "End") j = whereTabs.length - 1;
        if (j !== null) { e.preventDefault(); whereTabs[j].focus(); select(whereTabs[j]); }
      });
    });
  }
})();
