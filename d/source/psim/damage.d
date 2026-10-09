// damage [psim]
// D port of damage.h / damage.cpp. License: GPL version 2
module psim.damage;

import pengine.vmath;
import psim.psim : PReferenceFrame;
import psim.vehicle : vehicle_clip_s;

/// Damage indicator in racing UI
struct PDamage
{
  enum DamageSide
  {
    DamageFrontLeft = 0,
    DamageFrontRight,
    DamageRearLeft,
    DamageRearRight,
    DamageSideSize
  }

  private float[DamageSide.DamageSideSize] damage;
  private vec3f[DamageSide.DamageSideSize] center;
  private bool[DamageSide.DamageSideSize] flash;

  void setClip(const vehicle_clip_s[] clip)
  {
    vec3f clipmin = vec3f(float.max, float.max, float.max);
    vec3f clipmax = vec3f(-float.max, -float.max, -float.max);

    foreach (ref c; clip) {
      if (c.pt.x < clipmin.x) clipmin.x = c.pt.x;
      if (c.pt.y < clipmin.y) clipmin.y = c.pt.y;
      if (c.pt.z < clipmin.z) clipmin.z = c.pt.z;

      if (c.pt.x > clipmax.x) clipmax.x = c.pt.x;
      if (c.pt.y > clipmax.y) clipmax.y = c.pt.y;
      if (c.pt.z > clipmax.z) clipmax.z = c.pt.z;
    }
    for (int i = 0; i < DamageSide.DamageSideSize; ++i) {
      vec3f position = vec3f.zero();

      switch (i) {
        case DamageSide.DamageFrontLeft:
          position.x = clipmin.x;
          position.y = clipmax.y;
          position.z = 0.5f * clipmax.z;
          break;
        case DamageSide.DamageFrontRight:
          position.x = clipmax.x;
          position.y = clipmax.y;
          position.z = 0.5f * clipmax.z;
          break;
        case DamageSide.DamageRearLeft:
          position.x = clipmin.x;
          position.y = clipmin.y;
          position.z = 0.5f * clipmax.z;
          break;
        case DamageSide.DamageRearRight:
          position.x = clipmax.x;
          position.y = clipmin.y;
          position.z = 0.5f * clipmax.z;
          break;
        default:
          break;
      }

      center[i] = position;
      damage[i] = 0.0f;
      flash[i] = false;
    }
  }

  void addDamage(in vec3f crashpoint, float increment, PReferenceFrame ref_world)
  {
    float minimum = float.max;
    DamageSide damageside = DamageSide.DamageSideSize;

    for (int i = 0; i < DamageSide.DamageSideSize; ++i) {
      vec3f delta = crashpoint - ref_world.getLocToWorldPoint(center[i]);
      float distance = delta.length();

      if (distance < minimum) {
        minimum = distance;
        damageside = cast(DamageSide) i;
      }
    }
    if (damageside < DamageSide.DamageSideSize) {
      damage[damageside] += increment;
      flash[damageside] = true;
    }
  }

  float getDamage(DamageSide damageside)
  {
    if (damageside >= DamageSide.DamageSideSize)
      return 0.0f;
    if (flash[damageside]) {
      flash[damageside] = false;
      return -1.0;
    }
    return damage[damageside];
  }

  float getDamage(in vec3f position)
  {
    float minimum = float.max;
    DamageSide damageside = DamageSide.DamageSideSize;

    for (int i = 0; i < DamageSide.DamageSideSize; ++i) {
      vec3f delta = position - center[i];
      float distance = delta.length();

      if (distance < minimum) {
        minimum = distance;
        damageside = cast(DamageSide) i;
      }
    }
    if (damageside >= DamageSide.DamageSideSize)
      return 0.0f;
    if (damage[damageside] > 1.0f)
      return 1.0f;
    return damage[damageside];
  }
}
