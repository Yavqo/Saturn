// Runs on the pages listed under "matches" in manifest.json.
// It lives in its own JavaScript world: the page can't see this code, and this code can't see the page's variables.
// The page's DOM is shared, so you can read and change elements as usual.

const CLASS = 'my-extension-on';

function apply(on) {
  document.documentElement.classList.toggle(CLASS, on);
}

// Saved settings (needs the "storage" permission). The object is the default value.
saturn.storage.get({ highlight: true }).then(({ highlight }) => apply(highlight));

// Messages from the popup (the popup needs the "activeTab" permission to send them).
saturn.runtime.onMessage.addListener((message, respond) => {
  if (message.type === 'setHighlight') {
    apply(message.value);
    respond({ ok: true });
  } else if (message.type === 'getStats') {
    respond({ links: document.links.length });
  }
});
