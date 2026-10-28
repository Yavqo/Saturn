const DEFAULTS = { comments: true, related: true, shorts: true };
const boxes = [...document.querySelectorAll('input[data-key]')];

async function init() {
  const settings = await saturn.storage.get(DEFAULTS);
  for (const box of boxes) box.checked = !!settings[box.dataset.key];
}
for (const box of boxes) {
  box.addEventListener('change', async () => {
    const settings = Object.fromEntries(boxes.map((b) => [b.dataset.key, b.checked]));
    await saturn.storage.set(settings);
    try { await saturn.tabs.sendMessage({ type: 'settings', value: settings }); } catch (e) { /* not on YouTube */ }
  });
}
init();
