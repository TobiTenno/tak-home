/** Collapse site/sidebar nav on narrow viewports; expand only when toggled. */
(function () {
  const MQ = window.matchMedia("(max-width: 960px)");

  function enhance(root) {
    if (root.dataset.navEnhanced === "1") return;
    root.dataset.navEnhanced = "1";

    const brand = root.querySelector(".brand");
    const panel = document.createElement("div");
    panel.className = "side-panel";
    panel.id = "nav-panel-" + Math.random().toString(36).slice(2, 8);

    [...root.children].forEach((el) => {
      if (el === brand) return;
      panel.appendChild(el);
    });

    const top = document.createElement("div");
    top.className = "side-top";
    if (brand) top.appendChild(brand);

    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "nav-toggle";
    btn.setAttribute("aria-controls", panel.id);
    btn.setAttribute("aria-expanded", "false");
    btn.textContent = "Menu";
    top.appendChild(btn);

    root.prepend(top);
    root.appendChild(panel);

    function setOpen(open) {
      root.classList.toggle("is-open", open);
      btn.setAttribute("aria-expanded", open ? "true" : "false");
      btn.textContent = open ? "Close" : "Menu";
    }

    btn.addEventListener("click", () => setOpen(!root.classList.contains("is-open")));

    panel.addEventListener("click", (e) => {
      const a = e.target.closest("a");
      if (!a || !MQ.matches) return;
      setOpen(false);
    });

    MQ.addEventListener("change", () => {
      if (!MQ.matches) setOpen(false);
    });
  }

  function boot() {
    document
      .querySelectorAll(".side, nav[aria-label='Steps']")
      .forEach(enhance);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
