const toggle = document.getElementById('toggle');
saturn.storage.get({ enabled: false }).then(({ enabled }) => { toggle.checked = enabled; });
toggle.addEventListener('change', async () => {
  await saturn.storage.set({ enabled: toggle.checked });
  try { await saturn.tabs.sendMessage({ type: 'set', value: toggle.checked }); } catch (e) { /* not a web page */ }
});
