const script = document.querySelector("script[data-beam-console-client]");
const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
const livePath = script?.dataset.livePath || "/live";
const transport = script?.dataset.liveTransport || "websocket";
const themeStorageKey = "phx:theme";
const consoleMountPath = script?.dataset.consolePrefix || "/";
const treeStorageKey = `beam-console:tree:closed:${consoleMountPath}`;
const themeModes = new Set(["system", "light", "dark"]);
const systemThemeQuery = window.matchMedia("(prefers-color-scheme: dark)");

const storedTheme = () => {
  return readStoredTheme(window, themeStorageKey, themeModes);
};

const preferredTheme = () => storedTheme() || "system";
const effectiveTheme = theme => theme === "system" ? (systemThemeQuery.matches ? "dark" : "light") : theme;

const applyTheme = theme => {
  const effective = effectiveTheme(theme);
  document.documentElement.dataset.theme = effective;
  document.documentElement.dataset.themeSource = theme === "system" ? "system" : "user";
  window.dispatchEvent(new CustomEvent("beam-console-theme-change", { detail: { theme: effective, source: theme } }));
};

const persistTheme = theme => {
  writeStoredTheme(window, themeStorageKey, theme);
};

const storedBranchStates = () => {
  return readStoredBranchStates(window, treeStorageKey);
};

const persistBranchStates = states => {
  writeStoredBranchStates(window, treeStorageKey, states);
};
