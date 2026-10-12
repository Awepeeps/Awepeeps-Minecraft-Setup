package com.awepeeps.testkit;

import org.bukkit.plugin.java.JavaPlugin;

public final class AwepeepsTestKit extends JavaPlugin {
  @Override
  public void onEnable() {
    saveDefaultConfig();
    TestKitManager manager = new TestKitManager(this);
    getServer().getScheduler().runTaskTimer(this, manager::tick, 1L, 100L);
  }
}
