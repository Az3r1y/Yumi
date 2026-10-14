# Release notes: the format

Every release tells what Yumi can now do, not what changed in the code. Same order each time, English first, French after.

## Title

`Yumi <version>: <what he learned>`, written for a user.

- Good: « Yumi 0.1.0-alpha.8: he ticks your Notion tasks », « … : reminders that repeat ».
- Avoid: « Permission architecture refactor », « Performance improvements ».

When a release has no new trick (fixes only), say what got better for the user: « … : lighter on your battery ».

## Body

```markdown
## What's new
- **<The trick, in user words>.** One or two sentences: what you say, what he does, where you see it.

## Why it matters
<One sentence.>

## Try it
1. <Exact words to say, or where to click.>
2. <What you should see, and in which app.>

<GIF or video of the real app doing it: request, approval, result in the real app.>

## Technical notes
- <For developers: tools, permissions, risk level, fixes.>

## Install or update
If you already have Yumi, he tells you this version is out: replace Yumi.app in Applications, your settings and permissions are kept.
New here: download `Yumi-<version>.zip`, drag Yumi.app into Applications. Not notarized by Apple yet: the first time, System Settings › Privacy & Security › « Open Anyway ». macOS 15 or later. Built by GitHub Actions from the public code: `SHA256SUMS.txt` and the attestation are on this page.

## Feedback
Something wrong? [Open a bug](https://github.com/estebanbaigts/Yumi/issues/new?template=bug.yml). What should he learn next? [Suggest a new trick](https://github.com/estebanbaigts/Yumi/issues/new?template=trick.yml). No GitHub account: **Send feedback** in Yumi's menu.

If the trick came from someone's suggestion, thank them here, with a link to the issue.

---

**Version française** : mêmes rubriques, dans le même ordre (Nouveau, Pourquoi c'est utile, Essaie, Notes techniques, Installer, Retours).
```

## Before publishing

- The GIF or video shows the real app, never a mock.
- Every sentence of « What's new » is true in the code of this tag.
- The trick issue it answers is closed, with a link to the release.
- One short video of the trick is ready for the « Yumi learned… » series.
