// ConcentrationMaxx Reels filter, layer 3 of 3 (PLAN.md section 6).
// Injected into the Instagram web view at document start. Instagram changes pages
// without loading them, so this watches its history calls and bounces any route to
// Reels or Explore back to the feed. Instagram changes its site often: update this file
// and reels-rules.json together. The two lists below are filled in by the app from
// reels-rules.json, so there is one source for the blocked paths.
(function () {
  'use strict';
  if (window.__cmxReelsFilter) { return; }
  window.__cmxReelsFilter = true;

  var BLOCKED_FIRST = __CMX_BLOCKED_FIRST__;
  var BLOCKED_SECOND = __CMX_BLOCKED_SECOND__;

  function segments(path) {
    return String(path || '/').toLowerCase().split('/').filter(function (part) { return part.length > 0; });
  }

  function isBlockedPath(path) {
    var parts = segments(path);
    if (parts.length > 0 && BLOCKED_FIRST.indexOf(parts[0]) !== -1) { return true; }
    if (parts.length > 1 && BLOCKED_SECOND.indexOf(parts[1]) !== -1) { return true; }
    return false;
  }

  function notify(path) {
    try { window.webkit.messageHandlers.cmxReelsBlocked.postMessage(String(path)); } catch (error) {}
  }

  function bounce() {
    if (isBlockedPath(window.location.pathname)) {
      notify(window.location.pathname);
      window.location.replace('/');
    }
  }

  ['pushState', 'replaceState'].forEach(function (name) {
    var original = window.history[name];
    if (typeof original !== 'function') { return; }
    window.history[name] = function () {
      var result = original.apply(this, arguments);
      window.setTimeout(bounce, 0);
      return result;
    };
  });
  window.addEventListener('popstate', bounce);

  // Stop taps on links to Reels and Explore before Instagram's router sees them.
  document.addEventListener('click', function (event) {
    var target = event.target;
    var link = target && target.closest ? target.closest('a[href]') : null;
    if (!link) { return; }
    var url;
    try { url = new URL(link.getAttribute('href'), window.location.href); } catch (error) { return; }
    if (isBlockedPath(url.pathname)) {
      event.preventDefault();
      event.stopImmediatePropagation();
      notify(url.pathname);
    }
  }, true);

  // Hide the Reels and Explore tabs and links.
  function addStyle() {
    var style = document.createElement('style');
    style.textContent = 'a[href^="/reels"], a[href^="/reel/"], a[href^="/explore"], a[href*="/reels/"] { display: none !important; }';
    (document.head || document.documentElement).appendChild(style);
  }
  if (document.documentElement) { addStyle(); } else { document.addEventListener('DOMContentLoaded', addStyle); }

  // A safety net for anything the hooks above miss.
  window.setInterval(bounce, 1000);
  bounce();
})();
