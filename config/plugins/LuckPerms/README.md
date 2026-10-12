# LuckPerms basics (no config-file template)
# Destination on the server: <instance-data>/plugins/LuckPerms/ (generated)
#
# The private deployment repository does not template LuckPerms configuration
# files; it records policy as console commands. Keep the same approach here:
# grant the minimal permissions and keep click-sort/auto-sort off by default.
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
# The default group gets stock brush-use permissions only. Never op a friend to
# "make something work": grant the minimal permission instead.
