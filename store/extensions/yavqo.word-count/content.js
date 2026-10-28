// Word Count: answers the popup's question. It reads the page only when you open the popup.
function countWords(text) {
  const words = text.trim().match(/\S+/g);
  return words ? words.length : 0;
}

saturn.runtime.onMessage.addListener((message, respond) => {
  if (message.type !== 'count') return;
  const selection = String(window.getSelection() || '');
  const page = countWords(document.body ? document.body.innerText : '');
  respond({ page, selection: countWords(selection), minutes: Math.max(1, Math.round(page / 230)) });
});
