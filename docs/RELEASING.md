# Releasing Tutti

Releases are automatic: pushing a version tag to GitHub runs `.github/workflows/release.yml`,
which runs the offline checks (the test suite, the syntax check and the media check),
packages the addon with the BigWigs packager and uploads it. Only the addon files go into
the package: `.pkgmeta` leaves out `docs/`, `tests/`, `tools/`, `README.md` and `CLAUDE.md`,
and the packager skips every dot-folder (`.github`, `.git`, ...) by itself. A GitHub release
with the zip is always created, and CurseForge project 1805550 gets the file too (its id and
token were set up once, below).

`Tutti.toc` names every client in one line, `## Interface: 120105, 120107, 50504, 40402, 38002,
30405, 20506, 16001, 11509` (Retail, the Classic clients, WoW Forever), so the packager tags
every upload with all of those game versions and names the zip `Tutti-<tag>.zip`.

## One-time setup

Steps 1 to 3 are done (2026-11-14): CurseForge project 1805550, its id in `Tutti.toc`, the
token in the secret `CF_API_KEY`. They stay here for a new token or another site.

### 1. Create the CurseForge project (in the browser, your account)

1. Go to https://authors.curseforge.com, choose **Create Project**, game **World of
   Warcraft**, class **Addons**.
2. Fill in the form from [listing/curseforge.md](listing/curseforge.md): name, summary,
   description, categories, license **MIT**, avatar `listing/icon.png`.
3. Submit. CurseForge reviews new projects; once it is created, note the **Project ID**
   (shown on the project's About box).

### 2. Put the project id into the TOC

`Tutti.toc` has this line, under `## Author`, and `tests/test_load.lua` checks it. The release
is built from the tagged commit, and without the id the upload to CurseForge is skipped.

```
## X-Curse-Project-ID: 1805550
```

### 3. Give GitHub an upload token

1. CurseForge: https://authors.curseforge.com/#/settings/api-tokens → create a token. A
   token belongs to the account, so the one Sotto uses works for Tutti too.
2. GitHub: the repository `creazy231/Tutti`, **Settings → Secrets and variables → Actions →
   New repository secret**, name `CF_API_KEY`, value the token. Or from a terminal:
   `gh secret set CF_API_KEY -R creazy231/Tutti`.

Optional, the same way: Wago (`## X-Wago-ID` + secret `WAGO_API_TOKEN`) and WoWInterface
(`## X-WoWI-ID` + secret `WOWI_API_TOKEN`; it has no WoW Forever version, so the file is
listed there for the other clients only).

### 4. Gallery

Upload `listing/screenshots/01…06` to the project's gallery with the captions from
[listing/curseforge.md](listing/curseforge.md). The packager does not touch images. The
hero image in the description is loaded from GitHub (its raw URL), so it shows once the
repository is public and `main` has the file.

## Every release

1. Add the changes under a new version heading in `CHANGELOG.md` (the packager uses the
   file as the release's changelog; the first release's heading loses its "(unreleased)")
   and commit.
2. Tag and push:

   ```sh
   git tag 1.0.0
   git push origin main 1.0.0
   ```

   `1.0.0` uploads a release file; `1.1.0-beta1` a beta, `1.1.0-alpha1` an alpha.
   `## Version: @project-version@` in the TOC becomes the tag.
3. Watch the run under the repository's **Actions** tab. It fails before uploading if a
   check fails.

Never reuse a version number: if a release went wrong, make a new one.

## Trying it without uploading

**Actions → Release → Run workflow** is a dry run. It runs the checks and packages exactly
as a tag would, uploads nothing, and keeps the zip as the run's artifact `Tutti-package`.
Unzip it and check that its `Tutti/` folder holds `Tutti.toc`, `LICENSE`, `CHANGELOG.md`,
`Core/`, `UI/` and `Media/` and nothing else: no `docs/`, `tests/`, `tools/`, `.github/`,
`README.md` or `CLAUDE.md`.

## When a game version is patched

`## Interface` in `Tutti.toc` lists one number per client (Retail, the Classic clients,
WoW Forever: 1.60.1 is 16001). A client whose number is missing marks Tutti out of date, and
Retail does not load it at all. After a patch, add the client's new number (current values:
https://warcraft.wiki.gg/wiki/TOC_format, or `/dump select(4, GetBuildInfo())` in that
client), keep `tests/test_load.lua`'s `INTERFACES` in step, note it in `CHANGELOG.md` and
release a new version. If CurseForge does not list a new version yet, the packager tags the
file with the nearest older one and says so in the run's log.

## Notes

- The repository is public (github.com/creazy231/Tutti). `docs/mockup/` (the design mockup
  with a private game screenshot and EllesmereUI's licensed font) and `.superpowers/` are
  ignored by git; never add them.
- Commits use the repository's own identity (`creazy231`, GitHub no-reply address);
  keep it that way (`git config user.name`, `user.email` in this repository).
