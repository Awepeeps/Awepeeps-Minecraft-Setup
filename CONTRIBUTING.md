# Contributing

Thanks for improving the portable setup template. This repository is public:
everything you commit is visible to everyone.

## Ground rules

- **Keep the template generic.** Never commit secrets or instance values:
  hostnames, IPs, non-default ports, usernames, home-directory paths, MCSManager
  ids or UUIDs, player names or UUIDs, whitelist/ops contents, seeds,
  coordinates, Discord ids, webhook URLs, tokens, or passwords. Use placeholders
  such as `<SERVER_HOST>`, `<instance-data>`, `/srv/minecraft`, and `CHANGE_ME`.
- **Do not copy from the private deployment verbatim.** Read it line by line and
  replace every instance value with a placeholder. See
  [`AGENTS.md`](AGENTS.md) and the sanitizing-port workflow in
  [`.agents/skills/portable-template-change/SKILL.md`](.agents/skills/portable-template-change/SKILL.md).
- **Never invent a version or a hash.** Measure a jar's SHA-256 and pin the exact
  version or source commit; leave unknown URLs and digests as `TODO`.

## Before you open a pull request

1. Work on a branch of your fork (`origin`); open the pull request against the
   org repository's `main`. See the README's contribution workflow.
2. Run the mock test suites. They need no Docker, network, or live server:

   ```bash
   bash automation/run-tests.sh
   ```

3. Run the same checks CI runs, when you have the tools available:

   ```bash
   find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 -n1 bash -n
   find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 shellcheck --severity=warning --external-sources
   gitleaks dir . --redact --no-banner
   ```

   CI runs `bash -n`, a pinned `shellcheck`, the mock suites, YAML validation,
   and a pinned `gitleaks` secret scan. All of them must pass.
4. Scan your diff for instance values and secrets before you push. Fill in the
   pull request checklist honestly.

## Documentation

Update the relevant guide under [`docs/`](docs/) whenever a change alters
behavior, a pin, or a documented variable. If you add or rename an environment
variable, document it in [`.env.example`](.env.example) in the same change.
