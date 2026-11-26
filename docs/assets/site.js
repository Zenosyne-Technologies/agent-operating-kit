/* site.js - the Marvin docs site's behaviour. Vanilla JS, no dependencies, loaded with `defer` on every page.
   Each feature is one named init function handed to marvinReady(); a feature whose markup is absent from the page
   returns without doing anything. AOS-306 adds the old-anchor redirect and the persona inspector below. */
"use strict";

function marvinReady(fn) {
  var run = function () {
    try { fn(); } catch (err) { if (window.console) { window.console.error(err); } }
  };
  if (document.readyState === "loading") { document.addEventListener("DOMContentLoaded", run); } else { run(); }
}

/* The site root relative to this page ("" at the root, "../" one level down), read from the stylesheet link the
   shell writes, so a script never has to know where the site is mounted. */
function rootPrefix() {
  var l = document.querySelector('link[rel="stylesheet"][href$="assets/site.css"]');
  return l ? l.getAttribute("href").slice(0, -"assets/site.css".length) : "";
}

/* ---- scroll-spy (AOS-302): highlight the .sidebar link whose target heading on this page is in view.
   Only links that point at an element of the current page (a #fragment, same path) take part; the page links the
   build writes are left alone. The active link gets .is-active (styled in site.css). */
marvinReady(function initScrollSpy() {
  var sidebar = document.querySelector(".sidebar");
  if (!sidebar || !("IntersectionObserver" in window)) { return; }
  var here = location.pathname.replace(/index\.html$/, "");
  var links = [];
  var targets = [];
  Array.prototype.forEach.call(sidebar.querySelectorAll("a[href*='#']"), function (a) {
    var url = new URL(a.getAttribute("href"), location.href);
    if (url.pathname.replace(/index\.html$/, "") !== here || url.hash.length < 2) { return; }
    var el = document.getElementById(decodeURIComponent(url.hash.slice(1)));
    if (!el) { return; }
    links.push(a);
    targets.push(el);
  });
  if (!targets.length) { return; }
  var visible = new Set();
  var current = -1;
  function mark(i) {
    if (i === current) { return; }
    current = i;
    links.forEach(function (a, k) { a.classList.toggle("is-active", k === i); });
  }
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      var i = targets.indexOf(e.target);
      if (e.isIntersecting) { visible.add(i); } else { visible.delete(i); }
    });
    if (visible.size) {
      mark(Math.min.apply(null, Array.from(visible)));
      return;
    }
    // nothing in the band: keep the last heading that has scrolled above it
    var last = -1;
    targets.forEach(function (el, k) { if (el.getBoundingClientRect().top < window.innerHeight * 0.25) { last = k; } });
    if (last >= 0) { mark(last); }
  }, { rootMargin: "-72px 0px -65% 0px", threshold: 0 });
  targets.forEach(function (el) { io.observe(el); });
});

/* ---- old-anchor redirect (AOS-306): the site root used to be one page, the "Marvin Orchestration Map". Its section
   anchors now live on the concept pages, under the same ids, so an old link like <root>/#ladder lands on the right
   section. Runs on the root index only; every other page keeps its own fragments. */
marvinReady(function initOldAnchors() {
  var OLD_ANCHORS = {
    "#ladder": "concepts/escalation.html",
    "#stair": "concepts/escalation.html",
    "#signals": "concepts/escalation.html",
    "#lanes": "concepts/sizing.html",
    "#around": "concepts/around-the-loop.html",
    "#insp": "concepts/lifecycle.html"
  };
  var to = OLD_ANCHORS.hasOwnProperty(location.hash) ? OLD_ANCHORS[location.hash] : null;
  if (!to || rootPrefix() !== "" || !/(^|\/)(index\.html)?$/.test(location.pathname)) { return; }
  location.replace(to + location.hash);
});

/* ---- persona inspector (AOS-306). A page that carries the generator's #marvin-data block (<!-- data: profiles -->)
   gets: every [data-fill] inside a persona node filled with that persona's model and effort ("model"), or its tier's
   model under the other profiles where it differs ("alt"); and the #insp panel, which explains whichever persona is
   selected. Personas are [data-p] elements: chip buttons, or SVG nodes with role="button" and tabindex="0" (Enter
   and Space select them). Models, efforts and the persona list come only from the data block; NOTES holds the
   hand-written explanations, keyed by persona (scripts/test-build-docs.sh keeps its keys equal to agents/*.md plus
   marvin), and `rules` names the persona's guide on the Reference page. */
marvinReady(function initInspector() {
  var src = document.getElementById("marvin-data");
  if (!src) { return; }
  var D = JSON.parse(src.textContent);
  var TIER = { orch: "Orchestrator", heavy: "Heavy worker", small: "Small worker", micro: "Micro", frontier: "Frontier" };
  var NOTES = {
    "marvin": { rules: "",
      does: "Plans, decomposes, briefs, sequences and verifies. Reads to act, never to learn, and never bulk-implements.",
      when: "The main session, from install until it leaves the project. Raises effort to high when a task needs it.",
      limit: "No sub-agent runs above the heavy tier's model by default. A profile may put the orchestrator a tier above the heavy worker." },
    "developer": { rules: "briefing",
      does: "Builds one briefed size:m+ task to its DoD. On a decomposed size:m it builds the design-bearing core. Also cross-cutting debugging.",
      when: "The task is size:m or larger and the brief is complete.",
      limit: "Never validates its own work. Effort pinned at medium, the ladder's base rung." },
    "developer-small": { rules: "briefing",
      does: "Builds size:s tasks that need judgement, QA sweeps and peripheral pieces. Also runs the brief falsifier, the planning survey and reader summaries.",
      when: "A size:s task, a size:m peripheral piece, or a correction that is not fully specified.",
      limit: "As falsifier or survey it writes no code and commits nothing." },
    "developer-micro": { rules: "briefing",
      does: "Builds one fully specified task: every file named, nothing left to decide.",
      when: "A size:s task, peripheral piece or fix list that passes the fully-specified test in briefing.md.",
      limit: "If it gets stuck, the task tiers up to developer-small. Effort pinned at high." },
    "ponytail": { rules: "ponytail",
      does: "Zero-discretion size:xs work: every tracker call, release mechanics, index rows, label backfills and exact-lookup reads.",
      when: "Whenever the content is already decided, so tracker payloads stay out of Marvin's context.",
      limit: "May prepare a tag message. Never tags and never publishes a release." },
    "researcher": { rules: "planning-research",
      does: "Synthesis stage of plan validation and solution research for size:l and size:xl, working from a survey's citations. Also the read-only RETHINK pass.",
      when: "size:l/xl planning, or a build whose failure pattern says the approach is wrong.",
      limit: "Changes no code." },
    "validator-completion": { rules: "validation-agent",
      does: "Fresh business-analyst persona that adversarially tries to falsify \"done\" against the DoD.",
      when: "After every build, before the security validator.",
      limit: "Never the builder. A FAIL returns the task to its build tier and counts as one failed round." },
    "validator-security": { rules: "validation-agent",
      does: "Reviews the completed changes for security regressions.",
      when: "Only after the completion validator passes.",
      limit: "Never the builder. A FAIL returns the task to its build tier." },
    "validator-visual": { rules: "visual-validation",
      does: "Reviews a finished UI task's surfaces against the generic design checklist, with screenshots where it can.",
      when: "UI tasks only, after both gating validators pass.",
      limit: "Advisory. It never gates or bounces the task." },
    "documenter": { rules: "documentation-agent",
      does: "Documents one completed task and grows the product handbooks.",
      when: "Only after BOTH validators pass.",
      limit: "A mandatory gate: the tracker issue cannot close before documentation lands." },
    "codex": { rules: "codex",
      does: "Forwarder that runs one Codex lane (plan, review, security, design, diagnose, build, build-micro) and maps its JSON onto the final-message contract.",
      when: "A Codex lane is chosen under the handover consent switch.",
      limit: "Adds no judgement of its own. Falls back when Codex is unavailable." },
    "escalation-small-xhigh": { rules: "escalation-ladder",
      does: "The small tier's only rung: the same model with more effort.",
      when: "A developer-small build is stuck, including one that tiered up from micro.",
      limit: "Keeps the task's size label. Never self-escalates." },
    "escalation-high": { rules: "escalation-ladder",
      does: "First heavy-tier rung: the heavy worker's model at more effort.",
      when: "A stuck small-tier build climbs here. A stuck developer build enters the ladder here.",
      limit: "Receives the brief, the DoD and every prior attempt's findings." },
    "escalation-xhigh": { rules: "escalation-ladder",
      does: "Second heavy-tier rung.",
      when: "Round signals say climb at escalation-high.",
      limit: "Never self-escalates." },
    "escalation-max": { rules: "escalation-ladder",
      does: "The max-gate rung on the heavy tier's model.",
      when: "You choose max, give no answer, pick neither option, or the session is unattended. The outcome is recorded.",
      limit: "Last rung. A further climb signal stops the ladder." },
    "escalation-frontier": { rules: "escalation-ladder",
      does: "The opt-in frontier rung, one model tier above the heavy worker. Exists only in a profile that declares a frontier tier.",
      when: "Only when you explicitly choose the frontier swap for this task at the max gate.",
      limit: "Never reached by default or by silence." }
  };
  var own = function (o, k) { return Object.prototype.hasOwnProperty.call(o, k); };
  function cell(profile, tier) { var p = D.profiles[profile]; return p && own(p, tier) ? p[tier] : null; }
  function persona(id) {
    if (id === "marvin") {
      var o = cell(D["default"], "orch") || {};
      return { tier: "orch", model: o.model || "", effort: o.effort || "", description: "" };
    }
    return own(D.personas, id) ? D.personas[id] : null;
  }
  function modelLine(p) { return [p.model, p.effort].filter(Boolean).join(" · "); }
  function altLine(p) {
    var out = [];
    Object.keys(D.profiles).sort().forEach(function (name) {
      if (name === D["default"]) { return; }
      var c = cell(name, p.tier);
      var m = c && c.model ? c.model : "none";
      if (m !== p.model) { out.push(name + " profile: " + m); }
    });
    return out.join(" · ");
  }

  Array.prototype.forEach.call(document.querySelectorAll("[data-fill]"), function (el) {
    var host = el.closest("[data-p]");
    var p = host ? persona(host.getAttribute("data-p")) : null;
    if (!p) { return; }
    var v = el.getAttribute("data-fill") === "alt" ? altLine(p) : modelLine(p);
    el.textContent = v && el.hasAttribute("data-sep") ? " · " + v : v;
  });

  var insp = document.getElementById("insp");
  if (!insp) { return; }
  var root = rootPrefix();
  function make(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) { n.className = cls; }
    if (text) { n.textContent = text; }
    return n;
  }
  function field(cols, key, value, node) {
    if (!value && !node) { return; }
    var box = make("div");
    box.appendChild(make("span", "k", key));
    var v = node || make("span", "v", value);
    box.appendChild(v);
    cols.appendChild(box);
  }
  function select(id) {
    var p = persona(id);
    if (!p) { return; }
    var n = own(NOTES, id) ? NOTES[id] : {};
    var head = make("div", "ih");
    head.appendChild(make("span", "dot"));
    head.appendChild(make("span", "in", id === "marvin" ? "Marvin" : "marvin:" + id));
    head.appendChild(make("span", "pill", TIER[p.tier] || p.tier));
    var alt = altLine(p);
    head.appendChild(make("span", "im", modelLine(p) + (alt ? " (" + alt + ")" : "")));
    var cols = make("div", "cols");
    field(cols, "Does", n.does || p.description);
    field(cols, "Dispatched when", n.when);
    field(cols, "Limits", n.limit);
    var link = make("a", "v mono", n.rules ? ".marvin/agents/" + n.rules + ".md" : ".marvin/CLAUDE.marvin.md and its guides");
    link.href = root + "reference.html" + (n.rules ? "#" + n.rules : "");
    field(cols, "Rules", "", link);
    insp.setAttribute("data-tier", p.tier);
    insp.textContent = "";
    insp.appendChild(head);
    insp.appendChild(cols);
    Array.prototype.forEach.call(document.querySelectorAll("main [data-p]"), function (el) {
      var on = el.getAttribute("data-p") === id;
      el.classList.toggle("sel", on);
      if (el.tagName.toLowerCase() === "button" || el.getAttribute("role") === "button") { el.setAttribute("aria-pressed", on ? "true" : "false"); }
    });
  }
  document.addEventListener("click", function (e) {
    var el = e.target.closest ? e.target.closest("main [data-p]") : null;
    if (el) { select(el.getAttribute("data-p")); }
  });
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Enter" && e.key !== " ") { return; }
    var el = e.target.closest ? e.target.closest('svg [data-p][role="button"]') : null;
    if (el) { e.preventDefault(); select(el.getAttribute("data-p")); }
  });
  var first = document.querySelector("main [data-p]");
  if (first) { select(first.getAttribute("data-p")); }
});
