# GitHub Actions: Sierra de Guardia

Workflow: `.github/workflows/rojo-ci.yml`.

- On pull requests and pushes to `main`: installs pinned Rojo 7.7.0 (via `aftman.toml`) and Luau 0.743, runs the project check and phase 3–11 suites, compiles Luau sources, analyzes pure modules, builds `build/sierradeguardia.rbxlx`, and uploads the file as an Actions artifact.
- No Roblox upload occurs on pull requests or pushes.
- On a **manual** `workflow_dispatch` run on `main` only: the same tests/build must succeed first. The second job saves the compiled place using the Roblox Open Cloud API with `versionType=Saved` (NOT `Published`). It targets the existing place; it does not create a new experience.
- The upload job uses the GitHub environment `roblox-saved`. You may configure required reviewers for that environment in repository Settings for an extra approval step.

Set the following in repository Settings > Secrets and variables > Actions:

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `ROBLOX_API_KEY` | Your private Roblox Open Cloud key (never commit it) |
| Variable | `ROBLOX_UNIVERSE_ID` | `10772177636` |
| Variable | `ROBLOX_PLACE_ID` | `79277734505316` |

In Roblox Creator Dashboard, restrict the key to the correct experience and grant the Place Publishing API's required `universe-places` write permission. Keep the key secret; do not paste it into issues, PRs, workflow files or chats.

After merging this PR into `main`, open the repository's Actions tab, select **Sierra de Guardia - Rojo CI**, choose **Run workflow**, select `main` and run it. This will **save a draft version to Roblox** after the tests pass; it does not make that version live. For build-only checks, simply open a PR or push to main instead. Inspect the Actions logs and download the `sierradeguardia-place` artifact. Never run the manual workflow until you intend to overwrite the saved draft version of the selected place.

These checks do not execute Roblox Studio or verify runtime gameplay. Test the place in Studio or an appropriate private test environment before any live publication.
