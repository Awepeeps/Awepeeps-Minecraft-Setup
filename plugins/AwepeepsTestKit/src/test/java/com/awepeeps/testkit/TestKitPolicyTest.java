package com.awepeeps.testkit;

import static org.junit.jupiter.api.Assertions.*;

import java.time.Instant;
import java.util.Set;
import java.util.stream.Collectors;
import org.bukkit.Material;
import org.junit.jupiter.api.Test;

class TestKitPolicyTest {
  @Test
  void featureGateFailsClosedAndExpiresAtLocalDayBoundary() {
    assertTrue(TestKitPolicy.isActive(
        true, "2026-11-01", "America/New_York", Instant.parse("2026-11-02T04:59:59Z")));
    assertFalse(TestKitPolicy.isActive(
        true, "2026-11-01", "America/New_York", Instant.parse("2026-11-02T05:00:00Z")));
    assertFalse(TestKitPolicy.isActive(
        false, "2026-11-01", "America/New_York", Instant.parse("2026-11-01T12:00:00Z")));
    assertFalse(TestKitPolicy.isActive(
        true, "", "UTC", Instant.parse("2026-11-01T12:00:00Z")));
    assertFalse(TestKitPolicy.isActive(
        true, "not-a-date", "UTC", Instant.parse("2026-11-01T12:00:00Z")));
    assertFalse(TestKitPolicy.isActive(
        true, "2026-11-01", "invalid-zone", Instant.parse("2026-11-01T12:00:00Z")));
  }

  @Test
  void chestSearchRespectsSpawnProtectionAndBoundedWorldHeight() {
    assertFalse(TestKitPolicy.outsideProtection(16, 0, 16));
    assertFalse(TestKitPolicy.outsideProtection(16, 16, 16));
    assertTrue(TestKitPolicy.outsideProtection(17, 0, 16));
    assertEquals(18, TestKitPolicy.searchRadius(16, 8));
    assertEquals(64, TestKitPolicy.searchRadius(62, 8));
    assertEquals(-1, TestKitPolicy.searchRadius(64, 8));
    assertEquals(65, TestKitPolicy.surfacePlacementY(64, 64, -64, 320));
    assertNull(TestKitPolicy.surfacePlacementY(80, 64, -64, 320));
    assertNull(TestKitPolicy.surfacePlacementY(254, 240, 0, 256));
  }

  @Test
  void placementRequiresSafeUnoccupiedGroundAndChestClearance() {
    assertTrue(TestKitPolicy.safeFloor(true, false, false, false));
    assertFalse(TestKitPolicy.safeFloor(false, false, false, false));
    assertFalse(TestKitPolicy.safeFloor(true, true, false, false));
    assertFalse(TestKitPolicy.safeFloor(true, false, true, false));
    assertFalse(TestKitPolicy.safeFloor(true, false, false, true));
    assertTrue(TestKitPolicy.safePlacement(true, true, true, false));
    assertFalse(TestKitPolicy.safePlacement(false, true, true, false));
    assertFalse(TestKitPolicy.safePlacement(true, false, true, false));
    assertFalse(TestKitPolicy.safePlacement(true, true, false, false));
    assertFalse(TestKitPolicy.safePlacement(true, true, true, true));
  }

  @Test
  void starterKitContainsRequestedItemsAndFitsOneChest() {
    Set<Material> materials = TestKitContents.stacks().stream()
        .map(TestKitContents.Stack::material).collect(Collectors.toSet());
    assertTrue(materials.containsAll(Set.of(
        Material.LODESTONE, Material.RED_BED, Material.COMPASS, Material.BRUSH,
        Material.TORCH, Material.WHITE_BANNER, Material.RED_BANNER, Material.ANVIL,
        Material.DIAMOND_SWORD, Material.DIAMOND_PICKAXE, Material.DIAMOND_AXE,
        Material.DIAMOND_SHOVEL, Material.DIAMOND_HOE, Material.DIAMOND_HELMET,
        Material.DIAMOND_CHESTPLATE, Material.DIAMOND_LEGGINGS, Material.DIAMOND_BOOTS,
        Material.COOKED_BEEF)));
    assertEquals(99, TestKitContents.stacks().stream()
        .filter(stack -> stack.material() == Material.COOKED_BEEF)
        .mapToInt(TestKitContents.Stack::amount).sum());
    int occupiedSlots = TestKitContents.stacks().stream()
        .mapToInt(stack -> (stack.amount() + 63) / 64).sum();
    assertTrue(occupiedSlots <= 27, "The complete kit must fit a single chest");
  }
}
