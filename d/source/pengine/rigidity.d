// rigidity [pengine]
//
// Copyright (C) 2020 Martin Scherer
// License: GPL version 2 (see included gpl.txt)
module pengine.rigidity;

import pengine.cutil;
import pengine.util;
import pengine.xml;

/// Loads rigidity.xml and stores sprite -> rigidity value pairs.
final class PRigidity
{
  private float[string] rigiditymap;

  this()
  {
    auto xmlfile = new XMLDocument();
    XMLElement rootelem = PUtil.loadRootElement(xmlfile, "rigidity.xml", "rigiditymap");

    if (rootelem is null) {
      PUtil.outLog("Could not load file \"rigidity.xml\".");
      return;
    }

    for (XMLElement walk = rootelem.FirstChildElement(); walk !is null; walk = walk.NextSiblingElement()) {
      if (walk.Value() == "rigidity") {
        string sprite = walk.Attribute("sprite");
        if (sprite is null)
          continue;

        string val = walk.Attribute("value");
        if (val is null)
          continue;

        rigiditymap[sprite] = cast(float) atof(val);
      }
    }
  }

  /// Returns the rigidity value of a sprite (path to the sprite file).
  float getRigidity(string sprite) const
  {
    auto p = sprite in rigiditymap;
    if (p is null)
      return 0.0f;
    return *p;
  }
}
