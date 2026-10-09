// subsys [pengine]
//
// Copyright (C) 2004-2006 Jasmine Langridge, ja-reiko@users.sourceforge.net
// License: GPL version 2 (see included gpl.txt)
module pengine.subsys;

import pengine.vmath;
import pengine.app : PApp;

/// A PResource basically is just a name
class PResource
{
  protected string name;

  final string getName() const { return name; }
}

/// A list of resources that can be searched by name and cleared as a whole.
/// Resources holding GPU/audio handles implement `unload()`, which `clear()` calls.
struct PResourceList(T)
{
  private T[] reslist;

  void clear()
  {
    foreach (res; reslist) {
      static if (__traits(hasMember, T, "unload"))
        res.unload();
    }
    reslist = null;
  }

  T add(T newresource)
  {
    reslist ~= newresource;
    return newresource;
  }

  T find(string name)
  {
    foreach (res; reslist)
      if (name == res.getName())
        return res;
    return null;
  }
}

class PSubsystem
{
  protected PApp app;

  this(PApp parentApp) { app = parentApp; }

  void shutdown() { }

  void tick(float delta, const ref vec3f eyepos, const ref mat44f eyeori, const ref vec3f eyevel)
  {
  }
}
