# Git conventions

This page records how we use git in this repository: how to branch, how to write commits, and what
must never be committed. It does not cover code review or the release process. These conventions are
in force today.

- Branch off `main`, and keep feature branches short-lived.
- Use [Conventional Commits](https://www.conventionalcommits.org) prefixes: `feat:`, `fix:`,
  `chore:`, `docs:`, `refactor:`, and `test:`.
- Keep each commit focused. When the reason for a change is not obvious from the diff, explain that
  reason in the commit body.
- Do not commit secrets. `.env` is gitignored, and it must stay that way.
- The versioned pre-commit hook formats supported staged files and re-stages only files it changes.
  `pnpm format:staged` runs the same operation manually when needed.
