/*
 * Nightscout T-Display - Copyright (C) 2026 erikpendragon
 * Licensed under the GNU General Public License v3 or later. See LICENSE.
 */
#pragma once
#include <cstdio>
#include <string>

// True when `a` is a strictly newer dotted-numeric version than `b`.
// Missing components count as zero, so "1.1" beats "1.0.9".
inline bool version_is_newer(const std::string &a, const std::string &b) {
  if (a.empty() || b.empty()) return false;
  int av[3] = {0, 0, 0}, bv[3] = {0, 0, 0};
  std::sscanf(a.c_str(), "%d.%d.%d", &av[0], &av[1], &av[2]);
  std::sscanf(b.c_str(), "%d.%d.%d", &bv[0], &bv[1], &bv[2]);
  for (int i = 0; i < 3; i++)
    if (av[i] != bv[i]) return av[i] > bv[i];
  return false;
}
