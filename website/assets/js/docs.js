// Altair docs enhancements: theme toggle, search modal, scrollspy TOC,
// mobile navigation, code copy buttons. Runs after parsing (deferred).

(function () {
  "use strict";

  var rootPrefix = (function () {
    var scripts = document.querySelectorAll('script[src*="assets/js/docs.js"]');
    if (!scripts.length) return "./";
    var src = scripts[scripts.length - 1].getAttribute("src") || "";
    return src.indexOf("assets/js/docs.js") === 0 ? "./" : "../";
  })();

  /* ---------- Theme ---------- */

  var themeToggle = document.getElementById("theme-toggle");
  function currentTheme() {
    return document.documentElement.getAttribute("data-theme") || "light";
  }
  if (themeToggle) {
    themeToggle.addEventListener("click", function () {
      var next = currentTheme() === "dark" ? "light" : "dark";
      document.documentElement.setAttribute("data-theme", next);
      try {
        localStorage.setItem("altair-theme", next);
      } catch (e) { /* private mode */ }
    });
  }

  /* ---------- Mobile navigation ---------- */

  var navToggle = document.getElementById("nav-toggle");
  var navScrim = document.getElementById("nav-scrim");
  function closeNav() {
    document.body.classList.remove("nav-open");
    if (navToggle) navToggle.setAttribute("aria-expanded", "false");
  }
  if (navToggle) {
    navToggle.addEventListener("click", function () {
      var open = document.body.classList.toggle("nav-open");
      navToggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
  }
  if (navScrim) navScrim.addEventListener("click", closeNav);
  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape") {
      closeNav();
      closeSearch();
    }
  });
  document.querySelectorAll(".docs-sidebar a").forEach(function (link) {
    link.addEventListener("click", closeNav);
  });

  /* ---------- Search ---------- */

  var searchModal = document.getElementById("search-modal");
  var searchTrigger = document.getElementById("search-trigger");
  var searchInput = document.getElementById("search-input");
  var searchResults = document.getElementById("search-results");
  var searchIndex = null;
  var activeHit = -1;
  var lastFocused = null;

  function openSearch() {
    if (!searchModal) return;
    lastFocused = document.activeElement;
    searchModal.hidden = false;
    document.body.style.overflow = "hidden";
    loadIndex();
    window.requestAnimationFrame(function () {
      searchInput.value = "";
      renderResults("", true);
      searchInput.focus();
    });
  }

  function closeSearch() {
    if (!searchModal || searchModal.hidden) return;
    searchModal.hidden = true;
    document.body.style.overflow = "";
    if (lastFocused && lastFocused.focus) lastFocused.focus();
  }

  function indexUrl() {
    return rootPrefix + "assets/search-index.json";
  }

  function loadIndex() {
    if (searchIndex) return;
    fetch(indexUrl())
      .then(function (res) { return res.json(); })
      .then(function (data) {
        searchIndex = data;
        renderResults(searchInput.value, true);
      })
      .catch(function () {
        searchIndex = [];
        renderResults(searchInput.value, true);
      });
  }

  function scoreEntry(entry, query) {
    var q = query.toLowerCase();
    var title = entry.title.toLowerCase();
    var excerpt = (entry.excerpt || "").toLowerCase();
    var headings = (entry.headings || []).map(function (h) { return h.text.toLowerCase(); });
    var score = -1;
    if (title.indexOf(q) !== -1) score = 100 - title.indexOf(q);
    for (var i = 0; i < headings.length; i++) {
      if (headings[i].indexOf(q) !== -1) score = Math.max(score, 60 - i);
    }
    if (excerpt.indexOf(q) !== -1) score = Math.max(score, 20);
    return score;
  }

  function highlight(text, query) {
    if (!query) return escapeHtml(text);
    var idx = text.toLowerCase().indexOf(query.toLowerCase());
    if (idx === -1) return escapeHtml(text);
    return (
      escapeHtml(text.slice(0, idx)) +
      "<mark>" + escapeHtml(text.slice(idx, idx + query.length)) + "</mark>" +
      escapeHtml(text.slice(idx + query.length))
    );
  }

  function escapeHtml(text) {
    return String(text)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function hitUrl(entry, heading) {
    var url = rootPrefix + entry.url;
    if (heading) url += "#" + heading.id;
    return url;
  }

  function renderResults(query, resetActive) {
    if (!searchResults) return;
    if (resetActive) activeHit = -1;
    var q = (query || "").trim();
    if (!searchIndex) {
      searchResults.innerHTML = '<div class="search-empty">Loading index...</div>';
      return;
    }
    if (q.length < 2) {
      var popular = searchIndex.slice(0, 6);
      searchResults.innerHTML =
        '<div class="search-group">Browse</div>' +
        popular
          .map(function (entry) {
            return (
              '<a class="search-hit" role="option" href="' + rootPrefix + entry.url + '">' +
              '<div class="hit-title">' + escapeHtml(entry.title) + "</div>" +
              '<div class="hit-path">' + escapeHtml(entry.group) + "</div>" +
              "</a>"
            );
          })
          .join("");
      return;
    }
    var ranked = searchIndex
      .map(function (entry) {
        var bestHeading = null;
        var best = scoreEntry(entry, q);
        (entry.headings || []).forEach(function (h) {
          if (h.text.toLowerCase().indexOf(q.toLowerCase()) !== -1 && best < 70) {
            best = 70;
            bestHeading = h;
          }
        });
        return { entry: entry, score: best, heading: bestHeading };
      })
      .filter(function (r) { return r.score > 0; })
      .sort(function (a, b) { return b.score - a.score; })
      .slice(0, 12);
    if (!ranked.length) {
      searchResults.innerHTML = '<div class="search-empty">No results for "' + escapeHtml(q) + '".</div>';
      return;
    }
    searchResults.innerHTML = ranked
      .map(function (r, i) {
        var excerpt = r.heading ? r.heading.text : r.entry.excerpt;
        return (
          '<a class="search-hit' + (i === activeHit ? " is-active" : "") + '" role="option" href="' + hitUrl(r.entry, r.heading) + '">' +
          '<div class="hit-title">' + highlight(r.entry.title, q) + "</div>" +
          '<div class="hit-excerpt">' + highlight(excerpt || "", q) + "</div>" +
          '<div class="hit-path">' + escapeHtml(r.entry.group) + (r.heading ? " / " + escapeHtml(r.heading.text) : "") + "</div>" +
          "</a>"
        );
      })
      .join("");
  }

  function moveActive(delta) {
    var hits = searchResults.querySelectorAll(".search-hit");
    if (!hits.length) return;
    activeHit = (activeHit + delta + hits.length) % hits.length;
    hits.forEach(function (hit, i) {
      hit.classList.toggle("is-active", i === activeHit);
      if (i === activeHit) hit.scrollIntoView({ block: "nearest" });
    });
  }

  if (searchTrigger) searchTrigger.addEventListener("click", openSearch);
  document.addEventListener("keydown", function (event) {
    var mod = event.ctrlKey || event.metaKey;
    if (mod && event.key.toLowerCase() === "k") {
      event.preventDefault();
      if (searchModal.hidden) openSearch();
      else closeSearch();
    }
    if (event.key === "/" && searchModal.hidden && !/input|textarea|select/i.test(document.activeElement.tagName)) {
      event.preventDefault();
      openSearch();
    }
  });
  if (searchModal) {
    searchModal.querySelectorAll("[data-search-close]").forEach(function (el) {
      el.addEventListener("click", closeSearch);
    });
  }
  if (searchInput) {
    searchInput.addEventListener("input", function () { renderResults(searchInput.value, true); });
    searchInput.addEventListener("keydown", function (event) {
      if (event.key === "ArrowDown") { event.preventDefault(); moveActive(1); }
      else if (event.key === "ArrowUp") { event.preventDefault(); moveActive(-1); }
      else if (event.key === "Enter") {
        var hits = searchResults.querySelectorAll(".search-hit");
        var target = hits[activeHit] || hits[0];
        if (target) window.location.href = target.getAttribute("href");
      }
    });
  }

  /* ---------- Scrollspy TOC + reading progress ---------- */

  var tocLinks = Array.prototype.slice.call(document.querySelectorAll(".docs-toc a"));
  var tocById = {};
  tocLinks.forEach(function (link) {
    var id = link.getAttribute("href").slice(1);
    tocById[id] = link;
  });
  var spySections = Object.keys(tocById)
    .map(function (id) { return document.getElementById(id); })
    .filter(Boolean);

  function updateSpy() {
    if (!spySections.length) return;
    var current = null;
    var threshold = window.scrollY + window.innerHeight * 0.25;
    spySections.forEach(function (section) {
      if (section.offsetTop <= threshold) current = section.id;
    });
    tocLinks.forEach(function (link) {
      link.classList.toggle("is-visible", link.getAttribute("href") === "#" + current);
    });
  }

  var progressBar = document.querySelector(".reading-progress-bar");
  var ticking = false;
  function onScroll() {
    if (progressBar) {
      var docHeight = document.documentElement.scrollHeight - window.innerHeight;
      var scrolled = docHeight > 0 ? (window.scrollY / docHeight) * 100 : 0;
      progressBar.style.width = scrolled + "%";
    }
    updateSpy();
    ticking = false;
  }
  window.addEventListener("scroll", function () {
    if (!ticking) {
      window.requestAnimationFrame(onScroll);
      ticking = true;
    }
  }, { passive: true });
  updateSpy();
  if (progressBar) onScroll();

  /* ---------- Code blocks: copy button + language label ---------- */

  var LANGS = {
    sh: "Shell", shell: "Shell", bash: "Shell",
    crystal: "Crystal", cr: "Crystal", ruby: "Ruby",
    yaml: "YAML", yml: "YAML", json: "JSON", html: "HTML",
    erb: "ERB", powershell: "PowerShell", cmd: "Cmd",
    text: "Text", diff: "Diff", "": "Text"
  };

  function langLabel(className) {
    var match = /(?:^|\s)language-([\w+-]+)/.exec(className || "");
    var lang = match ? match[1].toLowerCase() : "";
    return LANGS[lang] || lang || "Text";
  }

  function legacyCopy(text) {
    return new Promise(function (resolve, reject) {
      var textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.setAttribute("readonly", "");
      textarea.style.position = "absolute";
      textarea.style.left = "-9999px";
      document.body.appendChild(textarea);
      textarea.select();
      try {
        resolve(document.execCommand("copy"));
      } catch (e) {
        reject(e);
      } finally {
        document.body.removeChild(textarea);
      }
    });
  }

  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text).catch(function () {
        return legacyCopy(text);
      });
    }
    return legacyCopy(text);
  }

  function addCopyButton(container, text) {
    var button = document.createElement("button");
    button.type = "button";
    button.className = "code-block__copy";
    button.textContent = "Copy";
    button.setAttribute("aria-label", "Copy code to clipboard");
    button.addEventListener("click", function () {
      copyText(text).then(
        function () {
          button.textContent = "Copied";
          button.classList.add("copied");
          setTimeout(function () {
            button.textContent = "Copy";
            button.classList.remove("copied");
          }, 1600);
        },
        function () {
          button.textContent = "Failed";
          setTimeout(function () {
            button.textContent = "Copy";
          }, 1600);
        }
      );
    });
    container.appendChild(button);
    return button;
  }

  function buildHeader(lang, copyTarget) {
    var header = document.createElement("div");
    header.className = "code-block__header";
    var label = document.createElement("span");
    label.className = "code-block__lang";
    label.textContent = lang;
    header.appendChild(label);
    addCopyButton(header, copyTarget);
    return header;
  }

  // Fenced code blocks: <pre><code class="language-...">...</code></pre>
  document.querySelectorAll("pre").forEach(function (pre) {
    if (pre.closest(".terminal")) return;
    var code = pre.querySelector("code");
    if (!code) return;
    var wrapper = document.createElement("div");
    wrapper.className = "code-block";
    var header = buildHeader(langLabel(code.className), code.textContent);
    pre.parentNode.replaceChild(wrapper, pre);
    wrapper.appendChild(header);
    wrapper.appendChild(pre);
  });

  // Homepage hero one-liner: <div class="copy-box"><code>curl ...</code></div>
  document.querySelectorAll(".copy-box").forEach(function (box) {
    var code = box.querySelector("code");
    if (!code) return;
    addCopyButton(box, code.textContent);
  });

  // Mute the leading `$` in shell blocks so commands read cleanly.
  document.querySelectorAll(".code-block pre code.language-sh, .code-block pre code.language-shell, .code-block pre code.language-bash").forEach(function (code) {
    Array.prototype.slice.call(code.childNodes).forEach(function (node) {
      if (node.nodeType !== 3) return;
      var lines = node.textContent.split("\n");
      var fragment = document.createDocumentFragment();
      lines.forEach(function (line, index) {
        if (index > 0) fragment.appendChild(document.createTextNode("\n"));
        if (line.indexOf("$ ") === 0) {
          var prompt = document.createElement("span");
          prompt.className = "shell-prompt";
          prompt.textContent = "$";
          fragment.appendChild(prompt);
          fragment.appendChild(document.createTextNode(" " + line.slice(2)));
        } else {
          fragment.appendChild(document.createTextNode(line));
        }
      });
      code.replaceChild(fragment, node);
    });
  });

  /* ---------- Terminal tabs on the homepage ---------- */

  document.querySelectorAll(".terminal").forEach(function (terminal) {
    var tabs = terminal.querySelectorAll(".terminal-tabs button");
    var panes = terminal.querySelectorAll(".terminal-body");
    if (!tabs.length || !panes.length) return;
    tabs.forEach(function (tab, i) {
      tab.addEventListener("click", function () {
        tabs.forEach(function (t) { t.setAttribute("aria-selected", "false"); });
        panes.forEach(function (p) { p.hidden = true; });
        tab.setAttribute("aria-selected", "true");
        if (panes[i]) panes[i].hidden = false;
      });
    });
  });
})();
