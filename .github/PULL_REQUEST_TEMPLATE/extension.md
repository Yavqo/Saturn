## New or updated extension

**Extension id:** `yourname.extension-name`
**Folder:** `store/extensions/<id>/`

### What it does
<!-- One or two sentences, in plain words. -->

### Why it needs its access
<!-- Explain every permission and any "matches" pattern, especially <all_urls>. Reviewers read this first. -->

### Checklist
- [ ] `python3 scripts/saturn-ext.py validate store/extensions/<id>` passes
- [ ] I loaded it in Saturn from `saturn://extensions` ▸ Build your own ▸ Load a folder, and it works
- [ ] It asks only for the permissions and sites it needs
- [ ] It has an icon, a `long_description` and 2–4 real screenshots (1280×800 works best)
- [ ] No remote code, no `eval`, no minified or obfuscated code (readable source only)
- [ ] It doesn't collect or send data about the people using it
- [ ] I own the code, or it is under a licence that lets Yavqo distribute it (add a LICENSE file if needed)
- [ ] For an update: I raised `version` in manifest.json
