# Security policy

## Reporting a vulnerability

Report suspected vulnerabilities **privately** through GitHub's private
vulnerability reporting:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability** (GitHub security advisories).
3. Describe the issue, the affected file or script, and how to reproduce it.

If private reporting is unavailable to you, open an issue that says you have a
security report and ask a maintainer to enable a private channel. Do not include
the details in the public issue.

## What not to post publicly

This repository is a public template, and its issue tracker is public. Never
paste any of the following into an issue, pull request, comment, or screenshot:

- Server addresses, hostnames, IPs, or non-default ports.
- Panel URLs, MCSManager node ids or instance UUIDs.
- Player names, UUIDs, whitelist or operator contents.
- World seeds, coordinates, or Discord/webhook ids.
- Tokens, passwords, API keys, RCON passwords, or backup archives.
- Absolute paths that contain a username or another personal identifier.

Replace every such value with a placeholder (`<SERVER_HOST>`, `<instance-data>`,
`CHANGE_ME`) before you share logs or configuration. Redaction is required even
in a private report unless a maintainer asks for the specific value.

## Scope

This policy covers the code, templates, and automation in this repository. The
running server instance and its secrets live in a separate private deployment
repository; report issues that concern only that deployment to its maintainers
through a private channel, not here.
