// vehicle [psim]
// D port of vehicle.h / vehicle.cpp. License: GPL version 2
module psim.vehicle;

import core.stdc.math : fabsf, fmodf;
import std.format : format;
import std.math : atan2, fmod;
import std.conv : to;

import pengine.cutil;
import pengine.model : PModel, PSSModel;
import pengine.subsys : PResource;
import pengine.terrain : PTerrain, PTerrainFoliage;
import pengine.util;
import pengine.vmath;
import pengine.xml;
import psim.collision;
import psim.damage;
import psim.engine;
import psim.psim;

// vehicle core types
enum v_core_type { car, tank, helicopter, plane, hovercraft }

// vehicle clip point types
enum v_clip_type { body_, drive_left, drive_right, hover }

// MPS = metres per second, KPH = km/h, MPH = miles/h
float MPS_TO_MPH(float x) { return x * 2.23693629f; }
float MPS_TO_KPH(float x) { return x * 3.6f; }

// Starting position in degrees, measured counter-clockwise from the x-axis.
enum MPH_ZERO_DEG = 210;
enum KPH_ZERO_DEG = 220;

// Degrees to rotate the speedo needle for each unit of speed
enum DEG_PER_MPH = 1.5f;
enum DEG_PER_KPH = 1.0f;

// Multiplier for mps to speed in some unit
enum float MPS_MPH_SPEED_MULT = 2.23693629f;
enum float MPS_KPH_SPEED_MULT = 3.6f;

// Multiplier for mps to degs on the speedo dial
enum float MPS_MPH_DEG_MULT = MPS_MPH_SPEED_MULT * DEG_PER_MPH;
enum float MPS_KPH_DEG_MULT = MPS_KPH_SPEED_MULT * DEG_PER_KPH;

/// Control status of a vehicle
struct v_control_s
{
  // shared
  float throttle = 0;
  float brake1 = 0, brake2 = 0;
  int shift = 0;
  vec3f turn;
  vec2f aim;

  // helicopter
  float collective = 0;

  void setZero()
  {
    throttle = 0.0f;
    brake1 = 0.0f;
    brake2 = 0.0f;
    turn = vec3f.zero();
    aim = vec2f.zero();
    collective = 0.0f;
    shift = ShiftAction.Automatic;
  }

  void setDefaultRates()
  {
    throttle = 10.0f;
    brake1 = 10.0f;
    brake2 = 10.0f;
    turn = vec3f(10.0f, 10.0f, 10.0f);
    aim = vec2f(10.0f, 10.0f);
    collective = 10.0f;
    shift = ShiftAction.Automatic;
  }

  /// ensure all the values are within range
  void clamp()
  {
    CLAMP(throttle, -1.0f, 1.0f);
    CLAMP(brake1, 0.0f, 1.0f);
    CLAMP(brake2, 0.0f, 1.0f);
    CLAMP(turn.x, -1.0f, 1.0f);
    CLAMP(turn.y, -1.0f, 1.0f);
    CLAMP(turn.z, -1.0f, 1.0f);
    CLAMP(aim.x, -1.0f, 1.0f);
    CLAMP(aim.y, -1.0f, 1.0f);
    CLAMP(collective, -1.0f, 1.0f);
  }
}

alias v_state_s = v_control_s;

struct vehicle_clip_s
{
  vec3f pt;
  v_clip_type type;
  float force = 0, dampening = 0;
}

/// A type of wheel and its stats
struct PVehicleTypeWheel
{
  vec3f pt;
  float radius = 0;
  float drive = 0, steer = 0, brake1 = 0, brake2 = 0;
  float force = 0;
  float dampening = 0;
  float friction = 0;
}

/// A type of part
final class PVehicleTypePart
{
  string name, parentname;
  int parent = -1;

  PReferenceFrame ref_local;
  PReferenceFrame render_ref_local;

  vehicle_clip_s[] clip;
  PVehicleTypeWheel[] wheel;
  PReferenceFrame[] flame;

  float scale = 1.0;
  PModel model;

  this()
  {
    ref_local = new PReferenceFrame();
    render_ref_local = new PReferenceFrame();
  }
}

// default vehicle type values
enum DEF_VEHICLE_NAME = "Vehicle";
enum DEF_VEHICLE_CLASS = "Unknown";
enum DEF_VEHICLE_MASS = 1;
enum DEF_VEHICLE_WHEELSCALE = 1;
enum DEF_VEHICLE_SPEED = 0;
enum DEF_VEHICLE_TURNSPEED_A = 1;
enum DEF_VEHICLE_TURNSPEED_B = 0;
enum DEF_VEHICLE_ANGDRAG = 1;
enum DEF_VEHICLE_LIFT = 1;

enum DEF_WHEEL_RADIUS = 1;
enum DEF_WHEEL_DRIVE = 0;
enum DEF_WHEEL_STEER = 0;
enum DEF_WHEEL_BRAKE1 = 0;
enum DEF_WHEEL_BRAKE2 = 0;
enum DEF_WHEEL_FORCE = 0;
enum DEF_WHEEL_DAMPENING = 0;
enum DEF_WHEEL_FRICTION = 0.02;

// When a car is reset, how much time to wait
enum VEHICLE_RESET_TIME = 3;
// When a car is upside down, how much time to wait before resetting
enum VEHICLE_UPSIDEDOWN_RESET_TIME = 4;

// This is a coefficent used to get the friction of a wheel or a clip with the ground
enum FRICTION_MAGIC_COEFF_CLIP = 10000;
enum FRICTION_MAGIC_COEFF_WHEEL = FRICTION_MAGIC_COEFF_CLIP * 50;

// How much of the wheel radius can the suspension be compressed
enum MAX_SUSPENSION_DEPTH_COEFF = 0.7;

// How much the vehicle sinks on the ground, besed of terrain resistance
enum SINK_COEFF = 0.26;

// How fast the wheel rotation velocity match with the velocity of the ground below
enum WHEEL_SPIN_VEL_UPDATE_RATIO = 0.1;

// under what distance from the ground the wheel will create a dust trail
enum MAX_DUST_TRAIL_HEIGHT = 0.05;

/// A model (type) of vehicle: e.g. name, specifications
class PVehicleType : PResource
{
  string proper_name;
  string proper_class;
  string pstat_wheeldrive;
  string pstat_roadholding;
  string pstat_enginepower;

  v_core_type coretype;
  float mass = 0;
  vec3f dims;

  PVehicleTypePart[] part;

  float wheelscale = 0;
  PModel wheelmodel;

  float driving_wheels_num = 0;

  PEngine engine;

  float inverse_drive_total = 0;
  float wheel_speed_multiplier = 0;

  struct Param
  {
    float speed = 0;
    vec3f turnspeed;
    float turnspeed_a = 0, turnspeed_b = 0; // turnspeed = a + b * speed
    vec2f fineffect; // x = rudder/fin (hz), y = tail (vt)
  }
  Param param;

  vec3f drag_coeff;
  vec3f ang_drag_coeff;
  float lift_coeff = 0;

  v_control_s ctrlrate;

  private bool locked;

  this() { engine = new PEngine(); }

  void unload() { part = null; }
  void setLocked(bool setLocked) { locked = setLocked; }
  bool getLocked() { return locked; }

  bool load(string filename, PSSModel ssModel)
  {
    if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
      PUtil.outLog("Loading vehicle type \"", filename, "\"");

    name = filename;

    unload();

    // defaults
    proper_name = DEF_VEHICLE_NAME;
    proper_class = DEF_VEHICLE_CLASS;

    mass = DEF_VEHICLE_MASS;
    dims = vec3f(1, 1, 1);

    wheelscale = DEF_VEHICLE_WHEELSCALE;
    wheelmodel = null;

    ctrlrate.setDefaultRates();

    param.speed = DEF_VEHICLE_SPEED;
    param.turnspeed = vec3f.zero();
    param.turnspeed_a = DEF_VEHICLE_TURNSPEED_A;
    param.turnspeed_b = DEF_VEHICLE_TURNSPEED_B;
    param.fineffect = vec2f.zero();

    driving_wheels_num = 0;

    // the scale of the values in the file
    float allscale = 1.0;

    float drive_total = 0.0f;

    vec3f drag = vec3f(1, 1, 1);
    float angdrag = DEF_VEHICLE_ANGDRAG;
    float lift = DEF_VEHICLE_LIFT;

    wheel_speed_multiplier = 0.0f;

    bool custom_dims = false;

    // Read stats from file
    auto xmlfile = new XMLDocument();
    XMLElement rootelem = PUtil.loadRootElement(xmlfile, filename, "vehicle");
    if (rootelem is null) {
      PUtil.outLog("Load failed: TinyXML error");
      return false;
    }

    string val;

    val = rootelem.Attribute("name");
    if (val !is null)
      proper_name = val;

    val = rootelem.Attribute("class");
    if (val !is null)
      proper_class = val;

    val = rootelem.Attribute("allscale");
    if (val !is null)
      allscale = atof(val);

    // vehicle type
    val = rootelem.Attribute("type");
    if (val is null || val.length == 0) {
      if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
        PUtil.outLog("Warning: <vehicle> element without type attribute");
      return false;
    }

    if (val == "car")
      coretype = v_core_type.car;
    else if (val == "tank")
      coretype = v_core_type.tank;
    else if (val == "helicopter")
      coretype = v_core_type.helicopter;
    else if (val == "plane")
      coretype = v_core_type.plane;
    else if (val == "hovercraft")
      coretype = v_core_type.hovercraft;
    else {
      if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
        PUtil.outLog("Error: <vehicle> has unrecognised type \"", val, "\"");
      return false;
    }

    for (XMLElement walk = rootelem.FirstChildElement(); walk !is null; walk = walk.NextSiblingElement()) {

      // generic params
      if (walk.Value() == "genparams") {

        val = walk.Attribute("mass");
        if (val !is null)
          mass = atof(val);

        val = walk.Attribute("dimensions");
        if (val !is null) {
          custom_dims = true;
          sscanf(val, "%f , %f , %f", &dims.x, &dims.y, &dims.z);
          dims *= allscale;
        }

        val = walk.Attribute("wheelscale");
        if (val !is null) wheelscale = atof(val);

        val = walk.Attribute("wheelmodel");
        if (val !is null) wheelmodel = ssModel.loadModel(PUtil.assemblePath(val, filename));

      // params
      } else if (walk.Value() == "ctrlparams") {

        val = walk.Attribute("speed");
        if (val !is null) param.speed = atof(val);

        val = walk.Attribute("turnspeed");
        if (val !is null) sscanf(val, "%f , %f , %f", &param.turnspeed.x, &param.turnspeed.y, &param.turnspeed.z);

        val = walk.Attribute("drag");
        if (val !is null) sscanf(val, "%f , %f , %f", &drag.x, &drag.y, &drag.z);

        val = walk.Attribute("angdrag");
        if (val !is null) angdrag = atof(val);

        val = walk.Attribute("lift");
        if (val !is null) sscanf(val, "%f", &lift);

        val = walk.Attribute("speedrate");
        if (val !is null) ctrlrate.throttle = atof(val);

        val = walk.Attribute("turnspeedrate");
        if (val !is null) sscanf(val, "%f , %f , %f", &ctrlrate.turn.x, &ctrlrate.turn.y, &ctrlrate.turn.z);

        val = walk.Attribute("turnspeedcoefficients");
        if (val !is null) sscanf(val, "%f , %f", &param.turnspeed_a, &param.turnspeed_b);

        val = walk.Attribute("fineffect");
        if (val !is null) sscanf(val, "%f , %f", &param.fineffect.x, &param.fineffect.y);

      // engine performance
      } else if (walk.Value() == "drivesystem") {

        for (XMLElement walk2 = walk.FirstChildElement(); walk2 !is null; walk2 = walk2.NextSiblingElement()) {
          if (walk2.Value() == "engine") {

            float powerscale = 1.0f;

            val = walk2.Attribute("powerscale");
            if (val !is null) powerscale = atof(val);

            for (XMLElement walk3 = walk2.FirstChildElement(); walk3 !is null; walk3 = walk3.NextSiblingElement()) {

              if (walk3.Value() == "powerpoint") {

                float in_rpm, in_power;

                val = walk3.Attribute("rpm");
                if (val is null) {
                  PUtil.outLog("Warning: failed to read engine RPM value");
                  continue;
                }
                in_rpm = atof(val);

                val = walk3.Attribute("power");
                if (val is null) {
                  PUtil.outLog("Warning: failed to read engine power value");
                  continue;
                }
                in_power = atof(val);

                engine.addPowerCurvePoint(in_rpm, in_power * powerscale);
              }
            }

          } else if (walk2.Value() == "gearbox") {

            for (XMLElement walk3 = walk2.FirstChildElement(); walk3 !is null; walk3 = walk3.NextSiblingElement()) {

              if (walk3.Value() == "gear") {

                val = walk3.Attribute("absolute");
                if (val !is null) {
                  engine.addGear(atof(val));
                } else {
                  val = walk3.Attribute("relative");
                  if (val is null) {
                    PUtil.outLog("Warning: gear has neither absolute nor relative value");
                    continue;
                  }

                  if (!engine.hasGears()) {
                    PUtil.outLog("Warning: first gear cannot use relative value");
                    continue;
                  }

                  engine.addGear(engine.getLastGearRatio() * atof(val));
                }
              }
            }

          }
        }
      // parts
      } else if (walk.Value() == "part") {
        auto vtp = new PVehicleTypePart();
        part ~= vtp;

        vtp.parent = -1;
        vtp.model = null;
        vtp.scale = 1.0;

        val = walk.Attribute("name");
        if (val !is null) vtp.name = val;

        val = walk.Attribute("parent");
        if (val !is null) vtp.parentname = val;

        val = walk.Attribute("pos");
        if (val !is null) {
          vec3f pos;
          if (sscanf(val, "%f , %f , %f", &pos.x, &pos.y, &pos.z) == 3)
            vtp.ref_local.setPosition(pos * allscale);
        }

        val = walk.Attribute("render_pos");
        if (val !is null) {
          vec3f render_pos;
          if (sscanf(val, "%f , %f , %f", &render_pos.x, &render_pos.y, &render_pos.z) == 3)
            vtp.render_ref_local.setPosition(render_pos * allscale);
        } else {
          // render pos is optional, it will fallback to the normal pos if missing
          vtp.render_ref_local.copyFrom(vtp.ref_local);
        }

        val = walk.Attribute("orientation");
        if (val !is null) {
          quatf ori;
          // note: w first, as per usual mathematical notation
          if (sscanf(val, "%f , %f , %f , %f", &ori.w, &ori.x, &ori.y, &ori.z) == 4)
            vtp.ref_local.setOrientation(ori);
          vtp.render_ref_local.setOrientation(ori);
        }

        val = walk.Attribute("scale");
        if (val !is null) vtp.scale = atof(val);

        val = walk.Attribute("model");
        if (val !is null) vtp.model = ssModel.loadModel(PUtil.assemblePath(val, filename));

        for (XMLElement walk2 = walk.FirstChildElement(); walk2 !is null; walk2 = walk2.NextSiblingElement()) {
          if (walk2.Value() == "clip") {
            vehicle_clip_s vc;

            vc.force = 0.0f;
            vc.dampening = 0.0f;

            val = walk2.Attribute("type");
            if (val is null || val.length == 0) {
              if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
                PUtil.outLog("Warning: <clip> element without type attribute");
              continue;
            }

            if (val == "body") vc.type = v_clip_type.body_;
            else if (val == "drive-left") vc.type = v_clip_type.drive_left;
            else if (val == "drive-right") vc.type = v_clip_type.drive_right;
            else if (val == "hover") vc.type = v_clip_type.hover;
            else {
              if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
                PUtil.outLog("Warning: <clip> has unrecognised type \"", val, "\"");
              continue;
            }

            val = walk2.Attribute("pos");
            if (val is null) {
              if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
                PUtil.outLog("Warning: <clip> has no pos attribute");
              continue;
            }
            sscanf(val, "%f , %f , %f", &vc.pt.x, &vc.pt.y, &vc.pt.z);
            vc.pt *= allscale;

            val = walk2.Attribute("force");
            if (val !is null) vc.force = atof(val);

            val = walk2.Attribute("dampening");
            if (val !is null) vc.dampening = atof(val);

            vtp.clip ~= vc;
          } else if (walk2.Value() == "wheel") {
            PVehicleTypeWheel vtw;

            vtw.radius = DEF_WHEEL_RADIUS;
            vtw.drive = DEF_WHEEL_DRIVE;
            vtw.steer = DEF_WHEEL_STEER;
            vtw.brake1 = DEF_WHEEL_BRAKE1;
            vtw.brake2 = DEF_WHEEL_BRAKE2;
            vtw.force = DEF_WHEEL_FORCE;
            vtw.dampening = DEF_WHEEL_DAMPENING;
            vtw.friction = DEF_WHEEL_FRICTION;

            val = walk2.Attribute("pos");
            if (val is null) {
              if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
                PUtil.outLog("Warning: <wheel> has no pos attribute");
              continue;
            }
            sscanf(val, "%f , %f , %f", &vtw.pt.x, &vtw.pt.y, &vtw.pt.z);
            vtw.pt *= allscale;

            val = walk2.Attribute("radius");
            if (val !is null) vtw.radius = atof(val);

            val = walk2.Attribute("drive");
            if (val !is null) vtw.drive = atof(val);

            val = walk2.Attribute("steer");
            if (val !is null) vtw.steer = atof(val);

            val = walk2.Attribute("brake1");
            if (val !is null) vtw.brake1 = atof(val);

            val = walk2.Attribute("brake2");
            if (val !is null) vtw.brake2 = atof(val);

            val = walk2.Attribute("force");
            if (val !is null) vtw.force = atof(val);

            val = walk2.Attribute("dampening");
            if (val !is null) vtw.dampening = atof(val);

            val = walk2.Attribute("friction");
            if (val !is null) vtw.friction = atof(val);

            vtp.wheel ~= vtw;
            drive_total += vtw.drive;
            wheel_speed_multiplier += 1.0f;
          } else if (walk2.Value() == "jetflame") {
            auto fl = new PReferenceFrame();
            vtp.flame ~= fl;

            val = walk2.Attribute("pos");
            if (val !is null) {
              vec3f pos;
              if (sscanf(val, "%f , %f , %f", &pos.x, &pos.y, &pos.z) == 3)
                fl.setPosition(pos * allscale);
            }

            val = walk2.Attribute("ori");
            if (val !is null) {
              quatf ori;
              if (sscanf(val, "%f , %f , %f , %f", &ori.w, &ori.x, &ori.y, &ori.z) == 4)
                fl.setOrientation(ori);
            }
          }
        }

        vtp.ref_local.updateMatrices();
      }
    }

    for (size_t i = 0; i < part.length; ++i) {
      if (part[i].parentname.length > 0) {
        size_t j;
        for (j = 0; j < part.length; ++j) {
          if (i == j) continue;
          if (part[i].parentname == part[j].name) {
            part[i].parent = cast(int) j;
            break;
          }
        }
        if (j >= part.length && PUtil.isDebugLevel(DEBUGLEVEL_TEST))
          PUtil.outLog("Warning: part \"", part[i].name,
                       "\" references non-existant parent \"", part[i].parentname, "\"");
      }
    }

    // compute road holding average and count number of driving wheels
    float road_holding = 0;
    uint wheel_num = 0;
    foreach (p; part) {
      foreach (ref w; p.wheel) {
        ++wheel_num;
        road_holding += w.friction;
        driving_wheels_num += w.drive;
      }
    }
    road_holding /= wheel_num;
    pstat_roadholding = format("%f", road_holding * 100);

    // avoid 0 as number of driving wheels
    if (driving_wheels_num == 0)
      driving_wheels_num = 1;

    // remove trailing spaces/points
    while (true) {
      if (pstat_roadholding.length && pstat_roadholding[$ - 1] == '0') {
        pstat_roadholding = pstat_roadholding[0 .. $ - 1];
        continue;
      } else if (pstat_roadholding.length && pstat_roadholding[$ - 1] == '.')
        pstat_roadholding = pstat_roadholding[0 .. $ - 1];
      break;
    }

    // get pstat of engine
    pstat_enginepower = format("%f", engine.getHorsePower());
    // remove decimals
    while (pstat_enginepower.length) {
      if (pstat_enginepower[$ - 1] == '.') {
        pstat_enginepower = pstat_enginepower[0 .. $ - 1];
        break;
      }
      pstat_enginepower = pstat_enginepower[0 .. $ - 1];
    }

    // assign pstat of driving wheels
    float[] wheels_drive;
    foreach (p; part)
      foreach (ref w; p.wheel)
        wheels_drive ~= w.drive;

    // standard four wheels layout
    if (wheels_drive.length == 4) {
      if (wheels_drive[0] > 0 && wheels_drive[1] > 0 && wheels_drive[2] > 0 && wheels_drive[3] > 0)
        pstat_wheeldrive = "4WD";
      else if (wheels_drive[0] > 0 && wheels_drive[1] > 0 && wheels_drive[2] == 0 && wheels_drive[3] == 0)
        pstat_wheeldrive = "FWD";
      else if (wheels_drive[0] == 0 && wheels_drive[1] == 0 && wheels_drive[2] > 0 && wheels_drive[3] > 0)
        pstat_wheeldrive = "RWD";
      else
        pstat_wheeldrive = "non standard layout";
    } else {
      uint wd = 0;
      foreach (d; wheels_drive)
        if (d > 0) ++wd;
      pstat_wheeldrive = to!string(wd) ~ " driving out of " ~ to!string(wheels_drive.length);
    }

    // Use model of the first part to compute dimensions
    if (!custom_dims) {
      auto extents = part[0].model.getExtents();
      dims.x = (extents[1].x - extents[0].x) * part[0].scale;
      dims.y = (extents[1].y - extents[0].y) * part[0].scale;
      dims.z = (extents[1].z - extents[0].z) * part[0].scale;
    }

    // linear drag coefficent
    const float drag_hack_area = 1.777777;
    const float drag_coefficent_front = 0.3 * drag.y;
    const float drag_coefficent_side = 0.8 * drag.x;
    const float drag_coefficent_bottom = 0.9 * drag.z;
    const float air_density = 1.2;
    const float drag_reference_area_front = dims.x * dims.z * drag_hack_area * 0.9;
    const float drag_reference_area_side = dims.y * dims.z * drag_hack_area * 0.75;
    const float drag_reference_area_bottom = dims.x * dims.y * drag_hack_area * 0.97;

    drag_coeff = vec3f(
      drag_coefficent_side * air_density * drag_reference_area_side * 0.5,
      drag_coefficent_front * air_density * drag_reference_area_front * 0.5,
      drag_coefficent_bottom * air_density * drag_reference_area_bottom * 0.5);

    // angular drag
    ang_drag_coeff = vec3f(
      62 * (dims.y + dims.z) * angdrag,
      62 * (dims.x + dims.z) * angdrag,
      62 * (dims.y + dims.x) * angdrag);

    // lift (downforce)
    const float wingspan = dims.x;
    const float chord = dims.y;
    const float F = -0.02 * lift;
    lift_coeff = 0.5 * wingspan * chord * F * air_density * drag_hack_area;

    // assign inverse_drive_total
    if (drive_total > 0.0f)
      inverse_drive_total = 1.0f / drive_total;
    else
      inverse_drive_total = 0.0f;

    if (wheel_speed_multiplier > 0.0f)
      wheel_speed_multiplier = 1.0f / wheel_speed_multiplier;

    return true;
  }
}

/// A wheel of a vehicle
final class PVehicleWheel
{
  float ride_pos, ride_vel;
  float spin_pos, spin_vel;
  float turn_pos;

  PReferenceFrame ref_world;
  PReferenceFrame ref_world_lowest_point;

  float skidding, dirtthrow;
  vec3f dirtthrowpos, dirtthrowvec;

  float bumplast, bumpnext, bumptravel;

  this()
  {
    ref_world = new PReferenceFrame();
    ref_world_lowest_point = new PReferenceFrame();
    reset();
  }

  void reset()
  {
    ride_pos = 0;
    ride_vel = 0;
    spin_pos = 0;
    spin_vel = 0;
    turn_pos = 0;
    bumplast = 0;
    bumpnext = 0;
    bumptravel = 0;
    skidding = 0;
    dirtthrow = 0;
    dirtthrowpos = vec3f.zero();
    dirtthrowvec = vec3f.zero();
  }

  /// Lowest point of the wheel, where it would touch the ground
  vec3f getLowestPoint()
  {
    vec3f wclip = ref_world_lowest_point.getPosition();
    wclip.z += INTERP(bumplast, bumpnext, bumptravel);
    return wclip;
  }
}

/// a vehicle point part, can have wheels attached
final class PVehiclePart
{
  PReferenceFrame ref_local, ref_world;
  PVehicleWheel[] wheel;
  PDamage damage;

  this()
  {
    ref_local = new PReferenceFrame();
    ref_world = new PReferenceFrame();
  }
}

/// a vehicle instance
final class PVehicle
{
  PSim sim;
  PVehicleType type;
  PRigidBody body_;
  PVehiclePart[] part;

  v_state_s state;
  PEngineInstance iengine;

  float blade_ang1 = 0.0f;

  int nextcp = 0;
  int nextcdcp = 0;
  int currentlap = 1;

  float reset_trigger_time = 0.0f;
  vec3f reset_pos;
  quatf reset_ori;
  float reset_time = 0.0f;

  float crunch_level = 0.0f, crunch_level_prev = 0.0f;

  v_control_s ctrl;

  float forwardspeed = 0.0f;
  float wheel_angvel = 0.0f;
  float wheel_speed = 0;
  float skid_level = 0;

  float offroadtime_begin = 0;
  float offroadtime_end = 0;
  float offroadtime_total = 0;

  /// exposes the rigid body under the name used by the rest of the game (`vehicle.body`)
  alias body = body_;

  this(PSim sim_parent, PVehicleType _type)
  {
    sim = sim_parent;
    type = _type;
    body_ = sim.createRigidBody();
    iengine = new PEngineInstance(type.engine);

    // vehicle mass is approximately meant to be cuboid
    body_.setMassCuboid(type.mass, type.dims);

    state.setZero();
    ctrl.setZero();

    // Set parts and wheels
    part = new PVehiclePart[type.part.length];
    for (size_t i = 0; i < part.length; i++) {
      part[i] = new PVehiclePart();
      part[i].ref_local.copyFrom(type.part[i].ref_local);

      part[i].wheel = new PVehicleWheel[type.part[i].wheel.length];
      for (size_t j = 0; j < part[i].wheel.length; j++) {
        part[i].wheel[j] = new PVehicleWheel();
        part[i].wheel[j].ref_world.setPosition(vec3f(0, 0, 1000000)); // FIXME
      }
      part[i].damage.setClip(type.part[i].clip);
    }

    updateParts();
  }

  PRigidBody getBody() { return body_; }

  float getEngineRPM() { return iengine.getEngineRPM(); }
  int getCurrentGear() { return iengine.getCurrentGear(); }
  bool getFlagGearChange() { return iengine.getFlagGearChange(); }
  float getCrashNoiseLevel()
  {
    if (crunch_level > crunch_level_prev) {
      float tmp = crunch_level - crunch_level_prev;
      crunch_level_prev = crunch_level;
      return tmp;
    } else {
      return 0.0f;
    }
  }
  float getWheelSpeed() { return wheel_speed; }
  float getSkidLevel() { return skid_level; }

  /// reset the vehicle anywhere it is (used when it get flipped or something)
  void doReset()
  {
    // some time has to pass before reset
    if (reset_time != 0.0f) return;

    reset_pos = body_.getPosition() + vec3f(0.0f, 0.0f, 2.0f);

    vec3f forw = makevec3f(body_.getOrientationMatrix().row[0]);
    float forwangle = atan2(forw.y, forw.x);

    quatf temp;
    temp.fromZAngle(forwangle);

    if (body_.getOrientation().dot(temp) < 0.0f) temp = temp * -1.0f;

    reset_ori = temp;

    reset();
  }

  /// reset the vehicle to a specific point
  void doReset(in vec3f pos, in quatf ori)
  {
    if (reset_time != 0.0f) return;

    reset_pos = pos;

    quatf temp = ori;

    if (body_.getOrientation().dot(temp) < 0.0f) temp = temp * -1.0f;

    reset_ori = temp;

    reset();
  }

  private void reset()
  {
    reset_time = VEHICLE_RESET_TIME;

    crunch_level = 0;
    crunch_level_prev = 0;

    foreach (p; part)
      foreach (w; p.wheel)
        w.reset();

    forwardspeed = 0;
    wheel_angvel = 0;
    wheel_speed = 0;
    skid_level = 0;

    iengine.doReset();

    state.setZero();
  }

  /// Physic simulation for the single vehicle
  void tick(const float delta)
  {
    // ensure control values are in valid range
    ctrl.clamp();

    // handle crunch noise level
    PULLTOWARD(crunch_level_prev, crunch_level, delta * 5.0f);
    PULLTOWARD(crunch_level, 0.0f, delta * 5.0f);

    // smooth out control values
    PULLTOWARD(state.throttle, ctrl.throttle, type.ctrlrate.throttle * delta);
    PULLTOWARD(state.brake1, ctrl.brake1, type.ctrlrate.brake1 * delta);
    PULLTOWARD(state.brake2, ctrl.brake2, type.ctrlrate.brake2 * delta);
    PULLTOWARD(state.turn.x, ctrl.turn.x, type.ctrlrate.turn.x * delta);
    PULLTOWARD(state.turn.y, ctrl.turn.y, type.ctrlrate.turn.y * delta);
    PULLTOWARD(state.turn.z, ctrl.turn.z, type.ctrlrate.turn.z * delta);
    PULLTOWARD(state.collective, ctrl.collective, type.ctrlrate.collective * delta);

    // prepare some useful data
    vec3f linvel = body_.getLinearVel();
    mat44f orimatt = body_.getInverseOrientationMatrix();
    vec3f angvel = body_.getAngularVel();
    vec3f loclinvel = body_.getWorldToLocVector(linvel);
    vec3f locangvel = body_.getWorldToLocVector(angvel);

    // if car is upside down, wait some seconds then reset
    if (orimatt.row[2].z <= 0.1f) {
      reset_trigger_time += delta;

      if (reset_trigger_time >= VEHICLE_UPSIDEDOWN_RESET_TIME)
        doReset();
    } else
      reset_trigger_time = 0.0f;

    // check for resetting to do
    if (reset_time > 0.0f) {
      vec3f pos = body_.getPosition();
      quatf ori = body_.getOrientation();

      PULLTOWARD(pos, reset_pos, delta * 2.0f);
      PULLTOWARD(ori, reset_ori, delta * 2.0f);

      body_.setPosition(pos);
      body_.setOrientation(ori);

      body_.setLinearVel(vec3f.zero());
      body_.setAngularVel(vec3f.zero());

      body_.updateMatrices();

      reset_time -= delta;
      if (reset_time <= 0.0f)
        reset_time = -2.0f;

      return;

    } else {
      reset_time += delta;
      if (reset_time > 0.0f)
        reset_time = 0.0f;
    }

    forwardspeed = loclinvel.y;

    // body turn control
    vec3f desiredturn = vec3f(
      state.turn.x * type.param.turnspeed.x,
      state.turn.y * type.param.turnspeed.y,
      state.turn.z * type.param.turnspeed.z);
    body_.addLocTorque(desiredturn * type.param.turnspeed_a);
    body_.addLocTorque((desiredturn - locangvel) * (type.param.turnspeed_b * loclinvel.y));

    // fin effect (torque due to drag)
    body_.addLocTorque(vec3f(-loclinvel.z * type.param.fineffect.y, 0.0, loclinvel.x * type.param.fineffect.x));

    // linear drag
    vec3f frc = -vec3f(
      loclinvel.x * fabsf(loclinvel.x) * type.drag_coeff.x,
      loclinvel.y * fabsf(loclinvel.y) * type.drag_coeff.y,
      loclinvel.z * fabsf(loclinvel.z) * type.drag_coeff.z);

    // angular drag
    body_.addLocTorque(-vec3f(
      locangvel.x * fabsf(locangvel.x) * type.ang_drag_coeff.x,
      locangvel.y * fabsf(locangvel.y) * type.ang_drag_coeff.y,
      locangvel.z * fabsf(locangvel.z) * type.ang_drag_coeff.z));

    // lift
    frc += vec3f(0, 0, SQUARED(forwardspeed) * type.lift_coeff);

    // VEHICLE TYPE POINT
    final switch (type.coretype) {

      case v_core_type.tank:
        if (part.length >= 3) {
          state.aim.x += ctrl.aim.x * delta * 0.5;
          if (state.aim.x < -PI) state.aim.x += 2.0 * PI;
          if (state.aim.x >= PI) state.aim.x -= 2.0 * PI;
          state.aim.y += ctrl.aim.y * delta * 0.5;
          CLAMP(state.aim.y, 0.0, 0.5);

          // NOTE: as in the C++ original this is a no-op, because getOrientation() returns a copy.
          {
            quatf o1 = part[1].ref_local.getOrientation();
            o1.fromThreeAxisAngle(vec3f(0.0, 0.0, -state.aim.x));
            quatf o2 = part[2].ref_local.getOrientation();
            o2.fromThreeAxisAngle(vec3f(-state.aim.y, 0.0, 0.0));
          }

          part[1].ref_local.updateMatrices();
          part[2].ref_local.updateMatrices();
        }
        break;

      case v_core_type.helicopter:
        break;

      case v_core_type.plane:
        frc.y += state.throttle * type.param.speed;
        break;

      case v_core_type.hovercraft:
        blade_ang1 = fmod(blade_ang1 + delta * 50.0 * state.throttle, 2.0 * PI);

        if (part.length >= 4) {
          state.aim.x += ctrl.aim.x * delta * 0.5;
          if (state.aim.x < -PI) state.aim.x += 2.0 * PI;
          if (state.aim.x >= PI) state.aim.x -= 2.0 * PI;
          state.aim.y += ctrl.aim.y * delta * 0.5;
          CLAMP(state.aim.y, 0.0, 0.5);

          // NOTE: no-ops in the original too (getOrientation() returns a copy).
          {
            quatf o1 = part[1].ref_local.getOrientation();
            o1.fromThreeAxisAngle(vec3f(0.0, blade_ang1, 0.0));
            quatf o2 = part[2].ref_local.getOrientation();
            o2.fromThreeAxisAngle(vec3f(0.0, 0.0, state.turn.z * -0.5));
          }

          part[1].ref_local.updateMatrices();
          part[2].ref_local.updateMatrices();
        }

        frc.y += state.throttle * type.param.speed;
        break;

      case v_core_type.car:
        break;
    }

    body_.addLocForce(frc);

    vec3f forwarddir = makevec3f(body_.getInverseOrientationMatrix().row[1]);

    // handle engine (output torque, change gear if needed...)
    iengine.tick(delta, state.throttle, wheel_angvel, ctrl.shift);

    // reset transmission control signal to default
    if (ctrl.shift != ShiftAction.Automatic)
      ctrl.shift = ShiftAction.KeepGear;

    // Output engine power delivered to each wheel
    float drivetorque = iengine.getOutputTorque() / type.driving_wheels_num;

    float turnfactor = state.turn.z;

    wheel_angvel = 0.0f;
    wheel_speed = 0.0f;
    skid_level = 0.0f;

    // the parts
    for (size_t i = 0; i < part.length; ++i) {
      // the clips of the part
      for (size_t j = 0; j < type.part[i].clip.length; ++j) {

        // the local clip coordinate
        vec3f lclip = type.part[i].clip[j].pt;
        // the world clip coordinate
        vec3f wclip = part[i].ref_world.getLocToWorldPoint(lclip);

        // where the clip *might* touch the ground
        PTerrain.ContactInfo tci;
        tci.pos.x = wclip.x;
        tci.pos.y = wclip.y;
        sim.getTerrain().getContactInfo(tci);

        // if the clip hovers let it hover
        if (type.part[i].clip[j].type == v_clip_type.hover) {
          if (tci.pos.z < 40.3) {
            tci.pos.z = 40.3;
            tci.normal = vec3f(0, 0, 1);
          }
        }

        // if the clip touches the ground
        if (wclip.z <= tci.pos.z) {
          // how much the clip enters the groud along the normal
          float depth = (tci.pos - wclip) * tci.normal;

          // clip velocity
          vec3f ptvel = body_.getLinearVelAtPoint(wclip);

          vec3f cfrc = vec3f.zero();

          switch (type.part[i].clip[j].type) {
            default:
            case v_clip_type.body_: {
              vec3f rightdir;
              if (tci.normal.x > 0.5f)
                rightdir = vec3f(0.0f, 1.0f, 0.0f);
              else
                rightdir = vec3f(1.0f, 0.0f, 0.0f);

              // forward direction
              vec3f surf_forward = tci.normal ^ rightdir;
              surf_forward.normalize();

              // lateral right dircetion
              vec3f surf_right = surf_forward ^ tci.normal;
              surf_right.normalize();

              // velocity along directions
              vec3f surfvel = vec3f(
                ptvel * surf_right, // lateral
                ptvel * surf_forward, // forward
                ptvel * tci.normal); // normal (perpendicular the ground)

              // how much force the clip put against the ground
              float perpforce =
                depth * type.part[i].clip[j].force
                - surfvel.z * type.part[i].clip[j].dampening;

              // if the clip pushes against the ground
              if (perpforce > 0.0f) {
                vec2f friction = vec2f(-surfvel.x, -surfvel.y) * FRICTION_MAGIC_COEFF_CLIP;

                float maxfriction = perpforce * 0.9f;
                float testfriction = perpforce * 1.2f;

                float leng = friction.length();

                if (leng > 0.0f && leng > testfriction)
                  friction *= (maxfriction / leng);

                cfrc += (tci.normal * perpforce +
                         surf_right * friction.x +
                         surf_forward * friction.y);

                part[i].damage.addDamage(tci.pos, perpforce * 0.0000001f, part[i].ref_world);
                CLAMP_LOWER(crunch_level, perpforce * 0.00001f);
              }
            } break;

            case v_clip_type.drive_left: {
              cfrc += vec3f(0.0, 0.0, type.part[i].clip[j].force);

              vec3f drivevec = forwarddir *
                               (state.throttle * type.param.speed +
                                state.turn.z * type.param.turnspeed.z);

              vec3f relvel = drivevec - tci.normal * (drivevec * tci.normal);

              cfrc += (ptvel - relvel) * -type.part[i].clip[j].dampening;

              cfrc *= depth;
            } break;

            case v_clip_type.drive_right: {
              cfrc += vec3f(0.0, 0.0, type.part[i].clip[j].force);

              vec3f drivevec = forwarddir *
                               (state.throttle * type.param.speed -
                                state.turn.z * type.param.turnspeed.z);

              vec3f relvel = drivevec - tci.normal * (drivevec * tci.normal);

              cfrc += (ptvel - relvel) * -type.part[i].clip[j].dampening;

              cfrc *= depth;
            } break;

            case v_clip_type.hover: {
              float surfvelz = ptvel * tci.normal;

              float perpfrc = type.part[i].clip[j].force;
              if (surfvelz < 0.0) perpfrc += surfvelz * -type.part[i].clip[j].dampening;

              cfrc += (tci.normal * perpfrc) * depth;
            } break;
          }

          body_.addForceAtPoint(cfrc, wclip);
        }
      }

      // The wheels
      for (size_t j = 0; j < type.part[i].wheel.length; ++j) {

        PVehicleWheel wheel = part[i].wheel[j];
        PVehicleTypeWheel typewheel = type.part[i].wheel[j];

        // terrain information
        const TerrainType mf_tt = sim.getTerrain().getRoadSurface(wheel.ref_world_lowest_point.getPosition());
        const float mf_coef = PUtil.decideFrictionCoef(mf_tt);
        const float mf_resis = PUtil.decideResistance(mf_tt);

        // where the wheel might touch the ground
        vec3f wclip = wheel.getLowestPoint();

        wheel.spin_vel += drivetorque * typewheel.drive * delta * (1.0f - mf_resis);

        // brakes affects wheel spin velocity
        float desiredchange = (state.brake1 * typewheel.brake1 +
                               state.brake2 * typewheel.brake2) * delta;
        if (wheel.spin_vel > desiredchange)
          wheel.spin_vel -= desiredchange;
        else if (wheel.spin_vel < -desiredchange)
          wheel.spin_vel += desiredchange;
        else
          wheel.spin_vel = 0.0f;

        // update wheel spin position
        wheel.spin_pos += wheel.spin_vel * delta;

        // update wheel spin velocity for the ground resistance
        wheel.spin_vel -= wheel.spin_vel * mf_resis * delta;

        // update wheel position respect steering axis
        wheel.turn_pos = turnfactor * typewheel.steer;

        wheel.dirtthrow = 0.0f;

        float suspension_force = wheel.ride_pos * typewheel.force;

        // update suspension velocity
        wheel.ride_vel +=
          (-suspension_force -
           wheel.ride_vel * typewheel.dampening) * 0.02 * delta;

        // update suspension position
        wheel.ride_pos += wheel.ride_vel * delta;

        // tci = the terrain point that shares the vertical with wclip
        PTerrain.ContactInfo tci;
        tci.pos.x = wclip.x;
        tci.pos.y = wclip.y;

        sim.getTerrain().getContactInfo(tci);

        // apply a bit of sinking depending of the material
        tci.pos.z -= SINK_COEFF * mf_resis;

        // further interaction only if the wheel touches the ground
        if (wclip.z <= tci.pos.z) {

          // bump velocity is proportional to the wheel spin velocity
          wheel.bumptravel += fabsf(wheel.spin_vel) * 0.6f * delta;

          // assign a new random bump if the bump velocity is too high
          if (wheel.bumptravel >= 1.0f) {
            wheel.bumplast = wheel.bumpnext;
            wheel.bumptravel -= cast(int) wheel.bumptravel;

            wheel.bumpnext = randm11() * rand01() * typewheel.radius * 0.1f;
          }

          // how much wheel is below the ground along the normal
          float depth = (tci.pos - wclip) * tci.normal;

          // wheel velocity
          vec3f ptvel = body_.getLinearVelAtPoint(wclip);

          vec3f wfrc = vec3f.zero();

          vec3f rightdir = makevec3f(wheel.ref_world.getInverseOrientationMatrix().row[0]);

          // the forward direction
          vec3f surf_forward = tci.normal ^ rightdir;
          surf_forward.normalize();

          // the right side direction
          vec3f surf_right = surf_forward ^ tci.normal;
          surf_right.normalize();

          // add wheel rotation speed to ptvel
          ptvel += surf_forward * (-wheel.spin_vel * typewheel.radius) * (1.0f - mf_resis);

          // velocity along these three directions
          vec3f surfvel = vec3f(
            ptvel * surf_right,
            ptvel * surf_forward,
            ptvel * tci.normal);

          // with how much force the wheel pushes the ground
          float perpforce = suspension_force;

          if (surfvel.z < 0.0f)
            perpforce -= surfvel.z * typewheel.dampening;

          // suspension get pressed to keep the wheel above ground
          wheel.ride_pos += depth;

          float maxdepth = typewheel.radius * MAX_SUSPENSION_DEPTH_COEFF;

          // if the suspension get pressed too much
          if (wheel.ride_pos > maxdepth) {
            float overdepth = wheel.ride_pos - maxdepth;
            wheel.ride_pos = maxdepth;
            perpforce -= overdepth * surfvel.z * typewheel.dampening * 5.0f;
          }

          if (wheel.ride_vel < -surfvel.z)
            wheel.ride_vel = -surfvel.z;

          // further interaction only if the wheel pushes the ground
          if (perpforce > 0.0f) {

            vec2f friction = vec2f(-surfvel.x, -surfvel.y) * typewheel.friction * FRICTION_MAGIC_COEFF_WHEEL;

            float maxfriction = perpforce * mf_coef;

            float testfriction = perpforce * 1.0f;

            float leng = friction.length();

            // damage of a vehicle side impacting wheel
            float damage = part[i].damage.getDamage(typewheel.pt);

            if (leng > 0.0f && leng > testfriction)
              friction *= (maxfriction / leng) + typewheel.friction;

            // the force of the wheel
            wfrc += (
              tci.normal * perpforce +
              (surf_right * friction.x +
               surf_forward * friction.y) * (1.0f - 0.5f * damage));

            // update wheel spin velocity
            wheel.spin_vel -= (friction.y * typewheel.radius) * delta * WHEEL_SPIN_VEL_UPDATE_RATIO;

            // apply the force
            body_.addForceAtPoint(wfrc, wclip);

            wheel.dirtthrow = leng / maxfriction;
            skid_level += wheel.dirtthrow;

            // downward direction
            vec3f downward = surf_forward ^ rightdir;
            downward.normalize();

            if (wheel.spin_vel > 0.0f)
              downward += surf_forward * -0.3f;
            else
              downward += surf_forward * 0.3f;
            downward.normalize();

            // where to throw dirt
            wheel.dirtthrowpos = wheel.ref_world_lowest_point.getPosition();
            // how much fast throw
            wheel.dirtthrowvec =
              body_.getLinearVelAtPoint(wheel.dirtthrowpos) +
              (downward ^ rightdir) * (wheel.spin_vel * typewheel.radius);
          }
        }

        wheel.spin_pos = fmodf(wheel.spin_pos, PI * 2.0f);

        wheel_angvel += wheel.spin_vel * typewheel.drive;

        wheel_speed += wheel.spin_vel * typewheel.radius;
      }

      // Calculate collisions with world objects
      auto collision = new PCollision(type.part[i].clip, part[i].ref_world);
      const(PTerrainFoliage)[] foliage = sim.getTerrain().getFoliageAtPos(body_.getPosition());

      if (foliage !is null) {
        const contact = collision.checkContact(foliage);

        for (size_t j = 0; j < contact.length; ++j) {
          vec3f crashforce = vec3f.zero();
          vec3f ptvel = body_.getLinearVelAtPoint(body_.getPosition());

          // Prevent that vehicle gets stuck in an object
          if (collision.towardsContact(body_.getPosition(), contact[j].pos, ptvel * delta)) {
            const float crashthreshold = 0.025f;
            vec3f crashpoint = collision.getCrashPoint(body_.getPosition(), contact[j]);

            ptvel.x = -ptvel.x * contact[j].rigidity;
            ptvel.y = -ptvel.y * contact[j].rigidity;
            ptvel.z = 0.0f;

            // apply crash force [N] at center of object in X/Y direction (F=v*m/t)
            if (delta != 0.0f)
              crashforce = ptvel * type.mass / delta;
            body_.addForceAtPoint(crashforce, crashpoint);
            part[i].damage.addDamage(crashpoint, crashforce.length() * 0.0000001f, part[i].ref_world);

            // Trigger crash sound or amplify gravel sound
            if (contact[j].rigidity > crashthreshold)
              CLAMP_LOWER(crunch_level, crashforce.length() * 0.00001f);
            else
              skid_level += crashforce.length();
          }
        }
      }
    }

    wheel_angvel *= type.inverse_drive_total;

    wheel_speed *= type.wheel_speed_multiplier;

    skid_level *= type.wheel_speed_multiplier;
  }

  /// Checks if vehicle can have a dust trail. If at least one wheel touches the ground
  bool canHaveDustTrail()
  {
    for (size_t i = 0; i < part.length; ++i) {
      for (size_t j = 0; j < type.part[i].wheel.length; ++j) {
        vec3f wclip = part[i].wheel[j].getLowestPoint();

        PTerrain.ContactInfo tci;

        tci.pos.x = wclip.x;
        tci.pos.y = wclip.y;
        sim.getTerrain().getContactInfo(tci);

        if (wclip.z - tci.pos.z <= MAX_DUST_TRAIL_HEIGHT)
          return true;
      }
    }

    return false;
  }

  /// update parts world coord and orientation
  void updateParts()
  {
    for (size_t i = 0; i < part.length; ++i) {
      PReferenceFrame parent;
      if (type.part[i].parent > -1)
        parent = part[type.part[i].parent].ref_world;
      else
        parent = body_;

      part[i].ref_world.setOrientation(part[i].ref_local.getOrientation() * parent.getOrientation());

      part[i].ref_world.updateMatrices();

      part[i].ref_world.setPosition(parent.getPosition() +
                                    parent.getOrientationMatrix().transform1(part[i].ref_local.getPosition()));

      for (size_t j = 0; j < part[i].wheel.length; j++) {
        vec3f locpos = type.part[i].wheel[j].pt +
                       vec3f(0.0f, 0.0f, part[i].wheel[j].ride_pos);

        part[i].wheel[j].ref_world.setPosition(part[i].ref_world.getLocToWorldPoint(locpos));
        part[i].wheel[j].ref_world_lowest_point.setPosition(
          part[i].ref_world.getLocToWorldPoint(locpos - vec3f(0, 0, type.part[i].wheel[j].radius)));

        quatf turnang, spinang;
        turnang.fromZAngle(part[i].wheel[j].turn_pos);
        spinang.fromXAngle(part[i].wheel[j].spin_pos);

        part[i].wheel[j].ref_world.setOrientation(spinang * turnang * part[i].ref_world.getOrientation());

        part[i].wheel[j].ref_world.updateMatrices();
        part[i].wheel[j].ref_world_lowest_point.updateMatrices();
      }
    }
  }
}
