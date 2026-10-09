// hiscore1 [trigger]
//
// Copyright (C) 2015 Andrei Bondor, ab396356@users.sourceforge.net
// License: GPL version 2 (see included gpl.txt)
//
// Loads and saves the player's best times and unlocks.
module trigger.hiscore1;

import std.algorithm : sort, min;
import std.array : appender;
import std.conv : to;
import std.format : format;
import std.regex : regex, matchFirst;
import std.string : strip;

import pengine.pvfs;
import pengine.util;

/// Unlock data: a set of strings (use `x in set`, `set[x] = true`, `set.length`).
alias UnlockData = bool[string];

struct RaceData
{
  string playername;  ///< e.g. "Andrei"
  string mapname;     ///< e.g. "/maps/jumpy/jumpy.level"
  string carname;     ///< e.g. "FMC Fox"
  string carclass;    ///< e.g. "Super500"
  float totaltime = 0;///< e.g. "102.2"
  float maxspeed = 0; ///< e.g. "212.0"

  this(string playername) { this.playername = playername; }

  this(string playername, string mapname, string carname, string carclass, float totaltime, float maxspeed)
  {
    this.playername = playername;
    this.mapname = mapname;
    this.carname = carname;
    this.carclass = carclass;
    this.totaltime = totaltime;
    this.maxspeed = maxspeed;
  }
}

enum HISCORE1_SORT
{
  BY_TOTALTIME_ASC,
  BY_TOTALTIME_DESC,
  BY_MAXSPEED_ASC,
  BY_MAXSPEED_DESC,
  BY_PLAYERNAME_ASC,
  BY_PLAYERNAME_DESC,
  BY_CARNAME_ASC,
  BY_CARNAME_DESC,
  BY_CARCLASS_ASC,
  BY_CARCLASS_DESC
}

/// Used to display the best times information.
struct TimeEntry
{
  ulong place = 0;        ///< True place, depending on time.
  RaceData rd;            ///< Race data.
  bool highlighted = false;///< Highlight flag.
}

/// Line oriented reader emulating `std::getline` on an input string stream.
private struct LineReader
{
  string s;
  size_t pos;

  bool getline(out string line)
  {
    if (pos >= s.length) return false;
    size_t e = pos;
    while (e < s.length && s[e] != '\n') e++;
    line = s[pos .. e];
    pos = e < s.length ? e + 1 : e;
    return true;
  }

  /// Reads lines until a non-empty one is found. Returns false if none.
  bool getlineSkipEmpty(out string line)
  {
    while (getline(line))
      if (line.length) break;
    return line.length != 0;
  }
}

private float stof(string s)
{
  return to!float(strip(s));
}

private string fmtg(float f) { return format("%g", f); }

private bool readRaceData(ref LineReader r, ref RaceData rd)
{
  string ts;
  if (!r.getlineSkipEmpty(rd.mapname)) return false;
  if (!r.getlineSkipEmpty(rd.carname)) return false;
  if (!r.getlineSkipEmpty(rd.carclass)) return false;
  if (!r.getlineSkipEmpty(ts)) return false;
  rd.totaltime = stof(ts);
  if (!r.getlineSkipEmpty(ts)) return false;
  rd.maxspeed = stof(ts);
  return true;
}

private string writeRaceData(in RaceData rd)
{
  return rd.mapname ~ '\n' ~ rd.carname ~ '\n' ~ rd.carclass ~ '\n' ~ fmtg(rd.totaltime) ~ '\n' ~
         fmtg(rd.maxspeed) ~ "\n\n";
}

/// Loads and saves the player's best times.
/// Note: there is no destructor; call `savePlayer()` before exiting.
final class HiScore1
{
  private RaceData[][string] alltimes;     ///< All times for all maps.
  private UnlockData[string] allunlocks;   ///< All unlock data for all players.
  private TimeEntry[] currenttimes;        ///< Selected times, for current map.
  private string searchdir;                ///< Directory where player profiles are.
  private string playername;               ///< Name of the current player.
  private long skipSaves = 5;              ///< Number of saves to skip, -1 means "save all by dtor".
  private long sc = 0;                     ///< Skip counter.

  this(string searchdir, string playername = "Player")
  {
    this.searchdir = searchdir;
    this.playername = playername;
  }

  void setPlayerName(string pname) { playername = pname; }

  /// Loads all times from .PLAYER files.
  void loadAllTimes()
  {
    if (!PVfs.isInit()) return;

    auto pat = regex(`^([\s\w]+)(\.player)$`);

    foreach (fname; PVfs.enumerateFiles(searchdir)) {
      auto mr = matchFirst(fname, pat);
      if (mr.empty) continue;

      string pname = mr[1];
      PFile pfile = PVfs.openRead(searchdir ~ '/' ~ fname);
      if (pfile is null) continue;
      auto pdata = pfile.readAll();
      pfile.close();

      try {
        readPlayerData(pname, pdata);
      } catch (Exception e) {
        PUtil.outLog("Invalid player data in \"", fname, "\": ", e.msg);
      }
    }
  }

  void addNewTime(in RaceData rd) { alltimes[rd.mapname] ~= rd; }

  void setSkipSaves(ulong sk)
  {
    skipSaves = cast(long) sk;
    sc = 0;
  }

  void savePlayer() { writePlayerData(playername); }

  /// Saves the player's race data with possible skipping.
  void skipSavePlayer()
  {
    if (skipSaves <= -1) // save only at exit
      return;

    if (sc++ == skipSaves) {
      writePlayerData(playername);
      sc = 0;
    }
  }

  void addNewUnlock(string udata) { addNewUnlock(playername, udata); }

  void addNewUnlock(string pname, string udata) { allunlocks[pname][udata] = true; }

  UnlockData getUnlockData() { return getUnlockData(playername); }

  UnlockData getUnlockData(string pname)
  {
    auto p = pname in allunlocks;
    if (p is null) return UnlockData.init;
    return *p;
  }

  /// Best time for `mapname`, or -1.0f if none is available.
  float getBestTime(string mapname)
  {
    auto p = mapname in alltimes;
    if (p is null || (*p).length == 0) return -1.0f;

    float best = (*p)[0].totaltime;
    foreach (ref rd; *p)
      if (rd.totaltime < best) best = rd.totaltime;
    return best;
  }

  /// Best class time for `mapname`, or -1.0f if none is available.
  float getBestClassTime(string mapname, string carclass)
  {
    auto p = mapname in alltimes;
    if (p is null) return -1.0f;

    bool found_a_time = false;
    float bct = float.infinity;

    foreach (ref rd; *p)
      if (rd.carclass == carclass) {
        bct = min(bct, rd.totaltime);
        found_a_time = true;
      }

    if (!found_a_time) return -1.0f;

    return bct;
  }

  /// Retrieves best times list for `mapname`, sorted by `sortmethod`.
  /// For `mapname == ""` the current results list will be re-sorted.
  TimeEntry[] getCurrentTimes(string mapname, HISCORE1_SORT sortmethod)
  {
    if (mapname.length) {
      currenttimes = null;

      if (auto p = mapname in alltimes)
        foreach (ref rd; *p)
          currenttimes ~= TimeEntry(0, rd, false);

      sortAndUpdatePlaces();
    }

    sortCurrentTimes(sortmethod);
    return currenttimes;
  }

  TimeEntry[] getCurrentTimesHL(HISCORE1_SORT sortmethod)
  {
    sortCurrentTimes(sortmethod);
    return currenttimes;
  }

  /// Inserts race data and retrieves the updated highlighted times.
  TimeEntry[] insertAndGetCurrentTimesHL(in RaceData rd)
  {
    currenttimes = null;

    if (auto p = rd.mapname in alltimes)
      foreach (ref old; *p)
        currenttimes ~= TimeEntry(0, old, false);

    currenttimes ~= TimeEntry(0, rd, true); // the newest, highlighted time
    sortAndUpdatePlaces();
    alltimes[rd.mapname] ~= rd;
    return currenttimes;
  }

private:

  void sortAndUpdatePlaces()
  {
    sortCurrentTimes(HISCORE1_SORT.BY_TOTALTIME_ASC);

    ulong p = 1;
    foreach (ref te; currenttimes)
      te.place = p++;
  }

  void sortCurrentTimes(HISCORE1_SORT sortmethod)
  {
    bool delegate(in TimeEntry, in TimeEntry) cmp;

    final switch (sortmethod) {
      case HISCORE1_SORT.BY_TOTALTIME_DESC:
        cmp = (a, b) => a.rd.totaltime > b.rd.totaltime;
        break;
      case HISCORE1_SORT.BY_MAXSPEED_ASC:
        cmp = (a, b) => a.rd.maxspeed > b.rd.maxspeed;
        break;
      case HISCORE1_SORT.BY_MAXSPEED_DESC:
        cmp = (a, b) => a.rd.maxspeed < b.rd.maxspeed;
        break;
      case HISCORE1_SORT.BY_PLAYERNAME_ASC:
        cmp = (a, b) => a.rd.playername == b.rd.playername ? a.rd.totaltime < b.rd.totaltime
                                                            : a.rd.playername < b.rd.playername;
        break;
      case HISCORE1_SORT.BY_PLAYERNAME_DESC:
        cmp = (a, b) => a.rd.playername == b.rd.playername ? a.rd.totaltime < b.rd.totaltime
                                                            : a.rd.playername > b.rd.playername;
        break;
      case HISCORE1_SORT.BY_CARNAME_ASC:
        cmp = (a, b) => a.rd.carname == b.rd.carname ? a.rd.totaltime < b.rd.totaltime
                                                      : a.rd.carname < b.rd.carname;
        break;
      case HISCORE1_SORT.BY_CARNAME_DESC:
        cmp = (a, b) => a.rd.carname == b.rd.carname ? a.rd.totaltime < b.rd.totaltime
                                                      : a.rd.carname > b.rd.carname;
        break;
      case HISCORE1_SORT.BY_CARCLASS_ASC:
        cmp = (a, b) => a.rd.carclass == b.rd.carclass ? a.rd.totaltime < b.rd.totaltime
                                                        : a.rd.carclass < b.rd.carclass;
        break;
      case HISCORE1_SORT.BY_CARCLASS_DESC:
        cmp = (a, b) => a.rd.carclass == b.rd.carclass ? a.rd.totaltime < b.rd.totaltime
                                                        : a.rd.carclass > b.rd.carclass;
        break;
      case HISCORE1_SORT.BY_TOTALTIME_ASC:
        cmp = (a, b) => a.rd.totaltime < b.rd.totaltime;
        break;
    }

    currenttimes.sort!((a, b) => cmp(a, b));
  }

  /// Encryption and decryption key, or rather pad.
  /// WARNING: changing this invalidates all highscore files of previous versions!
  static immutable ubyte[] edkey = [
    0x02, 0x43, 0x5E, 0xAC, 0x2E, 0x40, 0xD2, 0x7F, 0x84, 0xFB, 0xA0, 0x53, 0x52, 0x05, 0x4E, 0xEC,
    0x1A, 0xAB, 0x58, 0x8D, 0x2E, 0xFA, 0xC6, 0x2F, 0x65, 0x99, 0x69, 0x3D, 0xBC, 0x38, 0x0E, 0x64,
    0x45, 0x4B, 0xD9, 0x4B, 0xE5, 0x51, 0x73, 0xB3, 0x8A, 0x4E, 0x1B, 0xC1, 0x80, 0x11, 0x73, 0x16,
    0xE6, 0x66, 0x63, 0x09, 0x3A, 0x29, 0x90, 0x7F, 0xEC, 0xF6, 0x6B, 0xA5, 0x23, 0x2E, 0x77, 0xEC,
    0xDF, 0xA0, 0x92, 0x12, 0xB9, 0x7F, 0x3E, 0x63, 0x44, 0x9A, 0x53, 0x59, 0x97, 0xE0, 0x91, 0xE2,
    0x48, 0x20, 0xAA, 0x5C, 0x68, 0x4C, 0x09, 0x20, 0x63, 0xA6, 0x0A, 0xED, 0x80, 0x21, 0x12, 0xF0,
    0xE3, 0x4A, 0x74, 0xCA, 0x8C, 0xE0, 0x88, 0xDE, 0xC8, 0x47, 0xC8, 0xB2, 0x5B, 0x3C, 0x58, 0xFB,
    0x93, 0xC1, 0x1F, 0xFE, 0xEE, 0x16, 0x7D, 0xC7, 0x32, 0x00, 0x09, 0xE5, 0x32, 0x60, 0x5F, 0x31,
    0x98, 0x12, 0x30, 0x4D, 0x5A, 0xC8, 0x72, 0xF7, 0x83, 0xFE, 0x9B, 0xF1, 0x49, 0x6B, 0x83, 0x79,
    0xD4, 0xD1, 0x99, 0x1D, 0xB2, 0x1A, 0xC4, 0xFB, 0xB4, 0x6F, 0x8F, 0xE7, 0xE8, 0x0C, 0xB6, 0x14,
    0x84, 0x70, 0x37, 0xBE, 0x18, 0x84, 0xC9, 0x8B, 0xD9, 0x3D, 0xDD, 0x25, 0x1C, 0x17, 0x45, 0x20,
    0xED, 0x78, 0xC6, 0x40, 0xCA, 0x55, 0xF2, 0x2A, 0x4A, 0x28, 0x62, 0x3F, 0x94, 0xEB, 0xC9, 0x62,
    0x3F, 0xCF, 0x16, 0x9D, 0x6A, 0x53, 0x04, 0xEE, 0xFC, 0x2E, 0x10, 0xFE, 0xB6, 0xA7, 0x5B, 0x27,
    0x4C, 0x22, 0x15, 0xF9, 0x00, 0x73, 0x10, 0x3A, 0x29, 0x3B, 0x30, 0xCC, 0x41, 0x86, 0x15, 0x35,
    0xF1, 0x22, 0x22, 0x67, 0xC0, 0xEB, 0xA1, 0xD9, 0x9A, 0x12, 0x3B, 0x98, 0x70, 0x22, 0x3D, 0x6E,
    0x08, 0xF7, 0xF4, 0x98, 0xFE, 0x5A, 0xD3, 0x80, 0xC8, 0xC3, 0x78, 0x8F, 0xBB, 0xAD, 0x50, 0xF0,
    0xF3, 0x8A, 0xDB, 0x9B, 0xD1, 0xBD, 0xB3, 0x57, 0x67, 0xC4, 0x7B, 0xB2, 0xF1, 0x1E, 0x0B, 0xF7,
    0xF8, 0xC0, 0xEF, 0x31, 0x25, 0x3A, 0x4A, 0xE3, 0xC9, 0xDC, 0xAC, 0x52, 0x19, 0xC4, 0xC9, 0xBE,
    0x83, 0xC3, 0xDC, 0x53, 0xEC, 0xD7, 0xD1, 0x64, 0xF8, 0x39, 0x57, 0xBA, 0x84, 0x62, 0xF1, 0xEA,
    0x5E, 0x12, 0x9D, 0xF8, 0x59, 0x3D, 0xAB, 0x07, 0xBC, 0x62, 0x6F, 0x86, 0x4E, 0x41, 0x54, 0x23,
    0xB4, 0xFE, 0x3A, 0xB7, 0x1C, 0xFC, 0x86, 0x24, 0x69, 0xB8, 0x5E, 0xB7, 0x17, 0xA6, 0xA8, 0x0B,
    0xD8, 0x5C, 0x8B, 0x6E, 0x74, 0x70, 0xD9, 0x35, 0xBB, 0xEF, 0xAF, 0xBA, 0xD5, 0xCB, 0x6D, 0x21,
    0x38, 0x75, 0xC1, 0x77, 0x58, 0xC1, 0x76, 0xA6, 0x3D, 0xE7, 0xB7, 0x0A, 0x08, 0x55, 0x9D, 0xDA,
    0x2B, 0x12, 0xC1, 0xAE, 0xDE, 0x27, 0xB0, 0x5D, 0x9B, 0x49, 0xDD, 0x76, 0xAC, 0xD0, 0xAE, 0x55,
    0x61, 0x7C, 0x36, 0xE4, 0x2A, 0x0B, 0xC7, 0x7F, 0xA4, 0x8C, 0x86, 0xDE, 0x39, 0x79, 0x5C, 0xE6,
    0x5B, 0xE7, 0xFF, 0x80, 0x45, 0xD7, 0xD9, 0xDE, 0xF9, 0xC2, 0xAC, 0x50, 0x84, 0xA7, 0xD9, 0x13,
    0x95, 0xC9, 0xEB, 0x6B, 0x7D, 0x66, 0x1E, 0x88, 0xFE, 0xA4, 0xE4, 0xC9, 0x8F, 0x00, 0xF1, 0x9F,
    0x3F, 0x8C, 0x04, 0x5F, 0x30, 0xDF, 0x43, 0x7A, 0x73, 0x27, 0xAD, 0x1D, 0x90, 0x79, 0x36, 0x95,
    0x1F, 0xCE, 0x4D, 0xBA, 0xED, 0x28, 0x93, 0xD5, 0x08, 0xA4, 0x0B, 0x5A, 0xCA, 0x42, 0x9D, 0x84,
    0x66, 0x85, 0x8B, 0xCF, 0x25, 0xED, 0xB8, 0x91, 0x88, 0x04, 0x4F, 0x87, 0xE6, 0xBC, 0xA8, 0x6D,
    0xAE, 0xA4, 0x8F, 0x5E, 0x30, 0xB6, 0x39, 0x45, 0xDD, 0x78, 0x49, 0x08, 0xC5, 0x78, 0x72, 0x02,
    0x13, 0xB3, 0xA2, 0x90, 0x17, 0x1D, 0xA3, 0xC6, 0xD1, 0xD1, 0x77, 0x20, 0x0C, 0x54, 0x05, 0x15,
    0xB3, 0x76, 0x53, 0x33, 0x50, 0x9B, 0xF8, 0xDD, 0x28, 0x62, 0x27, 0x02, 0x97, 0xEF, 0xE7, 0x21,
    0x0A, 0x70, 0x5D, 0x84, 0x44, 0xAA, 0x38, 0x0E, 0xB4, 0xDE, 0xCA, 0xFA, 0x22, 0x98, 0x96, 0xF5,
    0x8F, 0x4B, 0xA5, 0xF9, 0xAF, 0xDE, 0x87, 0xCD, 0x70, 0x68, 0x2B, 0xCB, 0x28, 0xA1, 0x89, 0x2E,
    0x6D, 0xB3, 0x68, 0xA0, 0xB6, 0xD9, 0x64, 0xDA, 0xF9, 0xD9, 0xCB, 0xE7, 0x04, 0x33, 0xF2, 0xB8,
    0xCA, 0xDC, 0x61, 0xFC, 0x63, 0x7E, 0xDA, 0xD2, 0x27, 0x36, 0x44, 0xC1, 0x6D, 0xA0, 0xDB, 0xBD,
    0xB3, 0x0F, 0xD6, 0xF1, 0x0D, 0x18, 0xA6, 0x6F, 0x5B, 0xD7, 0x4F, 0xE5, 0xCA, 0xEE, 0xA5, 0xCE,
    0x5C, 0xB1, 0x52, 0x2F, 0xB5, 0x0F, 0xBF, 0xD3, 0x19, 0x5A, 0x65, 0x6E, 0x4B, 0xE5, 0xC8, 0x37,
    0x27, 0xF8, 0x7A, 0x4D, 0xA3, 0x3E, 0x33, 0x37, 0xDE, 0x16, 0x03, 0x1A, 0xC6, 0x2E, 0x87, 0x01,
    0xAE, 0x6B, 0xB7, 0x39, 0xBD, 0xE8, 0x17, 0x9B, 0x58, 0x4B, 0x01, 0x82, 0xD6, 0x09, 0x50, 0xBE,
    0xF3, 0x78, 0x2D, 0xB2, 0xB8, 0x8B, 0x17, 0x50, 0x02, 0x03, 0xFE, 0x1F, 0x45, 0x76, 0xF7, 0xD6,
    0x63, 0xCA, 0x85, 0x10, 0x3A, 0x61, 0x6D, 0xD2, 0x69, 0x96, 0x5E, 0x64, 0x09, 0xE4, 0x80, 0xC2,
    0x23, 0x63, 0x2E, 0x46, 0xF2, 0x3D, 0x4C, 0xE1, 0x11, 0xD5, 0x8F, 0x33, 0xBE, 0x10, 0x25, 0x8F,
    0x11, 0x7D, 0x90, 0xCC, 0x3A, 0xA0, 0x47, 0x09, 0xD7, 0xA4, 0x3B, 0x77, 0x96, 0x61, 0xFE, 0x8D,
    0xDB, 0x0A, 0x1F, 0x1B, 0xCC, 0x44, 0x32, 0x65, 0x2B, 0xB9, 0x7F, 0x3C, 0x75, 0x58, 0x52, 0x82,
    0x48, 0x50, 0xE5, 0xE7, 0x34, 0x53, 0xFD, 0x7A, 0x17, 0xF8, 0xE1, 0x91, 0x73, 0x65, 0x82, 0xAD,
    0xDB, 0x1F, 0xA3, 0xA5, 0x19, 0x90, 0x38, 0xDF, 0x0A, 0x0D, 0x96, 0x69, 0x0D, 0xB9, 0xA6, 0x88,
    0x3C, 0xC0, 0x02, 0xEB, 0x0A, 0xBF, 0x03, 0x09, 0x9D, 0x2F, 0x39, 0xBC, 0x73, 0x97, 0x65, 0xB3,
    0x79, 0x5B, 0x69, 0xE4, 0xAE, 0xF9, 0x6F, 0x32, 0xC8, 0x47, 0xBF, 0x14, 0x8F, 0x6E, 0x78, 0xDE
  ];

  /// Encrypts or decrypts the player data (it is a plain XOR pad).
  static ubyte[] xorcrypt(const(ubyte)[] pdata)
  {
    auto r = pdata.dup;
    size_t k = 0;
    foreach (ref c; r) {
      if (k == edkey.length) k = 0;
      c ^= edkey[k++];
    }
    return r;
  }

  /// Reads the player name and race data into the `alltimes` collection.
  bool readPlayerData(string pname, const(ubyte)[] pdata)
  {
    string ts;
    RaceData rd = RaceData(pname);

    auto r = LineReader(cast(string) xorcrypt(pdata), 0);

    if (!r.getlineSkipEmpty(ts)) return false;
    ulong nu = to!ulong(strip(ts));

    while (nu-- != 0) {
      if (!r.getlineSkipEmpty(ts)) return false;
      allunlocks[pname][ts] = true;
    }

    while (readRaceData(r, rd))
      alltimes[rd.mapname] ~= rd;

    return true;
  }

  /// Writes the player's race data to his .PLAYER file. If `pname` is empty, nothing is saved.
  void writePlayerData(string pname)
  {
    if (pname.length == 0) return;
    if (!PVfs.isInit()) return;

    string pfname = searchdir ~ '/' ~ pname ~ ".player";
    auto sspdata = appender!string();

    // save unlock data
    if (auto u = pname in allunlocks) {
      sspdata ~= to!string((*u).length) ~ '\n';
      foreach (s; (*u).byKey)
        sspdata ~= s ~ '\n';
    } else
      sspdata ~= "0\n";

    sspdata ~= '\n';

    // save race data
    foreach (map, list; alltimes)
      foreach (ref rd; list)
        if (rd.playername == pname)
          sspdata ~= writeRaceData(rd);

    auto enc = xorcrypt(cast(const(ubyte)[]) sspdata.data);

    PFile pfile = PVfs.openWrite(pfname);
    if (pfile is null) {
      PUtil.outLog("pfname is \"", pfname, "\"");
      PUtil.outLog("PhysFS error: ", PVfs.lastError);
      return;
    }

    pfile.write(enc);
    pfile.close();
  }
}
