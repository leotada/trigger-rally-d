// util [pengine]
//
// Copyright 2004-2006 Jasmine Langridge, jas@jareiko.net
// License: GPL version 2 (see included gpl.txt)
//
// D port of pengine.h (PUtil, dirtinfo, rgbcolor, TerrainType), terrainmap.h,
// exception.h and util.cpp.
module pengine.util;

import std.algorithm : endsWith;
import std.array : appender;
import std.stdio : stdout, write, writeln;
import std.string : indexOf, lastIndexOf;
import std.conv : to;

import pengine.pvfs;
import pengine.xml;

enum DEBUGLEVEL_CRITICAL = 0;
enum DEBUGLEVEL_ENDUSER = 10;
enum DEBUGLEVEL_TEST = 20;
enum DEBUGLEVEL_DEVELOPER = 30;

/// Exception thrown by the engine on load/initialisation errors.
class PException : Exception
{
  this(string text) { super(text); }
}

/// Creates a `PException` carrying the source location, like the original macro.
PException MakePException(string text, string file = __FILE__, size_t line = __LINE__)
{
  return new PException(text ~ " at " ~ file ~ ":" ~ to!string(line));
}

/// Helper structure for storing dirt information.
struct dirtinfo
{
  float startsize = 0.1f;
  float endsize = 0.5f;
  float decay = 6.0f;
}

/// Helper structure for storing RGB colors.
struct rgbcolor
{
  ubyte r = 0;
  ubyte g = 0;
  ubyte b = 0;
}

enum TerrainType
{
  Unknown,
  RacingTarmac,
  CountryRoad,
  SlipperyRoad,
  Ice,
  DeepSnow,
  FirmSand,
  LooseSand,
  PressedEarth,
  LooseEarth,
  MoistEarth,
  Mud,
  FineGravel,
  RoughGravel,
  Grass,
  Shrubbery,
  DeepWater
}

private struct TerrainMaterial
{
  TerrainType type;
  rgbcolor color;
  float friction;
  float resistance;
  dirtinfo dirt;
  string info; ///< "Name friction resistance", as stringified by the original macro
}

private immutable TerrainMaterial[] terrainMaterials = [
  TerrainMaterial(TerrainType.RacingTarmac,  rgbcolor( 80,  60, 100), 1.50f, 0.00f, dirtinfo(0.00f, 0.10f, 6.0f), "RacingTarmac 1.50 0.00"),
  TerrainMaterial(TerrainType.CountryRoad,   rgbcolor(140,  80, 180), 1.20f, 0.00f, dirtinfo(0.00f, 0.20f, 6.0f), "CountryRoad 1.20 0.00"),
  TerrainMaterial(TerrainType.SlipperyRoad,  rgbcolor(200, 140, 255), 0.50f, 0.00f, dirtinfo(0.00f, 0.30f, 6.0f), "SlipperyRoad 0.50 0.00"),
  TerrainMaterial(TerrainType.Ice,           rgbcolor(180, 220, 255), 0.20f, 0.00f, dirtinfo(0.00f, 0.10f, 6.0f), "Ice 0.20 0.00"),
  TerrainMaterial(TerrainType.DeepSnow,      rgbcolor(255, 255, 255), 0.30f, 0.50f, dirtinfo(0.00f, 0.80f, 1.0f), "DeepSnow 0.30 0.50"),
  TerrainMaterial(TerrainType.FirmSand,      rgbcolor(255, 220,   0), 1.00f, 0.05f, dirtinfo(0.50f, 2.60f, 1.5f), "FirmSand 1.00 0.05"),
  TerrainMaterial(TerrainType.LooseSand,     rgbcolor(255, 255, 140), 0.75f, 0.55f, dirtinfo(0.50f, 3.00f, 1.5f), "LooseSand 0.75 0.55"),
  TerrainMaterial(TerrainType.PressedEarth,  rgbcolor(255, 200, 200), 0.90f, 0.05f, dirtinfo(0.00f, 0.35f, 3.0f), "PressedEarth 0.90 0.05"),
  TerrainMaterial(TerrainType.LooseEarth,    rgbcolor(255, 140, 140), 0.70f, 0.25f, dirtinfo(0.00f, 1.00f, 2.0f), "LooseEarth 0.70 0.25"),
  TerrainMaterial(TerrainType.MoistEarth,    rgbcolor(255,   0,   0), 1.10f, 0.15f, dirtinfo(0.00f, 0.75f, 7.5f), "MoistEarth 1.10 0.15"),
  TerrainMaterial(TerrainType.Mud,           rgbcolor(160,   0,   0), 0.60f, 0.40f, dirtinfo(0.00f, 0.55f, 6.0f), "Mud 0.60 0.40"),
  TerrainMaterial(TerrainType.FineGravel,    rgbcolor(140, 140, 140), 0.90f, 0.10f, dirtinfo(0.00f, 1.25f, 3.0f), "FineGravel 0.90 0.10"),
  TerrainMaterial(TerrainType.RoughGravel,   rgbcolor(  0,   0,   0), 0.60f, 0.20f, dirtinfo(0.00f, 0.40f, 5.0f), "RoughGravel 0.60 0.20"),
  TerrainMaterial(TerrainType.Grass,         rgbcolor(  0, 180,   0), 0.40f, 0.10f, dirtinfo(0.00f, 0.30f, 6.5f), "Grass 0.40 0.10"),
  TerrainMaterial(TerrainType.Shrubbery,     rgbcolor(  0,  90,   0), 0.40f, 0.70f, dirtinfo(0.00f, 0.50f, 6.0f), "Shrubbery 0.40 0.70"),
  TerrainMaterial(TerrainType.DeepWater,     rgbcolor(  0,   0, 255), 0.20f, 0.60f, dirtinfo(0.00f, 0.50f, 6.0f), "DeepWater 0.20 0.60"),
];

/// Class which contains helper functions.
struct PUtil
{
  private static int deblev = DEBUGLEVEL_ENDUSER;

  /// Writes a line to the log (standard output).
  static void outLog(Args...)(Args args)
  {
    write(args);
    writeln();
    stdout.flush();
  }

  static bool isDebugLevel(int debugLevel) { return deblev >= debugLevel; }
  static void setDebugLevel(int debugLevel) { deblev = debugLevel; }

  /// Returns the road surface based on the RGB color.
  static TerrainType decideRoadSurface(in rgbcolor c)
  {
    foreach (ref m; terrainMaterials)
      if (m.color == c) return m.type;
    return TerrainType.Unknown;
  }

  /// Returns the road surface friction coefficient.
  static float decideFrictionCoef(TerrainType tt)
  {
    foreach (ref m; terrainMaterials)
      if (m.type == tt) return m.friction;
    return 1.00f; // tt == TerrainType.Unknown
  }

  /// Returns the road surface resistance.
  static float decideResistance(TerrainType tt)
  {
    foreach (ref m; terrainMaterials)
      if (m.type == tt) return m.resistance;
    return 0.00f; // tt == TerrainType.Unknown
  }

  /// Get string with information about terrain, for debugging purposes.
  static string getTerrainInfo(TerrainType tt)
  {
    foreach (ref m; terrainMaterials)
      if (m.type == tt) return m.info;
    return "Unknown 1.00 0.00";
  }

  /// Returns the road surface maximum dirt size.
  static dirtinfo getDirtInfo(TerrainType tt)
  {
    foreach (ref m; terrainMaterials)
      if (m.type == tt) return m.dirt;
    return dirtinfo(0.10f, 0.50f, 6.00f); // tt == TerrainType.Unknown
  }

  /// Get terrainmap color of terrain, for debugging purposes.
  static rgbcolor getTerrainColor(TerrainType tt)
  {
    foreach (ref m; terrainMaterials)
      if (m.type == tt) return m.color;
    return rgbcolor(0, 0, 0);
  }

  /// Get token and value from a string line. The token is the string
  /// before first space. The value, is the remaining string.
  /// Returns true if could extract token and value.
  static bool getToken(string line, out string tok, out string value)
  {
    tok = "";
    value = "";

    // remove initial spaces
    size_t ns = 0;
    while (ns < line.length && (line[ns] == ' ' || line[ns] == '\t')) ns++;
    if (ns < line.length)
      line = line[ns .. $];

    // find first space
    ptrdiff_t sp = -1;
    foreach (i, c; line)
      if (c == ' ' || c == '\t') {
        sp = cast(ptrdiff_t) i;
        break;
      }
    if (sp >= 0) {
      tok = line[0 .. sp];

      if (cast(size_t)(sp + 1) < line.length) {
        value = line[sp + 1 .. $];
        // remove trailing \n, if any
        if (value[$ - 1] == '\n')
          value = value[0 .. $ - 1];
      } else {
        value = "";
      }
      return true;
    }
    return false;
  }

  /// Reads a line (including the trailing '\n') of at most `size - 1` characters.
  /// Returns null at the end of file. (Unlike the original, an unterminated
  /// last line is returned instead of being dropped.)
  static string fgets2(PFile pfile, int size)
  {
    if (pfile.eof()) return null;

    auto line = appender!string();
    for (int i = 0; i < size - 1; i++) {
      if (pfile.eof()) break;
      ubyte[1] b;
      long ret = pfile.read(b[]);
      if (ret <= 0) break;
      line ~= cast(char) b[0];
      if (b[0] == '\n') break;
    }
    return line.data;
  }

  /// Given "data/blah/pic.jpg" will return "data/blah/".
  static string extractPathFromFilename(string filename)
  {
    auto found = filename.lastIndexOf('/');
    if (found < 0) return "";
    return filename[0 .. found + 1];
  }

  /// PhysFS doesn't allow ".."s in path names, so relative paths are resolved here.
  static string assemblePath(string relativefile, string parentfile)
  {
    string totalpath;

    if (relativefile.length && relativefile[0] == '/') {
      // relativefile is an absolute path
      totalpath = relativefile[1 .. $];
    } else {
      // relativefile is indeed relative, so concat with parent path
      totalpath = extractPathFromFilename(parentfile) ~ relativefile;
    }

    string totalpath_hold = totalpath;

    while (true) {
      // attempt to find a ".." to crunch back
      auto found = totalpath.indexOf("../");

      if (found < 0) break; // no more ".."s

      if (found < 2) {
        // ".." is too close to start of path
        outLog("Error: above local root: \"", totalpath_hold, "\"");
        return "";
      }

      auto crunch = totalpath[0 .. found - 1].lastIndexOf('/');

      if (crunch < 0) {
        // Crunch back to root (special case)
        crunch = 0;
        found += 1;
      }

      // remove the "/dir/.." chunk
      totalpath = totalpath[0 .. crunch] ~ totalpath[found + 2 .. $];
    }

    return totalpath;
  }

  /// Load XML file and return the root element of given name (failure: null).
  static XMLElement loadRootElement(XMLDocument doc, string filename, string rootName)
  {
    PFile pfile = PVfs.openRead(filename);
    if (pfile is null) {
      outLog("Load failed: PhysFS: ", PVfs.lastError);
      return null;
    }

    auto buffer = pfile.readAll();
    pfile.close();

    doc.Parse(cast(const(char)[]) buffer);

    XMLElement rootelem = doc.FirstChildElement(rootName);
    if (rootelem is null) {
      outLog("Load failed: TinyXML error");
      outLog("TinyXML: ", doc.ErrorStr());
      return null;
    }

    return rootelem;
  }

  static bool copyFile(string fileFrom, string fileTo)
  {
    outLog("Copying \"", fileFrom, "\" to \"", fileTo, "\"");

    PFile pfile_from = PVfs.openRead(fileFrom);
    if (pfile_from is null) {
      outLog("Copy failed: PhysFS: ", PVfs.lastError);
      return false;
    }

    // Make dest directory
    string filepath = extractPathFromFilename(fileTo);
    if (!PVfs.mkdir(filepath)) {
      if (PVfs.lastError == "File exists") {
        outLog("Couldn't mkdir \"", filepath, "\", attempting copy anyway");
        outLog("PhysFS: ", PVfs.lastError);
      }
    }

    PFile pfile_to = PVfs.openWrite(fileTo);
    if (pfile_to is null) {
      pfile_from.close();
      outLog("Copy failed: PhysFS: ", PVfs.lastError);
      return false;
    }

    pfile_to.write(pfile_from.readAll());

    pfile_from.close();
    pfile_to.close();

    return true;
  }

  static string[] findFiles(string basedir, string extension)
  {
    string[] results;

    foreach (name; PVfs.enumerateFiles(basedir)) {
      string thisfile = basedir ~ '/' ~ name;

      if (PVfs.isDirectory(thisfile)) {
        // Recurse into subdirectory
        results ~= findFiles(thisfile, extension);
      } else {
        // Check to see if file has correct extension
        if (thisfile.length >= extension.length && thisfile.endsWith(extension))
          results ~= thisfile;
      }
    }

    return results;
  }

  static string formatInt(int value, int width)
  {
    char[] text = new char[width];
    text[] = '0';

    for (int i = width - 1; i >= 0; i--) {
      text[i] = cast(char)('0' + (value % 10));
      value /= 10;
    }

    return text.idup;
  }

  static string formatInt(int value)
  {
    string text;

    bool neg = false;

    if (value < 0) {
      neg = true;
      value = -value;
    } else if (value == 0)
      return "0";

    for (; value; value /= 10)
      text = (cast(char)('0' + (value % 10))) ~ text;

    return neg ? ('-' ~ text) : text;
  }

  static string formatTime(float seconds)
  {
    int time_mins = cast(int)(seconds / 60.0f);
    seconds -= time_mins * 60;
    int time_secs = cast(int)(seconds);
    seconds -= time_secs;
    int time_centis = cast(int)(seconds * 100.0f);

    return formatInt(time_mins, 2) ~ ':' ~ formatInt(time_secs, 2) ~ '.' ~ formatInt(time_centis, 2);
  }

  /// Converts time expressed in seconds to a human-readable string.
  static string formatTimeShort(float seconds)
  {
    const int time_mins = cast(int)(seconds / 60.0f);
    seconds -= time_mins * 60;
    const int time_secs = cast(int)(seconds);

    return formatInt(time_mins) ~ ':' ~ formatInt(time_secs, 2);
  }
}
