(() => {
  const query = window.matchMedia("(prefers-color-scheme: dark)");
  let theme = "system";

  try {
    const stored = window.localStorage.getItem("phx:theme");
    if (stored === "light" || stored === "dark") theme = stored;
  } catch (_error) {
    // System preference remains available when storage is restricted.
  }

  const effective = theme === "system" ? (query.matches ? "dark" : "light") : theme;
  document.documentElement.dataset.theme = effective;
  document.documentElement.dataset.themeSource = theme === "system" ? "system" : "user";
})();
