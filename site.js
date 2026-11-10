// Progressive enhancement only. The pages work without this file.
document.querySelectorAll("[data-copy]").forEach((button) => {
  const originalLabel = button.textContent;
  let resetTimer;

  button.addEventListener("click", async () => {
    const target = document.getElementById(button.dataset.copy);
    if (!target) return;
    const text = target.textContent.trim();
    try {
      await navigator.clipboard.writeText(text);
      button.textContent = "COPIED";
    } catch {
      const range = document.createRange();
      range.selectNodeContents(target);
      const selection = window.getSelection();
      if (selection) {
        selection.removeAllRanges();
        selection.addRange(range);
      }
      button.textContent = "SELECTED";
    }
    window.clearTimeout(resetTimer);
    resetTimer = window.setTimeout(() => { button.textContent = originalLabel; }, 1600);
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
    if (menu.open && event.key === "Escape") {
      menu.removeAttribute("open");
      menu.querySelector("summary").focus();
    }
  });
}
