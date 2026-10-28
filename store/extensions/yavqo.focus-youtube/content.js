// Focus for YouTube: each setting turns on a data attribute on <html>; content.css does the hiding.
const DEFAULTS = { comments: true, related: true, shorts: true };

function apply(settings) {
  for (const key of Object.keys(DEFAULTS)) {
    document.documentElement.toggleAttribute('data-focus-' + key, !!settings[key]);
  }
}

saturn.storage.get(DEFAULTS).then(apply);
saturn.runtime.onMessage.addListener((message, respond) => {
  if (message.type === 'settings') { apply(message.value); respond({ ok: true }); }
});
