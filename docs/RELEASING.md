# Releasing Tutti

Releases are automatic: pushing a version tag to GitHub runs `.github/workflows/release.yml`,
which runs the offline checks (the test suite, the syntax check and the media check),
packages the addon with the BigWigs packager and uploads it. Only the addon files go into
the package: `.pkgmeta` leaves out `docs/`, `tests/`, `tools/`, `README.md` and `CLAUDE.md`,
and the packager skips every dot-folder (`.github`, `.git`, ...) by itself. A GitHub release
with the zip is always created; CurseForge gets the file once its project id and token are
set up (below).

Tutti is for WoW Forever only. `Tutti.toc` names one game version, `## Interface: 16001`
(WoW Forever 1.60.1), so the packager tags every upload with that version and names the zip
`Tutti-<tag>-forever.zip`.

## One-time setup

### 1. Create the CurseForge project (in the browser, your account)

1. Go to https://authors.curseforge.com, choose **Create Project**, game **World of
   Warcraft**, class **Addons**.
2. Fill in the form from [listing/curseforge.md](listing/curseforge.md): name, summary,
   description, categories, license **MIT**, avatar `listing/icon.png`.
3. Submit. CurseForge reviews new projects; once it is created, note the **Project ID**
   (shown on the project's About box).

### 2. Put the project id into the TOC

Add this line to `Tutti.toc` (under `## Author`) and push it to `main` before you tag the
first version. The release is built from the tagged commit, and without the id the upload
to CurseForge is skipped.

```
## X-Curse-Project-ID: 123456
```

### 3. Give GitHub an upload token

1. CurseForge: https://authors.curseforge.com/#/settings/api-tokens → create a token. A
   token belongs to the account, so the one Sotto uses works for Tutti too.
2. GitHub: the repository `creazy231/Tutti`, **Settings → Secrets and variables → Actions →
   New repository secret**, name `CF_API_KEY`, value the token. Or from a terminal:
   `gh secret set CF_API_KEY -R creazy231/Tutti`.

Optional, the same way: Wago (`## X-Wago-ID` + secret `WAGO_API_TOKEN`; Wago lists WoW
Forever 1.60.1). WoWInterface has no WoW Forever game version, so there is nothing to
upload to there.

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

## When WoW Forever is patched

`## Interface: 16001` in `Tutti.toc` is Forever's current interface number (1.60.1 is
16001; a patch to 1.60.2 or 1.61.0 would make it 16002 or 16100). A client whose number
differs marks Tutti out of date. After a patch, put the new number into `## Interface`
(current value: `/dump select(4, GetBuildInfo())` in Forever, or
https://warcraft.wiki.gg/wiki/TOC_format), keep the check in `tests/test_load.lua` in step,
note it in `CHANGELOG.md` and release a new version. If CurseForge does not list the new
Forever version yet, the packager tags the file with the nearest older one and says so in
the run's log.

## Notes

- The repository is public (github.com/creazy231/Tutti). `docs/mockup/` (the design mockup
  with a private game screenshot and EllesmereUI's licensed font) and `.superpowers/` are
  ignored by git; never add them.
- Commits use the repository's own identity (`creazy231`, GitHub no-reply address);
  keep it that way (`git config user.name`, `user.email` in this repository).
