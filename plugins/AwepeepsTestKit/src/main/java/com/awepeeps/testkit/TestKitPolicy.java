package com.awepeeps.testkit;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;

final class TestKitPolicy {
  static final int MAX_SEARCH_RADIUS = 64;
  static final int MAX_VERTICAL_SEARCH = 16;

  private TestKitPolicy() {}

  static boolean isActive(boolean enabled, String expiryDate, String timezone, Instant now) {
    if (!enabled || expiryDate == null || timezone == null) return false;
    try {
      LocalDate expiry = LocalDate.parse(expiryDate.trim());
      ZoneId zone = ZoneId.of(timezone.trim());
      return now.isBefore(expiry.plusDays(1).atStartOfDay(zone).toInstant());
    } catch (java.time.DateTimeException | ArithmeticException error) {
      return false;
    }
  }

  static boolean outsideProtection(int deltaX, int deltaZ, int protectionRadius) {
    return protectionRadius <= 0
        || Math.max(Math.abs(deltaX), Math.abs(deltaZ)) > protectionRadius;
  }

  static int searchRadius(int protectionRadius, int preferredRadius) {
    if (protectionRadius >= MAX_SEARCH_RADIUS) return -1;
    return Math.min(MAX_SEARCH_RADIUS,
        Math.max(preferredRadius, Math.max(0, protectionRadius) + 2));
  }

  static Integer surfacePlacementY(int surfaceBlockY, int spawnBlockY, int minHeight, int maxHeight) {
    int placementY = surfaceBlockY + 1;
    if (Math.abs((long) placementY - spawnBlockY) > MAX_VERTICAL_SEARCH
        || placementY <= minHeight || placementY + 1 >= maxHeight) return null;
    return placementY;
  }

  static boolean safeFloor(boolean solid, boolean liquid, boolean leaves, boolean hazardous) {
    return solid && !liquid && !leaves && !hazardous;
  }

  static boolean safePlacement(
      boolean airAtChest, boolean airAbove, boolean insideWorldBorder, boolean nextToChest) {
    return airAtChest && airAbove && insideWorldBorder && !nextToChest;
  }
}
