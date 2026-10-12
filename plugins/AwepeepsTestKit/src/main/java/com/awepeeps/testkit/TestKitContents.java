package com.awepeeps.testkit;

import java.util.List;
import org.bukkit.Material;
import org.bukkit.inventory.ItemStack;

final class TestKitContents {
  private static final List<Stack> STACKS = List.of(
      new Stack(Material.LODESTONE, 8),
      new Stack(Material.RED_BED, 1),
      new Stack(Material.COMPASS, 16),
      new Stack(Material.BRUSH, 1),
      new Stack(Material.OAK_LOG, 64),
      new Stack(Material.OAK_PLANKS, 64),
      new Stack(Material.COBBLESTONE, 64),
      new Stack(Material.CRAFTING_TABLE, 1),
      new Stack(Material.STICK, 64),
      new Stack(Material.TORCH, 64),
      new Stack(Material.DIAMOND, 16),
      new Stack(Material.IRON_INGOT, 64),
      new Stack(Material.WHITE_BANNER, 8),
      new Stack(Material.RED_BANNER, 8),
      new Stack(Material.ANVIL, 1),
      new Stack(Material.DIAMOND_SWORD, 1),
      new Stack(Material.DIAMOND_PICKAXE, 1),
      new Stack(Material.DIAMOND_AXE, 1),
      new Stack(Material.DIAMOND_SHOVEL, 1),
      new Stack(Material.DIAMOND_HOE, 1),
      new Stack(Material.DIAMOND_HELMET, 1),
      new Stack(Material.DIAMOND_CHESTPLATE, 1),
      new Stack(Material.DIAMOND_LEGGINGS, 1),
      new Stack(Material.DIAMOND_BOOTS, 1),
      new Stack(Material.COOKED_BEEF, 99));

  private TestKitContents() {}

  static List<Stack> stacks() {
    return STACKS;
  }

  static void fill(org.bukkit.inventory.Inventory inventory) {
    for (Stack stack : STACKS) {
      var leftovers = inventory.addItem(new ItemStack(stack.material(), stack.amount()));
      if (!leftovers.isEmpty()) {
        throw new IllegalStateException("The starter kit does not fit in one chest.");
      }
    }
  }

  record Stack(Material material, int amount) {}
}
