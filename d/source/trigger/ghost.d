// ghost [trigger]
//
// License: GPL version 2 (see included gpl.txt)
//
// Recording and play back of ghost vehicles.
module trigger.ghost;

import std.algorithm : canFind;
import std.array : appender, replace, split;
import std.conv : to;
import std.format : format;
import std.string : indexOf, strip;

import pengine.pvfs;
import pengine.util;
import pengine.vmath;
import psim.vehicle : PVehiclePart;

private string fmtg(float f) { return format("%g", f); }

final class PGhost
{
  /// Wheels of the ghost
  struct GhostWheel {
    vec3f pos;  ///< Position in world coordinates
    quatf ori;  ///< Orientation of the wheel
  }

  /// State of the ghost vehicle
  struct GhostData {
    float time = 0;     ///< Time stamp in seconds in game time
    vec3f pos;          ///< Position in world coordinates
    quatf ori;          ///< Orientation of the vehicle
    GhostWheel[] wheel; ///< Status of the wheels
  }

  private string mapname = "";
  private string vehiclename = "";
  private float sampletime;
  private float lastsample;
  private GhostData[] recordeddata;
  private GhostData[] replaydata;
  private float racetime = 0.0f;
  private string replayvehicle = "";
  private float replaytime;

  this(float sampletime)
  {
    this.sampletime = sampletime;
    lastsample = -float.max;
    replaytime = float.max;
  }

  /// Start recording the next race for later replay
  void recordStart(string map, string vehicle)
  {
    mapname = map ~ ".ghost";
    mapname = mapname.replace("/", "_");

    vehiclename = vehicle;
    lastsample = -float.max;
    recordeddata = null;
    replaydata = null;
    racetime = 0.0f;
    replayvehicle = "";
    replaytime = float.max;

    if (!PVfs.isInit())
      return;

    PFile physfile = PVfs.openRead(mapname);
    if (physfile is null)
      return;

    string readdata = cast(string) physfile.readAll().idup;

    auto comma = readdata.indexOf(',');
    if (comma < 0) {
      physfile.close();
      return;
    }
    replayvehicle = readdata[0 .. comma];
    string rest = readdata[comma + 1 .. $];
    auto nl = rest.indexOf('\n');
    string replaytimestring = nl < 0 ? rest : rest[0 .. nl];
    rest = nl < 0 ? "" : rest[nl + 1 .. $];

    try {
      replaytime = to!float(strip(replaytimestring));

      GhostData data;
      size_t pos = 0;
      while (pos < rest.length) {
        auto e = rest.indexOf('\n', pos);
        string line;
        if (e < 0) {
          line = rest[pos .. $];
          pos = rest.length;
        } else {
          line = rest[pos .. e];
          pos = e + 1;
        }
        parseGhostLine(line, data);
        replaydata ~= data;
      }
      physfile.close();
    } catch (Exception) {
      PUtil.outLog("Invalid data format in *.ghost file.");
    }
  }

  /// Samples the state of the vehicle if sample time is passed.
  void recordSample(float delta, const(PVehiclePart) part)
  {
    bool firstsample = (racetime == 0.0f);

    racetime += delta;
    if (firstsample || racetime >= lastsample + sampletime) {
      GhostData data;

      lastsample = racetime;
      data.time = racetime;
      data.pos = part.ref_world.getPosition();
      data.ori = part.ref_world.getOrientation();
      foreach (ref w; part.wheel) {
        GhostWheel wheel;

        wheel.pos = w.ref_world.getPosition();
        wheel.ori = w.ref_world.getOrientation();
        data.wheel ~= wheel;
      }
      recordeddata ~= data;
    }
  }

  /// Store ghost at end of the race if best time achieved.
  void recordStop(float time)
  {
    if (time <= replaytime) {
      if (mapname.length == 0) return;
      if (!PVfs.isInit()) return;

      PFile physfile = PVfs.openWrite(mapname);
      if (physfile is null)
        return;

      auto outputstream = appender!string();
      outputstream ~= vehiclename ~ ',' ~ fmtg(time) ~ '\n';
      foreach (ref data; recordeddata)
        outputstream ~= formatGhostData(data);

      physfile.write(outputstream.data);
      physfile.close();
    }
  }

  /// Get ghost state based on current race time. Returns true if data is valid.
  bool getReplayData(ref GhostData data, ref string vehicle) const
  {
    vehicle = replayvehicle;

    for (size_t i = 0; i < replaydata.length; ++i) {
      if (i == replaydata.length - 1 && racetime >= replaydata[i].time) {
        data = cast(GhostData) replaydata[i];
        return true;
      } else if (i + 1 < replaydata.length && racetime >= replaydata[i].time && racetime < replaydata[i + 1].time) {
        float interptime = 0.0f;

        if (replaydata[i + 1].time - replaydata[i].time != 0.0f)
          interptime = (racetime - replaydata[i].time) / (replaydata[i + 1].time - replaydata[i].time);

        data.time = racetime;
        data.pos = INTERP(replaydata[i].pos, replaydata[i + 1].pos, interptime);
        data.ori = INTERP(replaydata[i].ori, replaydata[i + 1].ori, interptime);

        for (size_t j = 0; j < replaydata[i].wheel.length; ++j) {
          GhostWheel wheel;

          wheel.pos = INTERP(replaydata[i].wheel[j].pos, replaydata[i + 1].wheel[j].pos, interptime);
          wheel.ori = INTERP(replaydata[i].wheel[j].ori, replaydata[i + 1].wheel[j].ori, interptime);
          data.wheel ~= wheel;
        }
        return true;
      }
    }
    return false;
  }
}

private string formatGhostData(in PGhost.GhostData gd)
{
  auto o = appender!string();
  o ~= fmtg(gd.time) ~ ',' ~ fmtg(gd.pos.x) ~ ',' ~ fmtg(gd.pos.y) ~ ',' ~ fmtg(gd.pos.z) ~ ',' ~
       fmtg(gd.ori.x) ~ ',' ~ fmtg(gd.ori.y) ~ ',' ~ fmtg(gd.ori.z) ~ ',' ~ fmtg(gd.ori.w);
  foreach (ref w; gd.wheel)
    o ~= ',' ~ fmtg(w.pos.x) ~ ',' ~ fmtg(w.pos.y) ~ ',' ~ fmtg(w.pos.z) ~ ',' ~
         fmtg(w.ori.x) ~ ',' ~ fmtg(w.ori.y) ~ ',' ~ fmtg(w.ori.z) ~ ',' ~ fmtg(w.ori.w);
  o ~= '\n';
  return o.data;
}

/// Parses one line of a ghost file into `gd`. An empty line leaves `gd` untouched.
private void parseGhostLine(string line, ref PGhost.GhostData gd)
{
  if (line.length == 0)
    return;

  auto result = line.split(',');
  try {
    if (result.length < 8) throw new Exception("short line");
    float f(size_t i) { return to!float(strip(result[i])); }
    gd.time = f(0);
    gd.pos.x = f(1);
    gd.pos.y = f(2);
    gd.pos.z = f(3);
    gd.ori.x = f(4);
    gd.ori.y = f(5);
    gd.ori.z = f(6);
    gd.ori.w = f(7);

    gd.wheel = null;
    for (size_t i = 8; i < result.length; i = i + 7) {
      if (i + 6 >= result.length) throw new Exception("short wheel");
      PGhost.GhostWheel gw;
      gw.pos.x = f(i);
      gw.pos.y = f(i + 1);
      gw.pos.z = f(i + 2);
      gw.ori.x = f(i + 3);
      gw.ori.y = f(i + 4);
      gw.ori.z = f(i + 5);
      gw.ori.w = f(i + 6);
      gd.wheel ~= gw;
    }
  } catch (Exception) {
    PUtil.outLog("Invalid data format in *.ghost file.");
  }
}
