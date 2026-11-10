// Progressive enhancement only. The pages work without this file.
document.querySelectorAll("[data-copy]").forEach((button) => {
  button.addEventListener("click", async () => {
    const target = document.getElementById(button.dataset.copy);
    if (!target) return;
    const text = target.textContent.trim();
    try {
      await navigator.clipboard.writeText(text);
      const old = button.textContent;
      button.textContent = "COPIED";
      window.setTimeout(() => { button.textContent = old; }, 1600);
    } catch {
      const range = document.createRange();
      range.selectNodeContents(target);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      button.textContent = "SELECTED";
      window.setTimeout(() => { button.textContent = "COPY"; }, 1600);
    }
  });
});

// Close the mobile menu after choosing a destination.
const menu = document.querySelector("details.menu");
if (menu) {
  menu.querySelectorAll("a").forEach((link) => {
    link.addEventListener("click", () => menu.removeAttribute("open"));
  });
  document.addEventListener("click", (event) => {
    if (menu.open && !menu.contains(event.target)) menu.removeAttribute("open");
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") menu.removeAttribute("open");
  });
}
