// Dark Pages: flips page colours with a CSS filter. The setting is saved once and applies to every site.
const CLASS = 'yavqo-dark-pages';
const apply = (on) => document.documentElement.classList.toggle(CLASS, on);

saturn.storage.get({ enabled: false }).then(({ enabled }) => apply(enabled));
saturn.runtime.onMessage.addListener((message, respond) => {
  if (message.type === 'set') { apply(!!message.value); respond({ ok: true }); }
});
