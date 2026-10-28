// Runs inside the popup. `saturn` is the extension API (see docs/extensions.md).
const toggle = document.getElementById('toggle');
const stats = document.getElementById('stats');

async function init() {
  const { highlight } = await saturn.storage.get({ highlight: true });
  toggle.checked = highlight;
  try {
    const result = await saturn.tabs.sendMessage({ type: 'getStats' });   // answered by content.js on the open page
    stats.textContent = result ? `${result.links} links on this page.` : 'Open example.com or a Wikipedia page to see it work.';
  } catch (e) {
    stats.textContent = 'Open example.com or a Wikipedia page to see it work.';
  }
}

toggle.addEventListener('change', async () => {
  await saturn.storage.set({ highlight: toggle.checked });
  try { await saturn.tabs.sendMessage({ type: 'setHighlight', value: toggle.checked }); } catch (e) { /* the page isn't one of ours */ }
});

init();
