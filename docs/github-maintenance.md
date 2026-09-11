# GitHub maintenance

## Intended repository settings

These settings require repository administrator access; adding this document does not apply them.

- Enable issues; disable unused wiki and projects.
- Allow squash merging only and delete merged branches automatically.
- Keep automatic merging disabled so the maintainer chooses when to merge.
- Protect main against deletion and force pushes. Require a pull request, resolved conversations and the `Build and test` check. Require zero approving reviews and no code-owner approval so the maintainer can merge their own PR after inspecting it.
- Use read-only default Actions permissions; do not allow Actions to approve PRs. The manual release job alone receives contents-write permission.
- Require approval for workflows from outside contributors before they run.
- Enable dependency alerts, secret scanning, push protection and private vulnerability reporting where supported.
- Retain current repository visibility until deliberately publishing the project.

GitHub does not allow authors to approve their own pull requests. Zero required approvals permits manual self-merge while retaining build checks and reviewable PRs.

## Releases

Run **Actions → Prepare draft release → Run workflow** from main, entering the version tag matching `build.sh`. The workflow builds and tests the selected main commit, packages the app, licence and README, and creates a draft prerelease. It never publishes automatically. Review the draft and publish it yourself when ready; no second reviewer is required.

The package is a development build with ad-hoc signing. It is not notarized. Check installation on another Mac before presenting it as a verified distribution. Increment the app version in `build.sh` before preparing another version. Existing releases are not overwritten.

## Initial setup order

Push and run the Build workflow successfully before making its check required. Verify repository admin access, existing rules and account-plan support before applying protection settings. Confirm the final settings through GitHub after saving them.
