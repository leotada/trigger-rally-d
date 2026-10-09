// engine [psim]
// D port of engine.h / engine.cpp. License: GPL version 2
module psim.engine;

import pengine.vmath;

// RPM = revolutions per minute
// RPS = radians per second
float RPM_TO_RPS(float x) { return x * (PI / 30.0f); }
float RPS_TO_RPM(float x) { return x * (30.0f / PI); }

enum ShiftAction : int
{
  Automatic = -2,
  DownShift = -1,
  KeepGear = 0,
  UpShift = 1,
}

/// Data about performances of an engine
class PEngine
{
  // x = radians per second, y = output power
  private vec2f[] powercurve;
  private float[] gear;
  private float gearch_first = 0.4f;
  private float gearch_repeat = 0.15f;
  private float minRPS = 10000000.0f, maxRPS = 0.0f;

  float getPowerAtRPS(float rps)
  {
    size_t p;
    float power;

    // find which curve points rps lies between
    for (p = 0; p < powercurve.length && powercurve[p].x < rps; p++) {}

    if (p == 0) {
      // to the left of the graph
      power = powercurve[0].y * (rps / powercurve[0].x);
    } else if (p < powercurve.length) {
      // on the graph
      power = powercurve[p - 1].y + (powercurve[p].y - powercurve[p - 1].y) *
              ((rps - powercurve[p - 1].x) / (powercurve[p].x - powercurve[p - 1].x));
    } else {
      // to the right of the graph
      power = powercurve[p - 1].y + (0.0f - powercurve[p - 1].y) *
              ((rps - powercurve[p - 1].x) / (powercurve[$ - 1].x - powercurve[p - 1].x));
    }

    return power;
  }

  void addPowerCurvePoint(float rpm, float power)
  {
    if (rpm <= 0.0f) return;

    float rps = RPM_TO_RPS(rpm);
    powercurve ~= vec2f(rps, power);

    if (minRPS > rps)
      minRPS = rps;
    else if (maxRPS < rps)
      maxRPS = rps;
  }

  void addGear(float ratio)
  {
    if (hasGears()) {
      if (ratio <= getLastGearRatio()) return;
    } else {
      if (ratio <= 0.0f) return;
    }
    gear ~= ratio;
  }

  bool hasGears() { return gear.length != 0; }
  float getLastGearRatio() { return gear[$ - 1]; }

  float getHorsePower()
  {
    float bhp = 0;
    const float k = 1e-6;

    for (size_t i = 0; i != powercurve.length; i++)
      bhp = MAX(bhp, powercurve[i].y * RPS_TO_RPM(powercurve[i].x) * k);

    return bhp;
  }
}

/// current status of the engine
class PEngineInstance
{
  private PEngine engine;
  private float rps = 0;
  private int currentgear = 0;
  private int targetgear_rel = 0;
  private float gearch = 0.0f;
  private bool reverse = false;
  private float out_torque = 0.0f;
  private bool flag_gearchange = false;
  private int shiftdirection = 0;

  this(PEngine neweng) { engine = neweng; }

  void tick(float delta, float throttle, float wheel_rps, int shift)
  {
    rps = wheel_rps / engine.gear[currentgear];

    bool wasreverse = reverse;
    bool neg_throttle = (throttle < 0.0f);

    if (neg_throttle) {
      if ((shift == ShiftAction.Automatic) ||
          (currentgear == 0 && shift == ShiftAction.DownShift)) {
        shift = ShiftAction.KeepGear;
        reverse = true;
      }
    } else {
      if ((shift == ShiftAction.Automatic) ||
          (currentgear == 0 && shift == ShiftAction.UpShift)) {
        if (reverse)
          shift = ShiftAction.KeepGear;
        reverse = false;
      }
    }

    if (neg_throttle != reverse)
      throttle = 0.0f;

    if (wasreverse != reverse) {
      flag_gearchange = true;
      shiftdirection = reverse ? -1 : 1;
    }
    if (reverse) {
      rps *= -1.0f;
      throttle *= -1.0f;
    }

    CLAMP_UPPER(throttle, 1.0f);
    CLAMP(rps, engine.minRPS, engine.maxRPS);

    if (reverse)
      currentgear = 0;

    out_torque = engine.getPowerAtRPS(rps) / (engine.gear[currentgear] * rps);

    if (!reverse) {
      int newtarget_rel = 0;

      if (shift == ShiftAction.Automatic) {
        if (currentgear < cast(int) engine.gear.length - 1) {
          float nextrate = rps * engine.gear[currentgear] / engine.gear[currentgear + 1];
          CLAMP(nextrate, engine.minRPS, engine.maxRPS);
          float nexttorque = engine.getPowerAtRPS(nextrate) / (engine.gear[currentgear + 1] * nextrate);
          if (nexttorque > out_torque)
            newtarget_rel = 1;
        }

        if (currentgear > 0 && newtarget_rel == 0) {
          float nextrate = rps * engine.gear[currentgear] / engine.gear[currentgear - 1];
          CLAMP(nextrate, engine.minRPS, engine.maxRPS);
          float nexttorque = engine.getPowerAtRPS(nextrate) / (engine.gear[currentgear - 1] * nextrate);
          if (nexttorque > out_torque)
            newtarget_rel = -1;
        }
      } else {
        if ((currentgear > 0 && shift == ShiftAction.DownShift) ||
            (currentgear < cast(int) engine.gear.length - 1 && shift == ShiftAction.UpShift) ||
            (shift == ShiftAction.KeepGear)) {
          targetgear_rel = shift;
        }
      }

      if ((newtarget_rel != 0 && newtarget_rel == targetgear_rel) || shift != ShiftAction.Automatic) {
        if ((gearch -= delta) <= 0.0f || shift != ShiftAction.Automatic) {
          float nextrate = rps * engine.gear[currentgear] / engine.gear[currentgear + targetgear_rel];
          CLAMP(nextrate, engine.minRPS, engine.maxRPS);
          out_torque = engine.getPowerAtRPS(nextrate) / (engine.gear[currentgear + targetgear_rel] * nextrate);
          currentgear += targetgear_rel;
          gearch = engine.gearch_repeat;
          flag_gearchange = true;
          shiftdirection = targetgear_rel;
        }
      } else {
        gearch = engine.gearch_first;
        targetgear_rel = newtarget_rel;
      }
    }

    out_torque *= throttle;

    if (reverse)
      out_torque *= -1.0;

    out_torque -= wheel_rps * 0.1f;
  }

  float getOutputTorque() { return out_torque; }
  float getEngineRPS() { return rps; }
  float getEngineRPM() { return RPS_TO_RPM(rps); }

  int getCurrentGear() { return reverse ? -1 : currentgear; }

  bool getFlagGearChange()
  {
    bool ret = flag_gearchange;
    flag_gearchange = false;
    return ret;
  }

  int getShiftDirection() { return shiftdirection; }

  void doReset()
  {
    rps = engine.minRPS;
    currentgear = 0;
    targetgear_rel = 0;
    gearch = 0.0f;
    out_torque = 0.0f;
  }
}
