# GitHub Actions: Sierra de Guardia

Workflow: `.github/workflows/rojo-ci.yml`.

- On pull requests and pushes to `main`: installs pinned Rojo 7.7.0 and Luau 0.743, runs project checks and phase 3–11 tests, compiles Luau sources, analyzes pure modules, builds `build/sierradeguardia.rbxlx`, and uploads it as an Actions artifact.
- No Roblox upload occurs on pull requests or pushes.
- On a manual `workflow_dispatch` run on `main` only, tests/build must pass before the upload job runs.
- The manual workflow now asks for **Version target**:
  - **Saved** (default): saves a draft version; it does not make the version live.
  - **Published**: publishes the built place version, which can change what players see when they join. Choose this only after reviewing the build and confirming you want to update the live game.
- The upload job uses the GitHub environment `roblox-saved`. You may configure required reviewers for that environment in repository Settings for an extra approval step.

Set the following in repository Settings > Secrets and variables > Actions:

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `ROBLOX_API_KEY` | Your private Roblox Open Cloud key (never commit it) |
| Variable | `ROBLOX_UNIVERSE_ID` | `10772177636` |
| Variable | `ROBLOX_PLACE_ID` | `79277734505316` |

In Roblox Creator Dashboard, restrict the key to the correct experience and grant the Place Publishing API's required `universe-places` write permission. Keep the key secret; do not paste it into issues, PRs, workflow files or chats.

After reviewing and merging the PR into `main`, open the repository's Actions tab, select **Sierra de Guardia - Rojo CI**, choose **Run workflow**, select `main`, then select the desired **Version target**. Use **Saved** for a draft or **Published** to update the live version. The workflow does not run the upload job on pull requests or ordinary pushes.

These checks do not execute Roblox Studio or verify runtime gameplay. A green CI run proves the project builds and static tests pass, not that the map renders correctly in a live Roblox server. Verify the result in a private test environment before publishing to all players.
