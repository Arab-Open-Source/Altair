// Adds a copy button and a language label to every code block, plus a
// copy button on the homepage hero's one-liner. Runs after the document
// is parsed (deferred script).

(function () {
  "use strict";

  var LANGS = {
    sh: "Shell",
    shell: "Shell",
    bash: "Shell",
    crystal: "Crystal",
    cr: "Crystal",
    ruby: "Ruby",
    yaml: "YAML",
    yml: "YAML",
    json: "JSON",
    html: "HTML",
    erb: "ERB",
    powershell: "PowerShell",
    cmd: "Cmd",
    text: "Text",
    diff: "Diff",
    "": "Text"
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
  // Built with text nodes only — the code text is already escaped.
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
})();
