Fix a Depot CI workflow or job until it is green.

1. Run the portable job with `depot ci run --repo xianwei/responsay-macos --org 2wztpgtn69 --workflow .depot/workflows/ci.yml --job guard` and retain the printed `<run-id>`. Never rely on remote autodetection: the `github` remote is the archive, not the code forge.
2. Read `depot ci status <run-id> --org 2wztpgtn69 --output json`, then run `depot ci diagnose --run <run-id> --org 2wztpgtn69 --output json`. Verify every diagnosis against the logs.
3. Read a failed job with `depot ci logs <run-id> --org 2wztpgtn69 --job guard`. Use `depot ci ssh <run-id> --org 2wztpgtn69 --job guard`, or rerun the fully scoped step-1 command with `--ssh-after-step <1-based-step-number>`, only when logs do not expose the cause.
4. Fix the current branch and rerun. Stop after four failed attempts and report the exact blocker.

Depot is intentionally limited to portable source, policy, privacy, and deterministic credential-pattern guards. Full Gitleaks and TruffleHog history/worktree scans run on Buildkite. Do not add Linux Swift or Xcode substitutes and call them macOS validation. The authoritative native gates run on Buildkite's hosted Apple Silicon macOS queue.

You may run and inspect Depot jobs, SSH into their sandboxes, and edit the current branch. Ask before changing secrets or variables, changing release behavior, opening a pull request, or expanding into an unrelated refactor.

When done, report the root cause, changes, and green run ID. If still blocked, report the failed step, evidence, and next command.
