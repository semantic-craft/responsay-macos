Diagnose and fix the current GitHub pull request's CI failure.

Read `docs/operations/ci.md` for the required checks. Use `gh pr checks --repo semantic-craft/responsay-macos <number>` to identify the failing run, then `gh run view --repo semantic-craft/responsay-macos <run-id> --log-failed` to inspect its evidence. Fix the cause on the task branch, run relevant local checks, and rerun the affected GitHub Actions job within the user's authorized scope.

Report the cause, changes, and verified run result. Preserve the distinction between portable guards, native macOS tests, and real-device acceptance. Keep credentials and signing material out of CI. If external input is required, report the failed step and smallest next action.
