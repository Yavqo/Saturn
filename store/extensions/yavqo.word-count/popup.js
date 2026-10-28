const $ = (id) => document.getElementById(id);
const fmt = (n) => n.toLocaleString();
let summary = '';

async function init() {
  try {
    const r = await saturn.tabs.sendMessage({ type: 'count' });
    if (!r) throw new Error('no answer');
    $('page').textContent = fmt(r.page);
    $('selection').textContent = fmt(r.selection);
    $('reading').textContent = `About ${r.minutes} min to read.`;
    summary = `${fmt(r.page)} words, about ${r.minutes} min to read.`;
    $('copy').disabled = false;
  } catch (e) {
    $('reading').textContent = 'Open a web page and reload it, then try again.';
  }
}
$('copy').addEventListener('click', async () => {
  await saturn.clipboard.writeText(summary);
  $('copy').textContent = 'Copied';
});
init();
