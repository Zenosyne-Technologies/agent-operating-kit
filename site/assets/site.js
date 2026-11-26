/* site.js - the Marvin docs site's behaviour. Vanilla JS, no dependencies, loaded with `defer` on every page.
   Each feature is one named init function handed to marvinReady(); a feature whose markup is absent from the page
   returns without doing anything. Later features (the persona inspector and the old-anchor redirect, AOS-306) are
   appended below as further marvinReady(function initX() { ... }) blocks. */
"use strict";

function marvinReady(fn) {
  var run = function () {
    try { fn(); } catch (err) { if (window.console) { window.console.error(err); } }
  };
  if (document.readyState === "loading") { document.addEventListener("DOMContentLoaded", run); } else { run(); }
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
