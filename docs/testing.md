# Agent-assisted Minecraft testing

This guide describes a safe, portable model for testing a Minecraft server with
an authorized Java account and an agent-operated Mineflayer client. It documents
the workflow and its safeguards; it does not provide access to, or configuration
for, any live server.

## Repository boundaries

- **Awepeeps-Minecraft-Setup (this repository)** is public. It contains portable
  templates and documentation with generic placeholders.
- **The deployment repository** is private. It owns instance-specific version
  pins, live configuration, and the guarded test harness. Keep these materials,
  along with deployment paths and operational records, out of this repository.
- **Awepeeps Spawn Kit** is maintained in its own public plugin repository. It
  defaults to disabled and empty; the consuming server supplies its own item
  list and optional inclusive date window. Keep test-only pins and configuration
  out of live-season plugin sets.
- **Awepeeps-BlueMap-Compass** is separately maintained public source code for
  custom compass navigation.

Do not copy private deployment documentation or history into this repository.
When publishing examples, replace account, host, path, and instance identifiers
with generic placeholders. Never include owner identity, server addresses,
deployment paths, tokens, or other access details.

## What runs the test client

The test client is a **private, guarded Mineflayer harness**, controlled from a
terminal and coordinated through an agent or
MCP orchestration. This means an agent can request and observe test actions; it
does **not** mean a Minecraft MCP server is installed on or exposed by the game
server. Keep the orchestration interface distinct from the Minecraft client and
server.

The harness uses only an authorized Microsoft Java account, and only while the
owner's normal Minecraft client is disconnected. It checks the expected
account/profile before joining. Authentication is subject to explicit safety
gates described below; never automate login for an account without the owner's
authorization.

## Safety gates and local secrets

Before attempting authentication, the harness verifies through local Docker
RCON that the disposable test server has zero players. It checks the same
zero-player condition again after authentication, before proceeding with a
join. If either check fails, stop the run and resolve the unexpected player
state; do not bypass the guard. The exact expected account/profile is also
validated before the client connects.

Keep cached Microsoft authentication tokens outside Git and outside public
artifacts. Device prompts and local environment files (including `.env`) are
ignored local state, not documentation to publish. Never put passwords, tokens,
device codes, or other authentication secrets in logs, screenshots, agent
prompts, or test output. The test harness should report outcomes without
printing secret values.

Use a disposable local server for this workflow. Do not point the harness at a
production server. Keep any environment-specific host, port, version pins, and
RCON details in the private deployment environment, not in this public guide.

## Compatibility scope

Select an explicit protocol supported by the pinned Mineflayer release. A
translated older-client connection has passed smoke and basic menu checks in
the private test environment. Other attempted protocols disconnected for an
unconfirmed reason. This does not establish compatibility for every gameplay
feature, newer item component, or protocol combination. Keep the exact tested
matrix, deployment pins and diagnostic evidence in the private repository.

## Acceptance checklist

Record a run as accepted only when all applicable items pass:

- The run targets a disposable local server, with the intended versions pinned
  in the private environment.
- The owner's authorized Java account is used, and the owner's regular client
  is disconnected.
- The exact expected account/profile guard passes.
- Local Docker RCON confirms zero players before authentication and confirms the
  expected zero-player state again after authentication.
- The agent operates the terminal/Mineflayer harness through the approved
  orchestration path; no Minecraft MCP server is assumed or required.
- The client joins only the intended local test server and completes the
  explicitly scoped scenario (for the verified baseline, the basic menu flow).
- The observed result and any failure are recorded without account identity,
  host details, deployment paths, or authentication secrets.
- The client disconnects cleanly and the local server is returned to its
  pre-test state.

If a guard fails, the target is ambiguous, authentication unexpectedly prompts
or fails, the client lands on the wrong server, or the behavior is outside the
verified scope, stop and mark the run unaccepted. Do not weaken a guard to make
a run pass.

## Teardown and restoration

After each run:

1. Disconnect the Mineflayer client and confirm it is no longer present.
2. Stop the disposable test server using its normal local lifecycle controls.
3. Restore any temporary local test configuration from the saved baseline, or
   discard the disposable environment and recreate it from clean templates.
4. Keep cached authentication state outside the repository; remove it using the
   account owner's normal credential-management procedure if it should no
   longer be retained.
5. Confirm no local environment file, device prompt, token cache, log, world,
   or generated artifact was added to the public repository or staged for
   publication.

This guide is intentionally limited to the public workflow and verified scope.
Private harness implementation, live configuration, and instance-specific
operational instructions remain in the private deployment repository.
