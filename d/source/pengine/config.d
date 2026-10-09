// config [pengine]
//
// Copyright (C) 2004-2006 Jasmine Langridge, ja-reiko@users.sourceforge.net
// License: GPL version 2 (see included gpl.txt)
//
// Loading and storing of configuration settings.
module pengine.config;

import std.conv : to;
import std.string : fromStringz, toStringz;

import bindings.gl;
import bindings.sdl2;
import pengine.app : PApp, PACKAGE_VERSION;
import pengine.cutil;
import pengine.pvfs;
import pengine.util;
import pengine.vmath;
import pengine.xml;
import psim.vehicle : MPH_ZERO_DEG, KPH_ZERO_DEG, MPS_MPH_DEG_MULT, MPS_KPH_DEG_MULT,
                      MPS_MPH_SPEED_MULT, MPS_KPH_SPEED_MULT;
import trigger.codriver : PCodriverUserConfig;
import trigger.mainapp : MainApp;

final class PConfig
{
  /// Unit of vehicle speed
  enum Speedunit {
    mph,  ///< Miles per hour
    kph   ///< Kilometers per hour
  }

  /// Snow flake style
  enum SnowFlakeType {
    point,    ///< Point shape
    square,   ///< Square shape
    textured  ///< Textured snow flake
  }

  struct UserControl {
    enum Type {
      TypeUnassigned,
      TypeKey,
      TypeJoyButton,
      TypeJoyAxis
    }
    alias TypeUnassigned = Type.TypeUnassigned;
    alias TypeKey = Type.TypeKey;
    alias TypeJoyButton = Type.TypeJoyButton;
    alias TypeJoyAxis = Type.TypeJoyAxis;

    static struct KeyData { SDL_Keycode sym; }
    static struct JoyButtonData { int button; }
    static struct JoyAxisData { int axis; float sign; float deadzone; float maxrange; } // more like half-axis, really

    Type type;
    union {
      KeyData key;
      JoyButtonData joybutton;
      JoyAxisData joyaxis;
    }
    // from 0.0 to 1.0 depending on activation level
    float value = 0;
  }

  enum Action {
    ActionForward,
    ActionBack,
    ActionLeft,
    ActionRight,
    ActionHandbrake,
    ActionUpshift,
    ActionDownshift,
    ActionRecover,
    ActionRecoverAtCheckpoint,
    ActionCamMode,
    ActionCamLeft,
    ActionCamRight,
    ActionShowMap,
    ActionShowUi,
    ActionShowCheckpoint,
    ActionPauseRace,
    ActionNext,
    ActionCount
  }
  // C++ style access: PConfig.ActionForward etc.
  alias ActionForward = Action.ActionForward;
  alias ActionBack = Action.ActionBack;
  alias ActionLeft = Action.ActionLeft;
  alias ActionRight = Action.ActionRight;
  alias ActionHandbrake = Action.ActionHandbrake;
  alias ActionUpshift = Action.ActionUpshift;
  alias ActionDownshift = Action.ActionDownshift;
  alias ActionRecover = Action.ActionRecover;
  alias ActionRecoverAtCheckpoint = Action.ActionRecoverAtCheckpoint;
  alias ActionCamMode = Action.ActionCamMode;
  alias ActionCamLeft = Action.ActionCamLeft;
  alias ActionCamRight = Action.ActionCamRight;
  alias ActionShowMap = Action.ActionShowMap;
  alias ActionShowUi = Action.ActionShowUi;
  alias ActionShowCheckpoint = Action.ActionShowCheckpoint;
  alias ActionPauseRace = Action.ActionPauseRace;
  alias ActionNext = Action.ActionNext;
  alias ActionCount = Action.ActionCount;

  struct Control {
    string[Action.ActionCount] action_name;
    UserControl[Action.ActionCount] map;
  }

  private MainApp mainapp;          ///< Used to some change settings in load function
  private XMLDocument xmlfile;      ///< In-memory copy of config file
  private XMLElement rootelem;      ///< Root element of XML config file
  private string cfgfilename = "";  ///< Path to XML configuration file

  // Config settings
  private string cfg_playername;
  private bool cfg_copydefplayers;

  private int cfg_video_cx, cfg_video_cy;
  private bool cfg_video_fullscreen;

  private float cfg_drivingassist;
  private bool cfg_enable_sound;
  private bool cfg_enable_codriversigns;
  private bool cfg_enable_fps;
  private bool cfg_enable_ghost;
  private bool cfg_automatic_transmission;

  private long cfg_skip_saves;

  /// Basic volume control.
  private float cfg_volume_engine = 0.33f;
  private float cfg_volume_sfx = 1.00f;
  private float cfg_volume_codriver = 1.00f;

  /// Search paths for the data directory, as read from the configuration.
  private string[] cfg_datadirs;

  private string cfg_codrivername;
  private string cfg_codriversigns;

  private PCodriverUserConfig cfg_codriveruserconfig;

  private Speedunit cfg_speed_unit;
  private float hud_speedo_start_deg;
  private float hud_speedo_mps_deg_mult;
  private float hud_speedo_mps_speed_mult;

  private SnowFlakeType cfg_snowflaketype = SnowFlakeType.point;

  private bool cfg_dirteffect = true;

  private GLfloat cfg_anisotropy = 1.0f;  ///< Anisotropic filter quality.
  private bool cfg_foliage = true;        ///< Foliage on/off flag.
  private bool cfg_roadsigns = true;      ///< Road signs on/off flag.
  private bool cfg_weather = true;        ///< Weather on/off flag.

  private Control ctrl;

  this(MainApp app)
  {
    mainapp = app;
  }

  private static bool yes(string v) { return v == "yes"; }

  /// Load configurations from files
  void loadConfig()
  {
    PUtil.outLog("Loading game configuration");

    // Set defaults
    cfg_playername = "Player";
    cfg_copydefplayers = true;

    cfg_video_cx = 640;
    cfg_video_cy = 480;
    cfg_video_fullscreen = false;

    cfg_drivingassist = 1.0f;
    cfg_enable_sound = true;
    cfg_enable_codriversigns = true;
    cfg_skip_saves = 5;
    cfg_volume_engine = 0.33f;
    cfg_volume_sfx = 1.0f;
    cfg_volume_codriver = 1.0f;
    cfg_anisotropy = 1.0f;
    cfg_foliage = true;
    cfg_roadsigns = true;
    cfg_weather = true;
    cfg_speed_unit = Speedunit.mph;
    cfg_snowflaketype = SnowFlakeType.point;
    cfg_dirteffect = true;
    cfg_enable_fps = false;
    cfg_enable_ghost = false;
    cfg_automatic_transmission = true;

    cfg_datadirs = null;

    hud_speedo_start_deg = MPH_ZERO_DEG;
    hud_speedo_mps_deg_mult = MPS_MPH_DEG_MULT;
    hud_speedo_mps_speed_mult = MPS_MPH_SPEED_MULT;

    ctrl.action_name[Action.ActionForward] = "forward";
    ctrl.action_name[Action.ActionBack] = "back";
    ctrl.action_name[Action.ActionLeft] = "left";
    ctrl.action_name[Action.ActionRight] = "right";
    ctrl.action_name[Action.ActionHandbrake] = "handbrake";
    ctrl.action_name[Action.ActionRecover] = "recover";
    ctrl.action_name[Action.ActionRecoverAtCheckpoint] = "recoveratcheckpoint";
    ctrl.action_name[Action.ActionCamMode] = "cammode";
    ctrl.action_name[Action.ActionCamLeft] = "camleft";
    ctrl.action_name[Action.ActionCamRight] = "camright";
    ctrl.action_name[Action.ActionShowMap] = "showmap";
    ctrl.action_name[Action.ActionPauseRace] = "pauserace";
    ctrl.action_name[Action.ActionShowUi] = "showui";
    ctrl.action_name[Action.ActionShowCheckpoint] = "showcheckpoint";
    ctrl.action_name[Action.ActionNext] = "next";
    ctrl.action_name[Action.ActionUpshift] = "upshift";
    ctrl.action_name[Action.ActionDownshift] = "downshift";

    for (int i = 0; i < Action.ActionCount; i++) {
      ctrl.map[i].type = UserControl.Type.TypeUnassigned;
      ctrl.map[i].value = 0.0f;
    }

    // Do config file management
    cfgfilename = "trigger-rally-" ~ PACKAGE_VERSION ~ ".config";

    if (!PVfs.exists(cfgfilename)) {
      version (UNIX) {
        static immutable string[] cfghidingplaces = ["/usr/share/games/trigger-rally/"];

        foreach (cfgpath; cfghidingplaces)
          if (!PVfs.mount(cfgpath, true))
            PUtil.outLog("Failed to add PhysFS search directory \"", cfgpath, "\"\nPhysFS: ", PVfs.lastError);
      }
      PUtil.outLog("No user config file, copying over defaults");

      string cfgdefaults = "trigger-rally.config.defs";

      if (!PUtil.copyFile(cfgdefaults, cfgfilename)) {
        PUtil.outLog("Couldn't create user config file. Proceeding with defaults.");

        cfgfilename = cfgdefaults;
      }
    }

    // Load actual settings from file
    xmlfile = new XMLDocument();
    rootelem = PUtil.loadRootElement(xmlfile, cfgfilename, "config");
    if (rootelem is null) {
      PUtil.outLog("Error: Couldn't load configuration file");
      PUtil.outLog("TinyXML: ", xmlfile.ErrorStr());
      PUtil.outLog("Your data paths are probably not set up correctly");
      throw MakePException("Boink");
    }

    string val;

    for (XMLElement walk = rootelem.FirstChildElement(); walk !is null; walk = walk.NextSiblingElement()) {
      const wv = walk.Value();
      if (wv == "player") {
        val = walk.Attribute("name");

        if (val !is null) {
          cfg_playername = val;
          mainapp.best_times.setPlayerName(val);
        }

        val = walk.Attribute("copydefplayers");

        if (val !is null && val == "no")
          cfg_copydefplayers = false;
        else
          cfg_copydefplayers = true;

        val = walk.Attribute("skipsaves");

        if (val !is null)
          cfg_skip_saves = to!long(val);

        mainapp.best_times.setSkipSaves(cast(ulong) cfg_skip_saves);
      } else if (wv == "video") {
        val = walk.Attribute("automatic");

        if (val !is null && val == "yes")
          mainapp.automaticVideoMode(true);
        else
          mainapp.automaticVideoMode(false);

        val = walk.Attribute("width");
        if (val) cfg_video_cx = atoi(val);

        val = walk.Attribute("height");
        if (val) cfg_video_cy = atoi(val);

        val = walk.Attribute("fullscreen");
        if (val) {
          if (val == "yes")
            cfg_video_fullscreen = true;
          else if (val == "no")
            cfg_video_fullscreen = false;
        }

        val = walk.Attribute("requirergb");
        if (val) {
          if (val == "yes") mainapp.requireRGB(true);
          else if (val == "no") mainapp.requireRGB(false);
        }

        val = walk.Attribute("requirealpha");
        if (val) {
          if (val == "yes") mainapp.requireAlpha(true);
          else if (val == "no") mainapp.requireAlpha(false);
        }

        val = walk.Attribute("requiredepth");
        if (val) {
          if (val == "yes") mainapp.requireDepth(true);
          else if (val == "no") mainapp.requireDepth(false);
        }

        val = walk.Attribute("requirestencil");
        if (val) {
          if (val == "yes") mainapp.requireStencil(true);
          else if (val == "no") mainapp.requireStencil(false);
        }

        val = walk.Attribute("stereo");
        if (val) {
          if (val == "none")
            mainapp.setStereoMode(PApp.StereoMode.StereoNone);
          else if (val == "quadbuffer")
            mainapp.setStereoMode(PApp.StereoMode.StereoQuadBuffer);
          else if (val == "red-blue")
            mainapp.setStereoMode(PApp.StereoMode.StereoRedBlue);
          else if (val == "red-green")
            mainapp.setStereoMode(PApp.StereoMode.StereoRedGreen);
          else if (val == "red-cyan")
            mainapp.setStereoMode(PApp.StereoMode.StereoRedCyan);
          else if (val == "yellow-blue")
            mainapp.setStereoMode(PApp.StereoMode.StereoYellowBlue);
        }

        float sepMult = 1.0f;
        val = walk.Attribute("stereoswapeyes");
        if (val && val == "yes")
          sepMult = -1.0f;

        val = walk.Attribute("stereoeyeseparation");
        if (val)
          mainapp.setStereoEyeSeperation(cast(float)(atof(val) * sepMult));
      } else if (wv == "audio") {
        val = walk.Attribute("enginevolume");
        if (val !is null) cfg_volume_engine = atof(val);

        val = walk.Attribute("sfxvolume");
        if (val !is null) cfg_volume_sfx = atof(val);

        val = walk.Attribute("codrivervolume");
        if (val !is null) cfg_volume_codriver = atof(val);
      } else if (wv == "graphics") {
        val = walk.Attribute("anisotropy");

        if (val) {
          if (val == "off") {
            cfg_anisotropy = 0.0f;
          } else if (val == "max") {
            glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, cfg_anisotropy);
          } else { // listen to the user, but don't trust him
            cfg_anisotropy = atof(val);
            CLAMP_LOWER(cfg_anisotropy, 1.0f);
          }
        }

        val = walk.Attribute("foliage");
        if (val) cfg_foliage = !(val == "no");

        val = walk.Attribute("roadsigns");
        if (val !is null) cfg_roadsigns = !(val == "no");

        val = walk.Attribute("weather");
        if (val) cfg_weather = !(val == "no");

        val = walk.Attribute("snowflaketype");
        if (val) {
          if (val == "square")
            cfg_snowflaketype = SnowFlakeType.square;
          else if (val == "textured")
            cfg_snowflaketype = SnowFlakeType.textured;
          else // default
            cfg_snowflaketype = SnowFlakeType.point;
        }

        val = walk.Attribute("dirteffect");
        if (val) cfg_dirteffect = (val == "yes");
      } else if (wv == "datadirectory") {
        for (XMLElement walk2 = walk.FirstChildElement(); walk2 !is null; walk2 = walk2.NextSiblingElement())
          if (walk2.Value() == "data") {
            auto p = walk2.Attribute("path");
            if (p !is null) cfg_datadirs ~= p;
          }
      } else if (wv == "parameters") {
        val = walk.Attribute("drivingassist");
        if (val) cfg_drivingassist = atof(val);

        val = walk.Attribute("enablesound");
        if (val) {
          if (val == "yes") cfg_enable_sound = true;
          else if (val == "no") cfg_enable_sound = false;
        }

        val = walk.Attribute("enablecodriversigns");
        if (val !is null) {
          if (val == "yes") cfg_enable_codriversigns = true;
          else if (val == "no") cfg_enable_codriversigns = false;
        }

        val = walk.Attribute("speedunit");
        if (val) {
          if (val == "mph") {
            cfg_speed_unit = Speedunit.mph;
            hud_speedo_start_deg = MPH_ZERO_DEG;
            hud_speedo_mps_deg_mult = MPS_MPH_DEG_MULT;
            hud_speedo_mps_speed_mult = MPS_MPH_SPEED_MULT;
          } else if (val == "kph") {
            cfg_speed_unit = Speedunit.kph;
            hud_speedo_start_deg = KPH_ZERO_DEG;
            hud_speedo_mps_deg_mult = MPS_KPH_DEG_MULT;
            hud_speedo_mps_speed_mult = MPS_KPH_SPEED_MULT;
          }
        }

        val = walk.Attribute("enablefps");
        if (val) {
          if (val == "yes") cfg_enable_fps = true;
          else if (val == "no") cfg_enable_fps = false;
        }

        val = walk.Attribute("enableghost");
        if (val) {
          if (val == "yes") cfg_enable_ghost = true;
          else if (val == "no") cfg_enable_ghost = false;
        }

        val = walk.Attribute("transmission");
        if (val) cfg_automatic_transmission = (val == "auto");

        val = walk.Attribute("codriver");
        if (val !is null) cfg_codrivername = val;

        val = walk.Attribute("codriversigns");
        if (val !is null) cfg_codriversigns = val;

        val = walk.Attribute("codriversignslife");
        if (val !is null) cfg_codriveruserconfig.life = to!float(val);

        val = walk.Attribute("codriversignsposx");
        if (val !is null) cfg_codriveruserconfig.posx = to!float(val);

        val = walk.Attribute("codriversignsposy");
        if (val !is null) cfg_codriveruserconfig.posy = to!float(val);

        val = walk.Attribute("codriversignsscale");
        if (val !is null) cfg_codriveruserconfig.scale = to!float(val);
      } else if (wv == "controls") {
        for (XMLElement walk2 = walk.FirstChildElement(); walk2 !is null; walk2 = walk2.NextSiblingElement()) {
          if (walk2.Value() == "keyboard") {
            val = walk2.Attribute("enable");
            if (val && val == "no")
              continue;

            for (XMLElement walk3 = walk2.FirstChildElement(); walk3 !is null; walk3 = walk3.NextSiblingElement()) {
              if (walk3.Value() == "key") {
                val = walk3.Attribute("action");

                int a = findAction(val);
                if (a >= Action.ActionCount) {
                  PUtil.outLog("Config ctrls: Unknown action \"", val, "\"");
                  continue;
                }

                val = walk3.Attribute("id");

                if (!val) {
                  PUtil.outLog("Config ctrls: Key has no ID");
                  continue;
                }

                ctrl.map[a].type = UserControl.Type.TypeKey;
                ctrl.map[a].key.sym = SDL_GetKeyFromName(val.toStringz);
              }
            }
          } else if (walk2.Value() == "joystick") {
            val = walk2.Attribute("enable");
            if (val && val == "no")
              continue;

            for (XMLElement walk3 = walk2.FirstChildElement(); walk3 !is null; walk3 = walk3.NextSiblingElement()) {
              if (walk3.Value() == "button") {
                val = walk3.Attribute("action");

                int a = findAction(val);
                if (a >= Action.ActionCount) {
                  PUtil.outLog("Config ctrls: Unknown action \"", val, "\"");
                  continue;
                }

                val = walk3.Attribute("index");
                if (!val) {
                  PUtil.outLog("Config ctrls: Joy button has no index");
                  continue;
                }

                ctrl.map[a].type = UserControl.Type.TypeJoyButton;
                ctrl.map[a].joybutton.button = atoi(val);
              } else if (walk3.Value() == "axis") {
                val = walk3.Attribute("action");

                int a = findAction(val);
                if (a >= Action.ActionCount) {
                  PUtil.outLog("Config ctrls: Unknown action \"", val, "\"");
                  continue;
                }

                val = walk3.Attribute("index");
                if (!val) {
                  PUtil.outLog("Config ctrls: Joy axis has no index");
                  continue;
                }

                int index = atoi(val);

                bool positive;

                val = walk3.Attribute("direction");
                if (!val) {
                  PUtil.outLog("Config ctrls: Joy axis has no direction");
                  continue;
                }
                if (val == "+")
                  positive = true;
                else if (val == "-")
                  positive = false;
                else {
                  PUtil.outLog("Config ctrls: Joy axis direction \"", val, "\" is neither \"+\" nor \"-\"");
                  continue;
                }

                ctrl.map[a].type = UserControl.Type.TypeJoyAxis;
                ctrl.map[a].joyaxis.axis = index;
                ctrl.map[a].joyaxis.sign = positive ? 1.0f : -1.0f;
                ctrl.map[a].joyaxis.deadzone = 0.0f;
                ctrl.map[a].joyaxis.maxrange = 1.0f;

                val = walk3.Attribute("deadzone");
                if (val) ctrl.map[a].joyaxis.deadzone = atof(val);

                val = walk3.Attribute("maxrange");
                if (val) ctrl.map[a].joyaxis.maxrange = atof(val);
              }
            }
          }
        }
      }
    }
  }

  private int findAction(string val)
  {
    int a;
    for (a = 0; a < Action.ActionCount; a++)
      if (val !is null && ctrl.action_name[a] == val) break;
    return a;
  }

  /// Store configuration to XML file
  void storeConfig()
  {
    PFile pfile = PVfs.openWrite(cfgfilename);

    if (pfile is null) {
      PUtil.outLog("Load failed: PhysFS: ", PVfs.lastError);
      return;
    }

    PUtil.outLog("Storing game configuration");

    for (XMLElement walk = rootelem.FirstChildElement(); walk !is null; walk = walk.NextSiblingElement()) {
      const wv = walk.Value();
      if (wv == "audio") {
        walk.SetAttribute("enginevolume", cfg_volume_engine);
        walk.SetAttribute("sfxvolume", cfg_volume_sfx);
        walk.SetAttribute("codrivervolume", cfg_volume_codriver);
      } else if (wv == "graphics") {
        if (cfg_anisotropy == 0.0f)
          walk.SetAttribute("anisotropy", "off");
        else
          walk.SetAttribute("anisotropy", to!string(cast(int) cfg_anisotropy));

        walk.SetAttribute("foliage", cfg_foliage ? "yes" : "no");
        walk.SetAttribute("roadsigns", cfg_roadsigns ? "yes" : "no");
        walk.SetAttribute("weather", cfg_weather ? "yes" : "no");

        final switch (cfg_snowflaketype) {
          case SnowFlakeType.point:
            walk.SetAttribute("snowflaketype", "point");
            break;
          case SnowFlakeType.square:
            walk.SetAttribute("snowflaketype", "quare"); // sic, as in the original
            break;
          case SnowFlakeType.textured:
            walk.SetAttribute("snowflaketype", "textured");
            break;
        }

        walk.SetAttribute("dirteffect", cfg_dirteffect ? "yes" : "no");
      } else if (wv == "parameters") {
        walk.SetAttribute("enablesound", cfg_enable_sound ? "yes" : "no");
        walk.SetAttribute("enablecodriversigns", cfg_enable_codriversigns ? "yes" : "no");
        walk.SetAttribute("speedunit", cfg_speed_unit == Speedunit.mph ? "mph" : "kph");
        walk.SetAttribute("enablefps", cfg_enable_fps ? "yes" : "no");
        walk.SetAttribute("enableghost", cfg_enable_ghost ? "yes" : "no");
        walk.SetAttribute("transmission", cfg_automatic_transmission ? "auto" : "manual");

        walk.SetAttribute("codriver", cfg_codrivername);
        walk.SetAttribute("codriversigns", cfg_codriversigns);
      } else if (wv == "controls") {
        for (XMLElement walk2 = walk.FirstChildElement(); walk2 !is null; walk2 = walk2.NextSiblingElement()) {
          if (walk2.Value() == "keyboard") {
            for (XMLElement walk3 = walk2.FirstChildElement(); walk3 !is null; walk3 = walk3.NextSiblingElement()) {
              if (walk3.Value() == "key") {
                string val = walk3.Attribute("action");
                int i = 0;

                while (i < Action.ActionCount) {
                  if (val !is null && ctrl.action_name[i] == val && ctrl.map[i].type == UserControl.Type.TypeKey) {
                    walk3.SetAttribute("id", fromStringz(SDL_GetKeyName(ctrl.map[i].key.sym)).idup);
                    break;
                  }
                  ++i;
                }

                if (i >= Action.ActionCount) {
                  PUtil.outLog("Config ctrls: Unknown action \"", val, "\"");
                  continue;
                }
              }
            }
          }
        }
      }
    }

    pfile.write(xmlfile.Print());
    pfile.close();
  }

  bool getFoliage() const { return cfg_foliage; }
  bool getRoadsigns() const { return cfg_roadsigns; }
  bool getWeather() const { return cfg_weather; }
  int getVideoCx() const { return cfg_video_cx; }
  int getVideoCy() const { return cfg_video_cy; }
  bool getVideoFullscreen() const { return cfg_video_fullscreen; }
  const(string)[] getDatadirs() const { return cfg_datadirs; }
  bool getCopydefplayers() const { return cfg_copydefplayers; }
  string getPlayername() const { return cfg_playername; }
  ref Control getCtrl() return { return ctrl; }
  float getVolumeCodriver() const { return cfg_volume_codriver; }
  PCodriverUserConfig getCodriveruserconfig() const { return cfg_codriveruserconfig; }
  bool getEnableCodriversigns() const { return cfg_enable_codriversigns; }
  string getCodriversigns() const { return cfg_codriversigns; }
  bool getEnableSound() const { return cfg_enable_sound; }
  string getCodrivername() const { return cfg_codrivername; }
  bool getDirteffect() const { return cfg_dirteffect; }
  bool getEnableGhost() const { return cfg_enable_ghost; }
  bool getAutomaticTransmission() const { return cfg_automatic_transmission; }
  float getDrivingassist() const { return cfg_drivingassist; }
  float getVolumeEngine() const { return cfg_volume_engine; }
  float getVolumeSfx() const { return cfg_volume_sfx; }
  SnowFlakeType getSnowflaketype() const { return cfg_snowflaketype; }
  bool getEnableFps() const { return cfg_enable_fps; }
  float getHudSpeedoMpsSpeedMult() const { return hud_speedo_mps_speed_mult; }
  Speedunit getSpeedUnit() const { return cfg_speed_unit; }
  GLfloat getAnisotropy() const { return cfg_anisotropy; }

  void setFoliage(bool foliage) { cfg_foliage = foliage; }
  void setRoadsigns(bool roadsigns) { cfg_roadsigns = roadsigns; }
  void setWeather(bool weather) { cfg_weather = weather; }
  void setVolumeCodriver(float volumeCodriver) { cfg_volume_codriver = volumeCodriver; }
  void setEnableCodriversigns(bool enableCodriversigns) { cfg_enable_codriversigns = enableCodriversigns; }
  void setCodriversigns(string codriversigns) { cfg_codriversigns = codriversigns; }
  void setCodrivername(string codrivername) { cfg_codrivername = codrivername; }
  void setDirteffect(bool dirteffect) { cfg_dirteffect = dirteffect; }
  void setEnableGhost(bool enableGhost) { cfg_enable_ghost = enableGhost; }
  void setAutomaticTransmission(bool automaticTransmission) { cfg_automatic_transmission = automaticTransmission; }
  void setVolumeEngine(float volumeEngine) { cfg_volume_engine = volumeEngine; }
  void setVolumeSfx(float volumeSfx) { cfg_volume_sfx = volumeSfx; }
  void setSnowflaketype(SnowFlakeType snowflaketype) { cfg_snowflaketype = snowflaketype; }
  void setEnableFps(bool enableFps) { cfg_enable_fps = enableFps; }
  void setSpeedUnit(Speedunit speedUnit) { cfg_speed_unit = speedUnit; }
  void setAnisotropy(GLfloat anisotropy) { cfg_anisotropy = anisotropy; }
}
