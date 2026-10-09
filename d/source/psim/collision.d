// collision [psim]
// D port of collision.h / collision.cpp. License: GPL version 2
module psim.collision;

import pengine.vmath;
import pengine.terrain : PTerrainFoliage;
import psim.psim : PReferenceFrame;
import psim.vehicle : vehicle_clip_s;

/// Handling of collisions with world objects
class PCollision
{
  private vec3f boxmin, boxmax, crashpoint;

  /// Calculates AABB box from clip positions in world coordinates
  this(const vehicle_clip_s[] clip, PReferenceFrame ref_world)
  {
    crashpoint = vec3f.zero();
    boxmin = vec3f(float.max, float.max, float.max);
    boxmax = vec3f(-float.max, -float.max, -float.max);

    foreach (ref c; clip) {
      vec3f lcliptop = c.pt;
      vec3f lclipbottom = lcliptop;

      lclipbottom.z = 0.0f;
      vec3f wcliptop = ref_world.getLocToWorldPoint(lcliptop);
      vec3f wclipbottom = ref_world.getLocToWorldPoint(lclipbottom);

      calcmin(wcliptop);
      calcmin(wclipbottom);
      calcmax(wcliptop);
      calcmax(wclipbottom);
    }
  }

  /// Returns objects inside AABB box
  PTerrainFoliage[] checkContact(const(PTerrainFoliage)[] foliage) const
  {
    PTerrainFoliage[] contact;

    foreach (ref f; foliage) {
      const foliagemin = f.pos;
      vec3f foliagemax = f.pos;

      foliagemax.z += f.scale;
      if (foliagemin.x <= boxmax.x && foliagemax.x >= boxmin.x &&
          foliagemin.y <= boxmax.y && foliagemax.y >= boxmin.y &&
          foliagemin.z <= boxmax.z && foliagemax.z >= boxmin.z) {
        contact ~= f;
      }
    }
    return contact;
  }

  /// Prevents vehicle to be stuck with world objects
  bool towardsContact(in vec3f body_, in vec3f contact, in vec3f diff) const
  {
    vec3f dist1 = body_ - contact;
    vec3f dist2 = body_ + diff - contact;
    return dist1.length() > dist2.length();
  }

  /// Calculate position to apply crash force
  vec3f getCrashPoint(in vec3f body_, in PTerrainFoliage foliage)
  {
    // Either take vehicle center Z position or highest point of object
    crashpoint = foliage.pos;
    crashpoint.z = MIN(body_.z, foliage.pos.z + foliage.scale);
    return crashpoint;
  }

  private void calcmin(in vec3f a)
  {
    boxmin.x = MIN(boxmin.x, a.x);
    boxmin.y = MIN(boxmin.y, a.y);
    boxmin.z = MIN(boxmin.z, a.z);
  }

  private void calcmax(in vec3f a)
  {
    boxmax.x = MAX(boxmax.x, a.x);
    boxmax.y = MAX(boxmax.y, a.y);
    boxmax.z = MAX(boxmax.z, a.z);
  }
}
