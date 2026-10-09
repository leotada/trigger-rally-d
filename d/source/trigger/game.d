// game [trigger]
//
// Copyright 2004-2006 Jasmine Langridge, jas@jareiko.net
// License: GPL version 2 (see included gpl.txt)
//
// Information about the race being played.
module trigger.game;

import core.stdc.stdlib : srand;
import std.math : cos, sin;
import std.conv : to;

import pengine.cutil;
import pengine.model;
import pengine.render;
import pengine.rigidity;
import pengine.terrain;
import pengine.util;
import pengine.vmath;
import pengine.xml;
import psim.psim;
import psim.vehicle;
import trigger.codriver;
import trigger.mainapp;
import trigger.menu;

enum CODRIVER_CHECKPOINT_RADIUS = 20;
enum CHECKPOINT_RADIUS = 30;

// default values for the simulation
enum DEF_NUM_LAPS = 1;
enum DEF_TARGET_TIME = 754.567f;
enum DEF_CLOUD_SCROLLRATE = 0.001;
enum DEF_FOG_DENSITY = 0.01;
enum DEF_FOG_DENSITY_SKY = 0.8;
enum DEF_RAIN = 0;
enum DEF_SNOWFALL = 0;
enum DEF_WATER_ENABLED = false;
enum DEF_WATER_HEIGHT = 0;
enum DEF_WATER_USERALPHA = false;
enum DEF_WATER_ALPHA = 1;
enum DEF_WATER_FIXEDALPHA = false;
enum DEF_CD_CHECKPT_ORDERED = true;

/// When the race finishes, how much time to wait before quitting
enum ENDGAME_TIMER = 5;

/// A checkpoint: basically just a coordinate
struct CheckPoint {
  vec3f pt;
}

/// Holds codriver checkpoint information.
struct CodriverCP {
  vec3f pt;
  string notes;
}

/// The status of the race ending
enum Gamefinish { not_finished, pass, fail }

/// Current state of the game
enum Gamestate { countdown, racing, finished }

/// Camera view mode
enum CameraMode { chase = 0, bumper, side, hood, periscope, count }

final class TriggerGame
{
  bool cdcheckpt_ordered = false;

  MainApp app;
  PSim sim;
  Gamestate gamestate;
  int randomseed;
  PVehicle[] vehicle;
  PVehicle uservehicle;
  PTerrain terrain;
  CheckPoint[] checkpt;
  CodriverCP[] codrivercheckpt;
  int number_of_laps = 1;

  PCodriverVoice cdvoice;
  PCodriverSigns cdsigns;

  PRigidity rigidity;

  immutable float offroadtime_penalty_multiplier = 2.5f;

  float coursetime;
  float othertime;
  float cptime;
  float targettime;

  string comment;

  vec3f start_pos;
  quatf start_ori;

  vec3f lastCkptPos;
  quatf lastCkptOri;

  struct Weather {
    struct Cloud { string texname; float scrollrate; }
    struct Fog { vec3f color; float density; float density_sky; }
    struct Precip { float rain; float snowfall; }
    Cloud cloud;
    Fog fog;
    Precip precip;
  }
  Weather weather;

  struct Water {
    bool enabled = false;
    float height = 0.0f;
    string texname = "";
    bool useralpha = false;
    bool fixedalpha = false;
    float alpha = 1.0f;
  }
  Water water;

  PVehicleType[] vehiclechoices;

  this(MainApp parent)
  {
    app = parent;
    cdvoice = new PCodriverVoice(app.getCodriverWords(), app.getCodriverVolume());
    cdsigns = new PCodriverSigns(app.getCodriverSigns(), app.getCodriverUserConfig());
    rigidity = new PRigidity();
  }

  /// Used for "real-time" counting of seconds, to scare the player.
  float getOffroadTime() const
  {
    return uservehicle.offroadtime_total + (coursetime - uservehicle.offroadtime_begin);
  }

  /// Loads vehicle types for the game (scans "/vehicles").
  bool loadVehicles()
  {
    if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
      PUtil.outLog("Loading vehicle information from \"/vehicles\"");

    if (sim is null)
      sim = new PSim();

    const vehiclefiles = PUtil.findFiles("/vehicles", ".vehicle");

    if (vehiclefiles.length) {
      foreach (vefi; vehiclefiles) {
        PUtil.outLog("Found vehicle: \"", vefi, "\"");

        PVehicleType vt = sim.loadVehicleType(vefi, app.getSSModel());

        if (vt !is null) {
          if (app.isVehicleLocked(vefi) && !app.isUnlockedByPlayer(vefi)) {
            PUtil.outLog("Vehicle \"", vefi, "\" is locked");
            vt.setLocked(true);
          } else {
            vt.setLocked(false);
          }
          vehiclechoices ~= vt;
        } else
          PUtil.outLog("Warning: failed to load vehicle from \"", vefi, "\"");
      }
    } else {
      PUtil.outLog("Error: there is no vehicle information");
      return false;
    }

    return true;
  }

  bool loadLevel(string filename)
  {
    if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
      PUtil.outLog("Loading level \"", filename, "\"");

    if (sim is null)
      sim = new PSim();

    sim.setGravity(vec3f(0, 0, -9.81f));

    start_pos = vec3f.zero();
    start_ori = quatf.identity();

    number_of_laps = DEF_NUM_LAPS;
    targettime = DEF_TARGET_TIME;

    weather.cloud.scrollrate = DEF_CLOUD_SCROLLRATE;
    weather.fog.color = vec3f(1, 1, 1);
    weather.fog.density = DEF_FOG_DENSITY;
    weather.fog.density_sky = DEF_FOG_DENSITY_SKY;
    weather.precip.rain = DEF_RAIN;
    weather.precip.snowfall = DEF_SNOWFALL;

    water.enabled = DEF_WATER_ENABLED;
    water.height = DEF_WATER_HEIGHT;
    water.useralpha = DEF_WATER_USERALPHA;
    water.alpha = DEF_WATER_ALPHA;
    water.fixedalpha = DEF_WATER_FIXEDALPHA;

    cdcheckpt_ordered = DEF_CD_CHECKPT_ORDERED;

    auto xmlfile = new XMLDocument();
    XMLElement rootelem = PUtil.loadRootElement(xmlfile, filename, "level");
    if (rootelem is null) return false;

    string val;

    val = rootelem.Attribute("comment");
    if (val !is null) comment = val;

    for (XMLElement walk = rootelem.FirstChildElement(); walk !is null; walk = walk.NextSiblingElement()) {

      if (walk.Value() == "terrain") {
        try {
          terrain = new PTerrain(walk, filename, app.getSSTexture(), rigidity,
                                 app.cfg.getFoliage(), app.cfg.getRoadsigns());
        } catch (PException e) {
          PUtil.outLog("Terrain problem: ", e.msg);
          return false;
        }
        sim.setTerrain(terrain);
      }
      else if (walk.Value() == "race") {
        vec2f coordscale = vec2f(1.0f, 1.0f);
        val = walk.Attribute("coordscale");
        if (val !is null) sscanf(val, "%f , %f", &coordscale.x, &coordscale.y);

        val = walk.Attribute("targettime");
        if (val !is null) targettime = atof(val);

        val = walk.Attribute("codrivercpmode");
        if (val !is null) {
          if (val == "ordered")
            cdcheckpt_ordered = true;
          else if (val == "free")
            cdcheckpt_ordered = false;
        }

        val = walk.Attribute("laps");
        if (val !is null) {
          try {
            number_of_laps = to!int(val);
          } catch (Exception e) {
            number_of_laps = 1;
          }

          if (number_of_laps < 1)
            number_of_laps = 1;
        }

        for (XMLElement walk2 = walk.FirstChildElement(); walk2 !is null; walk2 = walk2.NextSiblingElement()) {

          if (walk2.Value() == "checkpoint") {
            val = walk2.Attribute("coords");

            vec2f coords;

            if (val !is null) {
              if (sscanf(val, "%f , %f", &coords.x, &coords.y) == 2) {
                coords.x *= coordscale.x;
                coords.y *= coordscale.y;
              } else
                PUtil.outLog("Error reading checkpoint coords");
            } else {
              PUtil.outLog("Warning: checkpoint has no coords");
            }

            val = walk2.Attribute("notes");

            if (val !is null) {
              codrivercheckpt ~= CodriverCP(vec3f(coords.x, coords.y, terrain.getHeight(coords.x, coords.y)), val);
            } else {
              checkpt ~= CheckPoint(vec3f(coords.x, coords.y, terrain.getHeight(coords.x, coords.y)));
            }
          }
          else if (walk2.Value() == "startposition") {
            val = walk2.Attribute("pos");
            if (val !is null) sscanf(val, "%f , %f , %f", &start_pos.x, &start_pos.y, &start_pos.z);

            start_pos.x *= coordscale.x;
            start_pos.y *= coordscale.y;

            lastCkptPos = vec3f(start_pos.x, start_pos.y, terrain.getHeight(start_pos.x, start_pos.y) + 2.0f);

            val = walk2.Attribute("oridegrees");
            if (val !is null) {
              float deg = atof(val);
              start_ori.fromZAngle(-RADIANS(deg));
              lastCkptOri = start_ori;
            }

            val = walk2.Attribute("ori");
            if (val !is null) sscanf(val, "%f , %f , %f , %f", &start_ori.w, &start_ori.x, &start_ori.y, &start_ori.z);
          }
          else if (walk2.Value() == "codrivercp") {
            vec2f coords = vec2f(0.0f, 0.0f);
            string notes;

            val = walk2.Attribute("coords");

            if (val !is null) {
              if (sscanf(val, "%f , %f", &coords.x, &coords.y) == 2) {
                coords.x *= coordscale.x;
                coords.y *= coordscale.y;
              } else
                PUtil.outLog("Error reading codriver checkpoint coords");
            } else
              PUtil.outLog("Warning: codriver checkpoint has no coords");

            val = walk2.Attribute("notes");

            if (val !is null)
              notes = val;
            else
              PUtil.outLog("Warning: codriver checkpoint has no pace notes");

            codrivercheckpt ~= CodriverCP(vec3f(coords.x, coords.y, terrain.getHeight(coords.x, coords.y)), notes);
          }
        }
      }
      else if (walk.Value() == "weather") {
        val = walk.Attribute("cloudtexture");
        if (val !is null) weather.cloud.texname = PUtil.assemblePath(val, filename);

        val = walk.Attribute("cloudscrollrate");
        if (val !is null) weather.cloud.scrollrate = atof(val);

        val = walk.Attribute("fogcolor");
        if (val !is null) sscanf(val, "%f , %f , %f", &weather.fog.color.x, &weather.fog.color.y, &weather.fog.color.z);

        val = walk.Attribute("fogdensity");
        if (val !is null) weather.fog.density = atof(val);

        val = walk.Attribute("fogdensitysky");
        if (val !is null) weather.fog.density_sky = atof(val);

        val = walk.Attribute("rain");
        if (val !is null && app.cfg.getWeather()) weather.precip.rain = atof(val);

        val = walk.Attribute("snowfall");
        if (val !is null && app.cfg.getWeather())
          weather.precip.snowfall = atof(val);
      }
      else if (walk.Value() == "water") {
        water.enabled = true;

        val = walk.Attribute("height");
        if (val !is null)
          water.height = atof(val);

        val = walk.Attribute("watertexture");
        if (val !is null)
          water.texname = val;
        else
          water.texname = "";

        val = walk.Attribute("alpha");
        if (val !is null) {
          water.useralpha = true;
          water.alpha = atof(val);
        } else
          water.useralpha = false;

        val = walk.Attribute("fixedalpha");
        if (val !is null && val == "yes")
          water.fixedalpha = true;
      }
    }

    srand(1000);

    // if there are no checkpoints
    if (checkpt.length == 0) {
      enum cpsize = 3;

      vec2f[] temp1 = new vec2f[cpsize];

      float ang = randm11() * PI;

      temp1[0] = vec2f(cast(float) cos(cast(double) ang), cast(float) sin(cast(double) ang)) * (100.0f + rand01() * 300.0f);

      foreach (i; 1 .. cpsize) {
        ang += randm11() * (PI * 0.3f);

        temp1[i] = temp1[i - 1] + vec2f(cast(float) cos(cast(double) ang), cast(float) sin(cast(double) ang)) * (100.0f + rand01() * 300.0f);
      }

      checkpt = new CheckPoint[cpsize];

      foreach (i; 0 .. cpsize) {
        vec2f coords = temp1[i];
        checkpt[i].pt = vec3f(coords.x, coords.y, terrain.getHeight(coords.x, coords.y));
      }
    }

    // activate vehicle brakes
    foreach (v; vehicle) {
      v.ctrl.brake1 = 1.0f;
      v.ctrl.brake2 = 1.0f;
    }

    // do two seconds of simulations to have fine cars on ground
    sim.tick(2);

    coursetime = 0.0f;
    othertime = 3.0f;
    cptime = -4.0f;
    gamestate = Gamestate.countdown;

    return true;
  }

  /// Create a new vehicle and push it in the simulation
  void chooseVehicle(PVehicleType type)
  {
    PVehicle vh = sim.createVehicle(type, start_pos, start_ori);

    uservehicle = vh;

    if (vh !is null)
      vehicle ~= vh;
    else
      PUtil.outLog("Warning: failed to load vehicle");
  }

  private static bool offroad_earlier = false;

  void tick(float delta)
  {
    final switch (gamestate) {

      case Gamestate.countdown:
        othertime -= delta;
        if (othertime <= 0.0f) {
          othertime = ENDGAME_TIMER;
          gamestate = Gamestate.racing;
        }

        foreach (v; vehicle) {
          v.ctrl.setZero();
          v.ctrl.brake1 = 1.0f;
          v.ctrl.brake2 = 1.0f;
        }
        break;

      case Gamestate.racing:
        coursetime += delta;

        if (coursetime + uservehicle.offroadtime_total * offroadtime_penalty_multiplier > targettime
            && app.lss.state == AM_TOP_EVT_PREP) {
          gamestate = Gamestate.finished;
        }
        break;

      case Gamestate.finished:
        othertime -= delta;

        foreach (v; vehicle) {
          v.ctrl.brake1 = 1.0f;
          v.ctrl.throttle = 0.0f;
        }
        break;
    }

    sim.tick(delta);

    foreach (i, veh; vehicle) {
      const bodypos = veh.body_.getPosition();

      vec2f diff = makevec2f(checkpt[veh.nextcp].pt) - makevec2f(bodypos);

      const bool offroad_now = !terrain.getRmapOnRoad(bodypos);

      if (offroad_earlier) {
        if (!offroad_now) {
          offroad_earlier = false;
          veh.offroadtime_end = coursetime;
          veh.offroadtime_total += veh.offroadtime_end - veh.offroadtime_begin;
        }
      }
      else if (offroad_now) {
        offroad_earlier = true;
        veh.offroadtime_begin = coursetime;
      }

      if (diff.lengthsq() < CHECKPOINT_RADIUS * CHECKPOINT_RADIUS) {
        lastCkptPos = checkpt[veh.nextcp].pt + vec3f(0.0f, 0.0f, 2.0f);
        lastCkptOri = veh.body_.getOrientation();

        cptime = coursetime;

        if (++veh.nextcp >= cast(int) checkpt.length) {
          veh.nextcp = 0;
          ++veh.currentlap;
          if (i == 0 && veh.currentlap > number_of_laps) gamestate = Gamestate.finished;
        }
      }

      if (codrivercheckpt.length) {
        if (cdcheckpt_ordered) {
          diff = makevec2f(codrivercheckpt[veh.nextcdcp].pt) - makevec2f(veh.body_.getPosition());

          if (diff.lengthsq() < CODRIVER_CHECKPOINT_RADIUS * CODRIVER_CHECKPOINT_RADIUS) {
            cdvoice.say(codrivercheckpt[veh.nextcdcp].notes);
            cdsigns.set(codrivercheckpt[veh.nextcdcp].notes, coursetime);
            lastCkptPos = codrivercheckpt[veh.nextcdcp].pt + vec3f(0.0f, 0.0f, 2.0f);
            lastCkptOri = veh.body_.getOrientation();

            if (++veh.nextcdcp >= cast(int) codrivercheckpt.length)
              veh.nextcdcp = 0;
          }
        }
        else {
          foreach (j; 0 .. codrivercheckpt.length) {
            diff = makevec2f(codrivercheckpt[j].pt) - makevec2f(veh.body_.getPosition());

            if (diff.lengthsq() < CODRIVER_CHECKPOINT_RADIUS * CODRIVER_CHECKPOINT_RADIUS &&
                cast(int)(j + 1) != veh.nextcdcp) {
              cdvoice.say(codrivercheckpt[j].notes);
              cdsigns.set(codrivercheckpt[j].notes, coursetime);
              lastCkptPos = codrivercheckpt[j].pt + vec3f(0.0f, 0.0f, 2.0f);
              lastCkptOri = veh.body_.getOrientation();

              veh.nextcdcp = cast(int) j + 1;
              break;
            }
          }
        }
      }
    }
  }

  void resetAtCheckpoint(PVehicle veh)
  {
    veh.doReset(lastCkptPos, lastCkptOri);
  }

  void renderCodriverSigns()
  {
    cdsigns.render(coursetime);
  }

  bool isFinished() const
  {
    return (gamestate == Gamestate.finished) && (othertime <= 0.0f);
  }

  bool isRacing() const
  {
    return gamestate == Gamestate.racing;
  }

  Gamefinish getFinishState()
  {
    if (gamestate != Gamestate.finished)
      return Gamefinish.not_finished;
    if (coursetime + uservehicle.offroadtime_total * offroadtime_penalty_multiplier <= targettime)
      return Gamefinish.pass;
    else
      return Gamefinish.fail;
  }
}
