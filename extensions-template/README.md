# My Extension

A starter Saturn extension. Everything here is plain HTML, CSS and JavaScript.

| File | What it does |
|---|---|
| `manifest.json` | Name, version, permissions, which pages it runs on, and its toolbar popup. |
| `content.js`, `content.css` | Run on the pages listed under `matches`. |
| `popup.html`, `popup.css`, `popup.js` | The window that opens from the puzzle piece in the toolbar. |
| `icon.svg` | Shown in the extensions list. |

## Try it

1. In Saturn open `saturn://extensions`, go to **Build your own** and press **Create from template** (this folder was made that way).
2. Visit https://example.com. The links get a blue outline. Open the extension from the puzzle piece in the toolbar to turn it off.
3. Change a file, press **Reload** on the extension's card, then refresh the page.

## Make it yours

- Give it your own `id` (`yourname.what-it-does`), `name`, `description` and `author` in `manifest.json`.
- Change `matches` to the sites it should run on. Only ask for what you need: people see this list before they add it.
- Read the developer guide: https://github.com/Yavqo/Saturn/blob/main/docs/extensions.md

## Submit it to the store

See **Submit to the store** in the developer guide. In short: put your folder in `store/extensions/<id>/` of https://github.com/Yavqo/Saturn and open a pull request.
