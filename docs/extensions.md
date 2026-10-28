# Saturn extensions

Extensions add features to Saturn: restyle a page, add a button, count words, hide what you don't want to see.
They are made of plain HTML, CSS and JavaScript, in a folder with a `manifest.json`.

- **Find and add extensions:** open `saturn://extensions` (or the puzzle piece in the toolbar ▸ **Extension Store…**).
- **Build one:** `saturn://extensions` ▸ **Build your own** ▸ **Create from template**.
- **Share it:** [submit it to the store](#submit-to-the-store).

## Quick start

1. Open `saturn://extensions#build` and press **Create from template**. Saturn copies the starter to
   `Documents/Saturn Extensions/my-extension` and loads it.
2. Visit https://example.com. The links are outlined; open the extension from the puzzle piece to switch that off.
3. Edit the files. Press **Reload** on the extension's card, then refresh the page.

The starter lives in this repository too: [`extensions-template/`](../extensions-template).

## Folder layout

```
my-extension/
  manifest.json      required
  content.js         runs on the pages you choose
  content.css        styles added to those pages
  popup.html         optional window opened from the toolbar
  popup.js, popup.css
  icon.svg           optional, shown in the list
```

Allowed file types: `json js css html svg png jpg jpeg gif webp ico woff woff2 txt md`.
Limits: 1 MB per file, 5 MB and 200 files in total, no links (symlinks).

## manifest.json

| Field | Required | Meaning |
|---|---|---|
| `manifest_version` | yes | Always `1`. |
| `id` | yes | `yourname.extension-name`: 3–64 lowercase letters, numbers, dots and dashes. Unique in the store. Ids that start with `local.` are for your own copies and can't be submitted. |
| `name` | yes | Up to 45 characters. |
| `version` | yes | `1.0.0`. Raise it for every update. |
| `description` | store: yes | Up to 200 characters, plain words. |
| `author` | store: yes | Up to 60 characters. |
| `icon` | no | Path to an image in the folder. |
| `permissions` | no | A list from the table below. |
| `content_scripts` | one of these two | What runs on web pages (below). |
| `action` | one of these two | `{ "title", "popup", "popup_width", "popup_height" }`. The popup is an HTML file; width 200–600, height 100–600. |
| `web_accessible_resources` | no | Files that web pages may load through `saturn.runtime.getURL()`. |
| `tags` | no | Up to 5 words for store search. |

### content_scripts

```json
"content_scripts": [{
  "matches": ["https://example.com/*", "https://*.wikipedia.org/*"],
  "exclude_matches": ["https://example.com/private/*"],
  "js": ["content.js"],
  "css": ["content.css"],
  "run_at": "document_idle",
  "all_frames": false
}]
```

- `matches` uses the same patterns as other browsers: `scheme://host/path`, where the scheme is `https`, `http` or `*`,
  the host is a name, `*.name` or `*`, and `*` in the path matches anything. `<all_urls>` matches every web page.
- `run_at`: `document_start` (before the page builds), `document_end` or `document_idle` (default).
- Your code runs in its **own JavaScript world**. Pages can't see or change it, and your variables don't leak into the page.
  The page's elements (the DOM) are shared, so you read and change them as usual. Page CSP can't block it.
- Files in one entry share a scope; separate entries don't.

### Permissions

People see these before they add your extension, so ask only for what you use.

| Permission | Lets you |
|---|---|
| `storage` | Save settings with `saturn.storage` (up to 1 MB). |
| `activeTab` | From the popup, read the open page's address and title and message your content script. |
| `clipboardWrite` | Copy text with `saturn.clipboard.writeText`. |
| `tabs` | Open pages with `saturn.tabs.open`. |

Content scripts can read and change the pages their `matches` allow; that is shown as "Read and change data on …".

## The `saturn` API

Available in content scripts and in the popup. Every call returns a promise.

```js
// storage (needs "storage")
await saturn.storage.set({ theme: 'dark' });
const { theme } = await saturn.storage.get({ theme: 'light' });   // an object gives defaults
await saturn.storage.get('theme');                                // a name or a list of names
await saturn.storage.remove('theme');
await saturn.storage.clear();

// your own files
saturn.runtime.getURL('images/hello.png');   // list it under web_accessible_resources to use it on a web page
saturn.runtime.id;

// content script: answer the popup
saturn.runtime.onMessage.addListener((message, respond) => {
  if (message.type === 'ping') respond({ pong: true });          // or return a promise, or return true and respond later
});

// popup only (needs "activeTab")
const page = await saturn.tabs.active();                          // { url, title }
const reply = await saturn.tabs.sendMessage({ type: 'ping' });    // goes to your content script on the open page

// other
await saturn.tabs.open('https://example.com');                    // needs "tabs"; http and https only
await saturn.clipboard.writeText('Copied');                       // needs "clipboardWrite"
```

### Popups

A popup is a small web page in a window under the toolbar button. It can only load files from your extension:
**no inline scripts, no remote scripts, no network requests** (`script-src 'self'`, `connect-src 'self'`).
Put code in a `.js` file and link it with `<script src="popup.js" defer>`. If you need the network, do it from a
content script on a page you have access to, or ask in your pull request.

## Test it

1. `saturn://extensions` ▸ **Load a folder…** and pick your folder. Saturn shows what the extension can do and asks you to confirm.
2. After you change files press **Reload** on the card, then refresh the page. Content scripts are added when a page loads.
3. Errors from your content script appear in the page's console (right-click ▸ Inspect Element). Popups can be inspected the same way.
4. Run the same checks the store runs: `python3 scripts/saturn-ext.py validate path/to/your-extension`.

Extensions don't run in private windows.

## Submit to the store

1. Fork https://github.com/Yavqo/Saturn.
2. Copy your finished folder to `store/extensions/<id>/`. The folder name must equal the `id` in your manifest.
3. Run `python3 scripts/saturn-ext.py validate store/extensions/<id>` until it passes.
4. Open a pull request using the **extension** template (`?template=extension.md`). Explain every permission.
5. A person reviews it. After it is merged, GitHub builds the package and updates the catalogue, and people see it in the store.

To update, change your files, raise `version`, and open another pull request.

### What reviewers look for

- **Does what it says.** The name, description and code agree.
- **Least access.** Only the permissions and sites it needs. `<all_urls>` needs a reason.
- **Readable code.** No minified or obfuscated code, no `eval`, no downloading and running code from elsewhere.
- **No snooping.** No collecting browsing data, no hidden requests, no ads or affiliate rewriting.
- **Safe with passwords.** Extensions may not read password fields or Yavqo Vault.
- **Yours to share.** You wrote it, or its licence lets Yavqo distribute it.

Extensions that break these rules are removed from the store.

## How the store works

`store/index.json` lists every extension; `store/packages/` holds one `.zip` per extension. Both are generated by
`python3 scripts/saturn-ext.py build-store` (CI runs it after a merge, so you don't commit them yourself).
Each entry carries a SHA-256 checksum, and Saturn refuses a download that doesn't match, then validates the package
again with the same rules as above before it asks you to add it.

Saturn reads the catalogue from
`https://raw.githubusercontent.com/Yavqo/Saturn/main/store/index.json` and falls back to the copy bundled with the app.
