// terrain [pengine]
//
// Copyright 2004-2006 Jasmine Langridge, jas@jareiko.net
// License: GPL version 2 (see included gpl.txt)
//
// Heightmap terrain with tiles, foliage and road signs.
module pengine.terrain;

import core.stdc.stdlib : srand, rand;
import std.conv : to;
import std.math : cos, sin, fabs, lround;
import std.array : split;

import bindings.gl;
import pengine.cutil;
import pengine.image;
import pengine.render : PVert_tv;
import pengine.rigidity;
import pengine.texture;
import pengine.util;
import pengine.vbuffer;
import pengine.vmath;
import pengine.xml;

struct PTerrainFoliageBand
{
  float middle = 0, range = 0;
  float density = 0;
  int trycount;
  float scale = 0;

  float scalemin = 0;
  float scalemax = 0;

  PTexture sprite_tex;
  int sprite_count;
}

struct PTerrainFoliage
{
  vec3f pos;
  float ang = 0;
  float scale = 0;
  float rigidity = 0;
}

final class PTerrainFoliageSet
{
  PTerrainFoliage[] inst;

  PVBuffer[2] buff;
  int numvert, numelem;

  this()
  {
    buff[0] = new PVBuffer();
    buff[1] = new PVBuffer();
  }
}

alias PRoadSignSet = PTerrainFoliageSet;

final class PTerrainTile
{
  int posx, posy;
  int lru_counter;

  PVBuffer vert;
  int numverts;

  PTexture tex;

  vec3f mins, maxs; // AABB

  PTerrainFoliageSet[] foliage;
  PRoadSignSet[] roadsignset;
  // Straight vector for rapid search by collision detection
  PTerrainFoliage[] straight;

  this()
  {
    vert = new PVBuffer();
    tex = new PTexture();
  }

  void unload()
  {
    vert.unload();
    tex.unload();
    foreach (f; foliage) { f.buff[0].unload(); f.buff[1].unload(); }
    foreach (f; roadsignset) { f.buff[0].unload(); f.buff[1].unload(); }
  }
}

/// Loads road information.
struct RoadMap
{
  private bool[] bitmap;
  private int bx;
  private int by;

  bool load(in PImage img)
  {
    if (img.getData().length == 0)
      return false;

    bx = img.getcx();
    by = img.getcy();
    bitmap = null;
    bitmap.reserve(img.getcx() * img.getcy());

    const(ubyte)[] d = img.getData();
    const cc = img.getcc();

    for (size_t pb = 0; pb < d.length; pb += cc) {
      bool is_road = true;

      for (int i = 0; i < cc; ++i)
        if (d[pb + i] != 0xFF) { // the road is white
          is_road = false;
          break;
        }

      bitmap ~= is_road;
    }

    return true;
  }

  bool is_loaded() const { return bitmap.length != 0; }

  /// Decides if provided point is on the road. Returns true if no roadmap was loaded.
  bool isOnRoad(float px, float py, float ms) const
  {
    if (bitmap.length == 0)
      return true;

    if (px >= ms) {
      do
        px -= ms;
      while (px > ms);
    } else if (px < 0) {
      do
        px += ms;
      while (px < 0);
    }

    if (py >= ms) {
      do
        py -= ms;
      while (py > ms);
    } else if (py < 0) {
      do
        py += ms;
      while (py < 0);
    }

    long x = lround(px * bx / ms);
    long y = lround(py * by / ms);

    CLAMP_UPPER(x, bx - 1);
    CLAMP_UPPER(y, by - 1);
    return bitmap[cast(size_t)(y * bx + x)];
  }
}

struct road_sign
{
  PTexture sprite = null;
  float scale = 1.0f;
  float x = 0.0f;
  float y = 0.0f;
  float deg = 0.0f;
  int sprite_count = 1;
}

private __gshared PRamFile ramfile1, ramfile2;

enum HMULT = 1.0f;
enum VMULT = 2.0f;

final class PTerrain
{
  protected bool loaded;

  protected int tilesize, tilecount, totsize, totmask, totsizesq;

  protected float scale_hz, scale_vt, scale_hz_inv, scale_vt_inv, scale_tile_inv;

  protected int cmaptotsize, cmaptilesize, cmaptotmask;

  protected float[] hmap;

  // color map
  PImage cmap;
  // terrain map
  PImage tmap;
  // road map
  RoadMap rmap;

  protected float[] fmap;
  protected PTerrainFoliageBand[] foliageband;
  protected road_sign[] roadsigns;

  protected PTerrainTile[] tile;

  // tiles share index buffers
  protected PVBuffer ind;
  protected int numinds;

  protected PTexture tex_hud_map;

  // Rigidity map for foliage and road signs
  private PRigidity rigidity;

  struct ContactInfo
  {
    vec3f pos;
    vec3f normal;
  }

  protected float getInterp(float x, float y, const(float)[] data)
  {
    x *= scale_hz_inv;
    int xi = cast(int) x;
    if (x < 0.0) xi--;
    x -= cast(float) xi;
    int xiw = xi & totmask, xiw2 = (xiw + 1) & totmask;

    y *= scale_hz_inv;
    int yi = cast(int) y;
    if (y < 0.0) yi--;
    y -= cast(float) yi;
    int yiw = yi & totmask, yiw2 = (yiw + 1) & totmask;

    const cx = totsize;

    float xv1, xv2;
    if (y > 0.0) {
      if (y < 1.0) {
        if (x < y) {
          xv1 = data[yiw * cx + xiw];
          xv2 = INTERP(data[yiw2 * cx + xiw], data[yiw2 * cx + xiw2], x / y);
        } else {
          xv1 = INTERP(data[yiw * cx + xiw], data[yiw * cx + xiw2], (x - y) / (1.0 - y));
          xv2 = data[yiw2 * cx + xiw2];
        }
        return INTERP(xv1, xv2, y);
      } else {
        return INTERP(data[yiw2 * cx + xiw], data[yiw2 * cx + xiw2], x);
      }
    } else {
      return INTERP(data[yiw * cx + xiw], data[yiw * cx + xiw2], x);
    }
  }

  ~this()
  {
    // GL resources are released explicitly through unload()
  }

  void unload()
  {
    loaded = false;

    foreach (t; tile)
      t.unload();
    tile = null;

    hmap = null;
  }

  this(XMLElement element, string filepath, PSSTexture ssTexture,
       PRigidity rigidity, bool cfgFoliage, bool cfgRoadsigns)
  {
    this.rigidity = rigidity;
    loaded = false;
    unload();

    string heightmap, colormap, terrainmap, roadmap, foliagemap, hudmap;

    scale_hz = 1.0f;
    scale_vt = 1.0f;

    string val;

    val = element.Attribute("tilesize");
    if (val !is null) tilesize = atoi(val);

    val = element.Attribute("horizontalscale");
    if (val !is null) scale_hz = cast(float) atof(val);

    val = element.Attribute("verticalscale");
    if (val !is null) scale_vt = cast(float) atof(val);

    val = element.Attribute("heightmap");
    if (val !is null) heightmap = val;

    val = element.Attribute("colormap");
    if (val !is null) colormap = val;

    val = element.Attribute("terrainmap");
    if (val !is null) terrainmap = val;

    val = element.Attribute("roadmap");
    if (val !is null) roadmap = val;

    val = element.Attribute("foliagemap");
    if (val !is null && cfgFoliage) foliagemap = val;

    val = element.Attribute("hudmap");
    if (val !is null) hudmap = val;

    XMLElement node = element.FirstChildElement("blurfilter");
    float[][] blurfilter;

    if (node !is null) {
      for (XMLElement walk = node.FirstChildElement("row"); walk !is null; walk = walk.NextSiblingElement("row")) {
        string srow = walk.Attribute("data");

        if (srow is null)
          continue;

        float[] row;
        foreach (w; srow.split()) {
          try {
            row ~= to!float(w);
          } catch (Exception) {
            break;
          }
        }

        blurfilter ~= row;
      }
    } else {
      blurfilter = [
        [0.03f, 0.12f, 0.03f],
        [0.12f, 0.40f, 0.12f],
        [0.03f, 0.12f, 0.03f]
      ];
    }

    for (XMLElement walk = element.FirstChildElement(); walk !is null; walk = walk.NextSiblingElement()) {
      if (walk.Value() == "roadsign" && cfgRoadsigns) {
        road_sign temprs;

        val = walk.Attribute("sprite");
        if (val !is null)
          temprs.sprite = ssTexture.loadTexture(PUtil.assemblePath(val, filepath));

        val = walk.Attribute("scale");
        if (val !is null)
          temprs.scale = cast(float) atof(val);

        val = walk.Attribute("spritecount");
        if (val !is null)
          temprs.sprite_count = atoi(val);

        for (XMLElement walk2 = walk.FirstChildElement(); walk2 !is null; walk2 = walk2.NextSiblingElement()) {
          if (walk2.Value() == "location") {
            float deg = 0;

            val = walk2.Attribute("oridegrees");
            if (val !is null)
              deg = RADIANS(atof(val));

            val = walk2.Attribute("coords");
            if (val !is null) {
              float x, y;

              if (sscanf(val, "%f, %f", &x, &y) == 2) {
                temprs.x = x;
                temprs.y = y;
                temprs.deg = deg;

                if (temprs.sprite !is null)
                  roadsigns ~= temprs;
              }
            }
          }
        }
      } else if (walk.Value() == "foliageband" && cfgFoliage) {
        PTerrainFoliageBand tfb;
        tfb.middle = 0.5f;
        tfb.range = 0.5f;
        tfb.density = 1.0f;
        tfb.scale = 1.0f;
        tfb.scalemin = 1.0f;
        tfb.scalemax = 1.4f;
        tfb.sprite_tex = null;
        tfb.sprite_count = 1;

        val = walk.Attribute("middle");
        if (val !is null) tfb.middle = cast(float) atof(val);

        val = walk.Attribute("range");
        if (val !is null) tfb.range = cast(float) atof(val);

        val = walk.Attribute("density");
        if (val !is null) tfb.density = cast(float) atof(val);

        val = walk.Attribute("scale");
        if (val !is null) tfb.scale = cast(float) atof(val);

        val = walk.Attribute("scalemin");
        if (val !is null) tfb.scalemin = cast(float) atof(val);

        val = walk.Attribute("scalemax");
        if (val !is null) tfb.scalemax = cast(float) atof(val);

        val = walk.Attribute("sprite");
        if (val !is null) tfb.sprite_tex = ssTexture.loadTexture(PUtil.assemblePath(val, filepath));

        val = walk.Attribute("spritecount");
        if (val !is null) tfb.sprite_count = atoi(val);

        foliageband ~= tfb;
      }
    }

    if (heightmap.length == 0) {
      throw MakePException("Load failed: terrain has no heightmap");
    }

    if (colormap.length == 0) {
      throw MakePException("Load failed: terrain has no colormap");
    }

    if (tilesize != (tilesize & (-tilesize)) || tilesize < 4) {
      throw MakePException("Load failed: tile size not power of two dimension, or too small");
    }

    if (scale_hz <= 0.0 || scale_vt == 0.0) {
      throw MakePException("Load failed: invalid scale value");
    }

    scale_hz_inv = 1.0 / scale_hz;
    scale_vt_inv = 1.0 / scale_vt;
    scale_tile_inv = scale_hz_inv / cast(float) tilesize;

    PImage img;
    try {
      img.load(PUtil.assemblePath(heightmap, filepath));
    } catch (Exception e) {
      PUtil.outLog("Load failed: couldn't open heightmap \"", heightmap, "\"");
      throw e;
    }

    totsize = img.getcx();
    if (totsize != img.getcy() || totsize != (totsize & (-totsize)) || totsize < 16) {
      throw MakePException("Load failed: heightmap not square, or not power of two dimension, or too small");
    }

    totsizesq = totsize * totsize;

    if (tilesize > totsize) tilesize = totsize;

    tilecount = totsize / tilesize;
    totmask = totsize - 1;

    hmap = new float[totsizesq];

    if (img.getcc() != 1) {
      if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
        PUtil.outLog("Warning: heightmap is not single channel");
    }

    {
      const cc = img.getcc();
      const(ubyte)[] dat = img.getData();

      for (int y = 0; y < totsize; ++y) {
        for (int x = 0; x < totsize; ++x) {
          float accum = 0.0;
          for (int yi = 0; yi < cast(int) blurfilter.length; ++yi) {
            for (int xi = 0; xi < cast(int) blurfilter[yi].length; ++xi) {
              accum += cast(float) dat[
                (((y + yi - cast(int)((blurfilter.length - 1) / 2)) & totmask) * totsize +
                 ((x + xi - cast(int)((blurfilter[yi].length - 1) / 2)) & totmask)) * cc] * blurfilter[yi][xi];
            }
          }
          hmap[y * totsize + x] = accum * scale_vt;
        }
      }
    }

    img.unload();

    try {
      cmap.load(PUtil.assemblePath(colormap, filepath));
    } catch (Exception e) {
      PUtil.outLog("Load failed: couldn't open colormap \"", colormap, "\"");
      throw e;
    }

    cmaptotsize = cmap.getcx();
    if (cmaptotsize != cmap.getcy() || cmaptotsize != (cmaptotsize & (-cmaptotsize)) || cmaptotsize < tilecount) {
      throw MakePException("Load failed: colormap not square, or not power of two dimension, or too small");
    }

    cmaptilesize = cmaptotsize / tilecount;
    cmaptotmask = cmaptotsize - 1;

    // load terrain map image
    try {
      if (terrainmap.length != 0)
        tmap.load(PUtil.assemblePath(terrainmap, filepath));
    } catch (Exception e) {
      PUtil.outLog("Load failed: couldn't open terrainmap \"", terrainmap, "\"");
      throw e;
    }

    if (tmap.getData().length != 0 && tmap.getcx() != tmap.getcy())
      throw MakePException("Load failed: terrainmap not square");

    PImage rmap_img;

    // load road map image
    try {
      if (roadmap.length != 0)
        rmap_img.load(PUtil.assemblePath(roadmap, filepath));
    } catch (Exception e) {
      PUtil.outLog("Load failed: couldn't open roadmap \"", roadmap, "\"");
      throw e;
    }

    if (rmap_img.getData().length != 0) {
      if (rmap_img.getcx() != rmap_img.getcy())
        throw MakePException("Load failed: roadmap not square");
      else if (!rmap.load(rmap_img))
        throw MakePException("Load failed: bad roadmap image");
    }

    // calculate foliage try counts for tile size
    for (size_t b = 0; b < foliageband.length; b++) {
      foliageband[b].trycount =
        cast(int)(foliageband[b].density * cast(float) totsizesq * scale_hz * scale_hz);
    }

    // load foliage map
    fmap = new float[totsizesq];
    fmap[] = 0.0f;

    if (foliagemap.length != 0) {
      try {
        img.load(PUtil.assemblePath(foliagemap, filepath));
      } catch (Exception e) {
        PUtil.outLog("Load failed: couldn't open foliage map \"", foliagemap, "\"");
        throw e;
      }

      if (totsize != img.getcy() || totsize != img.getcx()) {
        throw MakePException("Load failed: foliage map size doesn't match heightmap");
      }

      const cc = img.getcc();
      const(ubyte)[] dat = img.getData();

      if (cc != 1) {
        if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
          PUtil.outLog("Warning: foliage map is not single channel");
      }

      for (int i = 0; i < totsizesq; i++) {
        fmap[i] = cast(float) dat[i * cc] / 255.0f;
      }
    }

    // load hud map
    tex_hud_map = null;

    if (hudmap.length != 0) {
      tex_hud_map = ssTexture.loadTexture(PUtil.assemblePath(hudmap, filepath));
    }

    // prepare shared index buffers
    int tilesizep1 = tilesize + 1;

    numinds = 0;

    if (ramfile1 is null) {
      ramfile1 = new PRamFile();
      ramfile2 = new PRamFile();
    }

    auto ramfile = new PRamFile();
    ushort index;
    for (int y = 0; y < tilesize; ++y) {
      int add1 = (y + 1) * tilesizep1;
      int add2 = (y + 0) * tilesizep1;
      if (y > 0) {
        index = cast(ushort)(0 + add1);
        ramfile.write(&index, ushort.sizeof);
        numinds += 1;
      }
      for (int x = 0; x < tilesizep1; ++x) {
        index = cast(ushort)(x + add1);
        ramfile.write(&index, ushort.sizeof);
        index = cast(ushort)(x + add2);
        ramfile.write(&index, ushort.sizeof);
        numinds += 2;
      }
      if (y + 1 < tilesize) {
        ramfile.write(&index, ushort.sizeof);
        numinds += 1;
      }
    }

    ind = new PVBuffer();
    ind.create(ramfile.getSize(), PVBuffer.IndexContent, PVBuffer.StaticUsage, ramfile.getData());
    ramfile.clear();

    loaded = true;
  }

  /// Gets terrain tile for each world position.
  private const(PTerrainTile) getTileAtPos(in vec3f pos) const
  {
    int tilex = cast(int)(pos.x * scale_tile_inv);
    int tiley = cast(int)(pos.y * scale_tile_inv);

    if (pos.x < 0.0)
      --tilex;
    if (pos.y < 0.0)
      --tiley;

    foreach (t; tile) {
      if (t.posx == tilex && t.posy == tiley)
        return t;
    }
    return null;
  }

  /// Gets the objects on the tile at a world position (null if the tile isn't loaded).
  const(PTerrainFoliage)[] getFoliageAtPos(in vec3f pos) const
  {
    const t = getTileAtPos(pos);

    if (t !is null) {
      return t.straight;
    }
    return null;
  }

  protected PTerrainTile getTile(int tilex, int tiley)
  {
    // find the least recently used tile while searching for x,y
    int best_lru = 0, unused = 0;
    PTerrainTile tileptr = null;
    foreach (t; tile) {
      if (t.posx == tilex && t.posy == tiley) {
        t.lru_counter = 0;
        return t;
      }

      if (best_lru < t.lru_counter) {
        best_lru = t.lru_counter;
        tileptr = t;
      }

      if (t.lru_counter > 1) ++unused;
    }

    // if there aren't enough unused tiles, create a new one
    if (unused < 10 || best_lru <= 1) {
      tileptr = new PTerrainTile();
      tile ~= tileptr;
    }

    tileptr.posx = tilex;
    tileptr.posy = tiley;
    tileptr.lru_counter = 0;

    tileptr.mins = vec3f(cast(float) tilex * scale_hz, cast(float) tiley * scale_hz, 1000000000.0);
    tileptr.maxs = vec3f(cast(float)(tilex + 1) * scale_hz, cast(float)(tiley + 1) * scale_hz, -1000000000.0);

    ramfile1.clear();

    int tileoffsety = tiley * tilesize;
    int tileoffsetx = tilex * tilesize;
    int tilesizep1 = tilesize + 1;
    for (int y = 0; y < tilesizep1; ++y) {
      int posy = tileoffsety + y;
      int sampley = posy & totmask;
      for (int x = 0; x < tilesizep1; ++x) {
        int posx = tileoffsetx + x;
        int samplex = posx & totmask;
        vec3f vert = vec3f(
          cast(float) posx * scale_hz,
          cast(float) posy * scale_hz,
          cast(float) hmap[(sampley * totsize) + samplex]);
        ramfile1.write(&vert, vec3f.sizeof);
        if (tileptr.mins.z > vert.z)
          tileptr.mins.z = vert.z;
        if (tileptr.maxs.z < vert.z)
          tileptr.maxs.z = vert.z;
      }
    }
    tileptr.vert.create(ramfile1.getSize(), PVBuffer.VertexContent, PVBuffer.StaticUsage, ramfile1.getData());

    tileptr.numverts = tilesizep1 * tilesizep1;

    tileptr.tex.loadPiece(cmap,
                          (tilex * cmaptilesize) & cmaptotmask, (tiley * cmaptilesize) & cmaptotmask,
                          cmaptilesize, cmaptilesize, true, true);

    // Create foliage

    srand(1);

    while (tileptr.foliage.length < foliageband.length)
      tileptr.foliage ~= new PTerrainFoliageSet();
    tileptr.foliage.length = foliageband.length;

    for (size_t b = 0; b < foliageband.length; b++) {
      auto fset = tileptr.foliage[b];

      fset.inst = null;

      // Create foliage instances
      for (int i = 0; i < foliageband[b].trycount; i++) {
        float rigidityvalue = 0.0f;
        // arguments are evaluated right to left by the original compiler: y first, then x
        float fy = cast(float)((tileptr.posy * tilesize) + rand01() * tilesize) * scale_hz;
        float fx = cast(float)((tileptr.posx * tilesize) + rand01() * tilesize) * scale_hz;
        vec2f ftry = vec2f(fx, fy);

        float fol = getFoliageLevel(ftry.x, ftry.y);

        if ((1.0 - fabs((fol - foliageband[b].middle) / foliageband[b].range)) < rand01()) continue;

        PTerrainFoliage inst;
        inst.pos.x = ftry.x;
        inst.pos.y = ftry.y;
        inst.pos.z = getHeight(ftry.x, ftry.y);
        inst.ang = rand01() * PI * 2.0f;
        inst.scale = (foliageband[b].scale + fol * 0.5f) * (rand01() * foliageband[b].scalemax + 0.5);

        if (foliageband[b].sprite_tex !is null)
          rigidityvalue = rigidity.getRigidity(foliageband[b].sprite_tex.getName());
        if (rigidityvalue != 0.0f) {
          inst.rigidity = rigidityvalue;
          tileptr.straight ~= inst;
        }
        fset.inst ~= inst;
      }

      // Create vertex buffers for rendering
      ramfile1.clear();
      ramfile2.clear();

      fset.numvert = 0;
      fset.numelem = 0;

      buildSpriteBuffers(fset, foliageband[b].sprite_count);

      if (fset.numelem) {
        fset.buff[0].create(ramfile1.getSize(), PVBuffer.VertexContent, PVBuffer.StaticUsage, ramfile1.getData());
        fset.buff[1].create(ramfile2.getSize(), PVBuffer.IndexContent, PVBuffer.StaticUsage, ramfile2.getData());
      }
    }

    while (tileptr.roadsignset.length < roadsigns.length)
      tileptr.roadsignset ~= new PRoadSignSet();
    tileptr.roadsignset.length = roadsigns.length;

    for (size_t b = 0; b < roadsigns.length; ++b) {
      float rigidityvalue = 0.0f;
      vec2f ftry = vec2f(roadsigns[b].x * scale_hz, roadsigns[b].y * scale_hz);
      vec2f tilemin = vec2f(tileptr.posx * tilesize * scale_hz, tileptr.posy * tilesize * scale_hz);
      vec2f tilemax = vec2f((tileptr.posx * tilesize + tilesize) * scale_hz,
                            (tileptr.posy * tilesize + tilesize) * scale_hz);

      if (ftry.x >= tilemin.x && ftry.x <= tilemax.x && ftry.y >= tilemin.y && ftry.y <= tilemax.y) {
        auto rset = tileptr.roadsignset[b];
        rset.inst = null;

        PTerrainFoliage inst;
        inst.pos.x = ftry.x;
        inst.pos.y = ftry.y;
        inst.pos.z = getHeight(ftry.x, ftry.y);
        inst.ang = roadsigns[b].deg;
        inst.scale = roadsigns[b].scale;

        rigidityvalue = rigidity.getRigidity(roadsigns[b].sprite.getName());
        if (rigidityvalue != 0.0f) {
          inst.rigidity = rigidityvalue;
          tileptr.straight ~= inst;
        }
        rset.inst ~= inst;

        ramfile1.clear();
        ramfile2.clear();

        rset.numvert = 0;
        rset.numelem = 0;

        buildSpriteBuffers(rset, roadsigns[b].sprite_count);

        if (rset.numelem) {
          rset.buff[0].create(ramfile1.getSize(), PVBuffer.VertexContent, PVBuffer.StaticUsage, ramfile1.getData());
          rset.buff[1].create(ramfile2.getSize(), PVBuffer.IndexContent, PVBuffer.StaticUsage, ramfile2.getData());
        }
      }
    }
    return tileptr;
  }

  /// Fills ramfile1/ramfile2 with the crossed-quad sprites for a set of instances.
  private void buildSpriteBuffers(PTerrainFoliageSet set, int sprite_count)
  {
    float angincr = PI / cast(float) sprite_count;
    foreach (ref inst; set.inst) {
      for (float anga = 0.0f; anga < PI - 0.01f; anga += angincr) {
        float interang = inst.ang + anga;
        int stv = set.numvert;
        PVert_tv tmpv;

        tmpv.xyz = inst.pos + vec3f(cos(interang) * HMULT, sin(interang) * HMULT, 0.0f) * inst.scale;
        tmpv.st = vec2f(1.0f, 0.0f);
        ramfile1.write(&tmpv, PVert_tv.sizeof);
        set.numvert++;

        tmpv.xyz = inst.pos + vec3f(-cos(interang) * HMULT, -sin(interang) * HMULT, 0.0f) * inst.scale;
        tmpv.st = vec2f(0.0f, 0.0f);
        ramfile1.write(&tmpv, PVert_tv.sizeof);
        set.numvert++;

        tmpv.xyz = inst.pos + vec3f(-cos(interang) * HMULT, -sin(interang) * HMULT, VMULT) * inst.scale;
        tmpv.st = vec2f(0.0f, 1.0f);
        ramfile1.write(&tmpv, PVert_tv.sizeof);
        set.numvert++;

        tmpv.xyz = inst.pos + vec3f(cos(interang) * HMULT, sin(interang) * HMULT, VMULT) * inst.scale;
        tmpv.st = vec2f(1.0f, 1.0f);
        ramfile1.write(&tmpv, PVert_tv.sizeof);
        set.numvert++;

        static immutable int[6] order = [0, 1, 2, 0, 2, 3];
        foreach (o; order) {
          uint idx = stv + o;
          ramfile2.write(&idx, uint.sizeof);
          set.numelem++;
        }
      }
    }
  }

  void render(in vec3f campos, in mat44f camorim)
  {
    // increase all lru counters
    foreach (t; tile) ++t.lru_counter;

    // get frustum (computed but unused, as in the original)
    frustumf frust;
    {
      mat44f mat_mv, mat_p, mat_c;

      glGetFloatv(GL_MODELVIEW_MATRIX, mat_mv);
      glGetFloatv(GL_PROJECTION_MATRIX, mat_p);

      mat_c = mat_mv.concatenate(mat_p);

      frust.construct(mat_c);
    }

    int ctx = cast(int)(campos.x * scale_tile_inv);
    if (campos.x < 0.0) --ctx;
    int cty = cast(int)(campos.y * scale_tile_inv);
    if (campos.y < 0.0) --cty;

    int mintx = ctx - 3,
        maxtx = ctx + 4,
        minty = cty - 3,
        maxty = cty + 4;

    // Determine list of tiles to draw
    PTerrainTile[] drawtile;

    for (int ty = minty; ty < maxty; ++ty) {
      for (int tx = mintx; tx < maxtx; ++tx) {
        drawtile ~= getTile(tx, ty);
      }
    }

    // Draw terrain
    glEnable(GL_TEXTURE_GEN_S);
    glEnable(GL_TEXTURE_GEN_T);

    float[4] tgens = [scale_tile_inv, 0.0f, 0.0f, 0.0f];
    float[4] tgent = [0.0f, scale_tile_inv, 0.0f, 0.0f];
    glTexGeni(GL_S, GL_TEXTURE_GEN_MODE, GL_OBJECT_LINEAR);
    glTexGeni(GL_T, GL_TEXTURE_GEN_MODE, GL_OBJECT_LINEAR);

    glEnableClientState(GL_VERTEX_ARRAY);

    foreach (t; drawtile) {
      tgens[3] = cast(float)(-t.posx);
      tgent[3] = cast(float)(-t.posy);

      glTexGenfv(GL_S, GL_OBJECT_PLANE, tgens);
      glTexGenfv(GL_T, GL_OBJECT_PLANE, tgent);

      // Texture
      t.tex.bind();

      // Vertex buffers
      t.vert.bind();
      ind.bind();
      glVertexPointer(3, GL_FLOAT, cast(int) vec3f.sizeof, t.vert.getPointer(0));

      glDrawRangeElements(GL_TRIANGLE_STRIP, 0, t.numverts, numinds, GL_UNSIGNED_SHORT, ind.getPointer(0));
    }

    glDisableClientState(GL_VERTEX_ARRAY);

    PVBuffer.unbind();

    glDisable(GL_TEXTURE_GEN_S);
    glDisable(GL_TEXTURE_GEN_T);

    // Don't apply terrain detail texture to foliage.
    glActiveTextureARB(GL_TEXTURE1_ARB);
    glDisable(GL_TEXTURE_2D);
    glActiveTextureARB(GL_TEXTURE0_ARB);

    // Draw foliage
    glAlphaFunc(GL_GEQUAL, 0.5);
    glEnable(GL_ALPHA_TEST);
    glDisable(GL_CULL_FACE);
    glColor3f(1.0f, 1.0f, 1.0f);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glEnableClientState(GL_VERTEX_ARRAY);

    for (size_t b = 0; b < foliageband.length; b++) {
      if (foliageband[b].sprite_tex is null) continue;

      foliageband[b].sprite_tex.bind();

      foreach (t; drawtile) {
        auto f = t.foliage[b];
        if (f.numelem) {
          f.buff[0].bind(); // vert data
          f.buff[1].bind(); // indices

          glTexCoordPointer(2, GL_FLOAT, cast(int) PVert_tv.sizeof, f.buff[0].getPointer(0));
          glVertexPointer(3, GL_FLOAT, cast(int) PVert_tv.sizeof, f.buff[0].getPointer(float.sizeof * 2));

          glDrawRangeElements(GL_TRIANGLES, 0, f.numvert, f.numelem, GL_UNSIGNED_INT, f.buff[1].getPointer(0));
        }
      }
    }

    PVBuffer.unbind();

    // draw road signs
    for (size_t b = 0; b < roadsigns.length; ++b) {
      roadsigns[b].sprite.bind();

      foreach (t; drawtile) {
        auto r = t.roadsignset[b];
        if (r.numelem) {
          r.buff[0].bind();
          r.buff[1].bind();

          glTexCoordPointer(2, GL_FLOAT, cast(int) PVert_tv.sizeof, r.buff[0].getPointer(0));
          glVertexPointer(3, GL_FLOAT, cast(int) PVert_tv.sizeof, r.buff[0].getPointer(float.sizeof * 2));

          glDrawRangeElements(GL_TRIANGLES, 0, r.numvert, r.numelem, GL_UNSIGNED_INT, r.buff[1].getPointer(0));
        }
      }
    }

    PVBuffer.unbind();
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
    glEnable(GL_CULL_FACE);
    glDisable(GL_ALPHA_TEST);
  }

  void drawSplat(float x, float y, float scale, float angle)
  {
    float[] hmd = hmap;
    int cx = totsize;
    int cy = totsize;

    x *= scale_hz_inv;
    y *= scale_hz_inv;

    scale *= 0.5f;

    int miny = cast(int)(y - scale);
    if ((y - scale) < 0.0f) miny--;
    int maxy = cast(int)(y + scale) + 1;
    if ((y + scale) < 0.0f) maxy--;
    int minx = cast(int)(x - scale);
    if ((x - scale) < 0.0f) minx--;
    int maxx = cast(int)(x + scale) + 2;
    if ((x + scale) < 0.0f) maxx--;

    glMatrixMode(GL_TEXTURE);

    glPushMatrix();
    glTranslatef(0.5f, 0.5f, 0.0f);
    glRotatef(DEGREES(angle), 0.0f, 0.0f, 1.0f);
    glScalef(0.5f / scale, 0.5f / scale, 1.0f);
    glTranslatef(-x, -y, 0.0f);

    for (int y2 = miny; y2 < maxy; y2++) {
      int yc = y2 & (cy - 1),
          ycp1 = (yc + 1) & (cy - 1),
          yc_cx = yc * cx,
          ycp1_cx = ycp1 * cx;

      glBegin(GL_TRIANGLE_STRIP);
      for (int x2 = minx; x2 < maxx; x2++) {
        int xc = x2 & (cx - 1);
        glTexCoord2i(x2, y2 + 1);
        glVertex3f(x2 * scale_hz, (y2 + 1) * scale_hz, hmd[ycp1_cx + xc]);
        glTexCoord2i(x2, y2);
        glVertex3f(x2 * scale_hz, y2 * scale_hz, hmd[yc_cx + xc]);
      }
      glEnd();
    }
    glPopMatrix();

    glMatrixMode(GL_MODELVIEW);
  }

  /// Returns whether or not the given position is on road (true if no roadmap was loaded).
  bool getRmapOnRoad(in vec3f pos) const
  {
    return rmap.isOnRoad(pos.x, pos.y, getMapSize());
  }

  /// Returns the color of the pixel in the colormap that corresponds to the given position
  /// in the terrain (the height component Z is ignored), in OpenGL-style RGB.
  vec3f getCmapColor(in vec3f pos) const
  {
    vec3f r;
    const int ms = cast(int) getMapSize();
    int px = cast(int) pos.x;
    int py = cast(int) pos.y;

    if (px >= ms) {
      do
        px -= ms;
      while (px > ms);
    } else if (px < 0) {
      do
        px += ms;
      while (px < 0);
    }

    if (py >= ms) {
      do
        py -= ms;
      while (py > ms);
    } else if (py < 0) {
      do
        py += ms;
      while (py < 0);
    }

    long x = lround(cast(float)(px * cmap.getcx()) / getMapSize());
    long y = lround(cast(float)(py * cmap.getcy()) / getMapSize());

    CLAMP_UPPER(x, cmap.getcx() - 1);
    CLAMP_UPPER(y, cmap.getcy() - 1);
    r.x = cmap.getByte(cast(size_t)((y * cmap.getcx() + x) * cmap.getcc() + 0)) / 255.0f;
    r.y = cmap.getByte(cast(size_t)((y * cmap.getcx() + x) * cmap.getcc() + 1)) / 255.0f;
    r.z = cmap.getByte(cast(size_t)((y * cmap.getcx() + x) * cmap.getcc() + 2)) / 255.0f;
    return r;
  }

  /// Returns the road surface type corresponding to the given position in the terrain.
  TerrainType getRoadSurface(in vec3f pos) const
  {
    if (tmap.getData().length == 0)
      return TerrainType.Unknown;

    const int ms = cast(int) getMapSize();
    int px = cast(int) pos.x;
    int py = cast(int) pos.y;

    if (px >= ms) {
      do
        px -= ms;
      while (px > ms);
    } else if (px < 0) {
      do
        px += ms;
      while (px < 0);
    }

    if (py >= ms) {
      do
        py -= ms;
      while (py > ms);
    } else if (py < 0) {
      do
        py += ms;
      while (py < 0);
    }

    long x = lround(cast(float)(px * tmap.getcx()) / getMapSize());
    long y = lround(cast(float)(py * tmap.getcy()) / getMapSize());
    rgbcolor temp;

    CLAMP_UPPER(x, tmap.getcx() - 1);
    CLAMP_UPPER(y, tmap.getcy() - 1);
    temp.r = tmap.getByte(cast(size_t)((y * tmap.getcx() + x) * tmap.getcc() + 0));
    temp.g = tmap.getByte(cast(size_t)((y * tmap.getcx() + x) * tmap.getcc() + 1));
    temp.b = tmap.getByte(cast(size_t)((y * tmap.getcx() + x) * tmap.getcc() + 2));
    return PUtil.decideRoadSurface(temp);
  }

  /// Gets the information about a contact point (its coordinates and normal) with the ground.
  void getContactInfo(ref ContactInfo tci)
  {
    float x = tci.pos.x * scale_hz_inv;
    // int part of x
    int xi = cast(int) x;
    if (x < 0.0) xi--;
    // x is the decimal part
    x -= cast(float) xi;
    int xiw = xi & totmask, xiw2 = (xi + 1) & totmask;

    float y = tci.pos.y * scale_hz_inv;
    int yi = cast(int) y;
    if (y < 0.0) yi--;
    y -= cast(float) yi;
    int yiw = yi & totmask, yiw2 = (yi + 1) & totmask;

    const(float)[] data = hmap;
    const cx = totsize;

    float xv1, xv2;
    if (y > 0.0) {
      if (y < 1.0) {
        if (x < y) {
          tci.normal.x = data[yiw2 * cx + xiw] - data[yiw2 * cx + xiw2];
          tci.normal.y = data[yiw * cx + xiw] - data[yiw2 * cx + xiw];
          xv1 = data[yiw * cx + xiw];
          xv2 = INTERP(data[yiw2 * cx + xiw], data[yiw2 * cx + xiw2], x / y);
        } else {
          tci.normal.x = data[yiw * cx + xiw] - data[yiw * cx + xiw2];
          tci.normal.y = data[yiw * cx + xiw2] - data[yiw2 * cx + xiw2];
          xv1 = INTERP(data[yiw * cx + xiw], data[yiw * cx + xiw2], (x - y) / (1.0 - y));
          xv2 = data[yiw2 * cx + xiw2];
        }
        tci.pos.z = INTERP(xv1, xv2, y);
      } else {
        tci.normal.x = data[yiw2 * cx + xiw] - data[yiw2 * cx + xiw2];
        tci.normal.y = data[yiw * cx + xiw] - data[yiw2 * cx + xiw];
        tci.pos.z = INTERP(data[yiw2 * cx + xiw], data[yiw2 * cx + xiw2], x);
      }
    } else {
      tci.normal.x = data[yiw * cx + xiw] - data[yiw * cx + xiw2];
      tci.normal.y = data[yiw * cx + xiw2] - data[yiw2 * cx + xiw2];
      tci.pos.z = INTERP(data[yiw * cx + xiw], data[yiw * cx + xiw2], x);
    }
    tci.normal.z = scale_hz;
    tci.normal.normalize();
  }

  float getHeight(float x, float y) { return getInterp(x, y, hmap); }

  float getFoliageLevel(float x, float y) { return getInterp(x, y, fmap); }

  PTexture getHUDMapTexture() { return tex_hud_map; }

  float getMapSize() const { return totsize * scale_hz; }
}
