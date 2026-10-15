# LuckPerms basics (no config-file template)
# Destination on the server: <instance-data>/plugins/LuckPerms/ (generated)
#
# This public repository does not template LuckPerms configuration files; it
# records policy as console commands. Grant only the permissions described in
# this file and docs/nicknames-and-permissions.md.
#
# TODO: there is no LuckPerms config-file template in this repo. If you need one,
# take it from a disposable server's generated plugins/LuckPerms/ directory,
# strip every player-specific grant, and add it here.
#
# Server-wide sorting defaults are set with the ChestCleaner admin command, not
# LuckPerms:
#   /sortingadmin clickSort false
#   /sortingadmin autosort false
#   /sortingadmin sortingSound active true
#   /sortingadmin chatNotification true
#   /sortingadmin refill false
#
# Keep click-sort, auto-sort overrides and /cleaninventory away from ordinary
# players:
#   /lp group default permission unset chestcleaner.clicksort
#   /lp group default permission unset chestcleaner.cmd.sortingconfig.clicksort
#   /lp group default permission unset chestcleaner.cmd.cleaninventory.sort
#
# For ChestCleaner, the default group gets stock brush-use permissions only.
# Never op a friend to "make something work": grant the minimal permission.

# EssentialsX Core: no extra default-group grants by default. Explicitly deny its
# default-true access for the default group (see docs/nicknames-and-permissions.md):
#   /lp group default permission set essentials.back.onteleport false
#   /lp group default permission set essentials.teleport.cooldown.bypass.back false
#   /lp group default permission set essentials.teleport.cooldown.bypass.tpa false
# If the owner chooses to allow self-service nicknames, grant only:
#   /lp group default permission set essentials.nick true
# Keep nick-for-others and all moderation/admin permissions ungranted to default.
# No moderator group is created by this template. If needed, grant only:
#   essentials.kick, essentials.mute, essentials.tempban, essentials.unban
