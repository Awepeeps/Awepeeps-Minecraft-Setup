# Pull request

## Summary

<!-- What changed and why. Link any related issue. -->

## Checklist

- [ ] `bash automation/run-tests.sh` passes locally.
- [ ] Shell changes keep `bash -n`, `shellcheck`, and the mock suites green.
- [ ] **No instance-specific values**: no hostnames, IPs, non-default ports,
      usernames, home-directory paths, MCSManager ids/UUIDs, player names/UUIDs,
      whitelist/ops contents, seeds, coordinates, Discord/webhook ids, tokens, or
      passwords. Placeholders only.
- [ ] The diff was scanned for secrets and instance values (for example
      `gitleaks dir . --redact --no-banner`).
- [ ] Documentation is updated (guides and [`.env.example`](.env.example) for any
      new or renamed variable).
- [ ] Plugin pin changes record a measured version/commit and SHA-256; unknown
      URLs and digests remain `TODO`.
