// mainapp [trigger]
//
// Copyright 2004-2006 Jasmine Langridge, jas@jareiko.net
// License: GPL version 2 (see included gpl.txt)
//
// The whole Trigger Rally game application (main.cpp + the logic part of menu.cpp).
module trigger.mainapp;

import core.stdc.math : fmodf;
import core.stdc.stdlib : srand;
import std.array : insertInPlace;
import std.ascii : isAlphaNum, toLower;
import std.math : abs, atan2, fabs, log;
import std.conv : to;

import bindings.gl;
import bindings.sdl2;
import pengine.app;
import pengine.audio;
import pengine.config;
import pengine.cutil;
import pengine.model;
import pengine.pvfs;
import pengine.render;
import pengine.terrain;
import pengine.texture;
import pengine.util;
import pengine.vmath;
import pengine.xml;
import psim.psim;
import psim.vehicle;
import psim.engine : ShiftAction;
import trigger.codriver;
import trigger.control;
import trigger.game;
import trigger.ghost;
import trigger.hiscore1;
import trigger.menu;
import trigger.option;
import trigger.mainrender;

enum PACKAGE_VERSION = "0.6.7";

enum AS_LOAD_1 = 1;
enum AS_LOAD_2 = 2;
enum AS_LOAD_3 = 3;
enum AS_LEVEL_SCREEN = 10;
enum AS_CHOOSE_VEHICLE = 11;
enum AS_IN_GAME = 12;
enum AS_END_SCREEN = 13;

// Best Times table font information, must be kept updated
enum float fa = 8.0f / 12.0f;     // Font Aspect
enum float fs = 20.0f;            // Font Size
enum float fw = fa * fs;          // Font Width

// X coordinate values for Best Times table labels
enum float XTIMES_PLAYERNAME = 100.0f + 4 * fw;
enum float XTIMES_CARNAME = 350.0f;
enum float XTIMES_CARCLASS = 475.0f;
enum float XTIMES_TOTALTIME = 700.0f;

struct TriggerLevel {
  string filename, name, description, comment, author, targettime, targettimeshort;

  float targettimefloat = 0.0f;

  PTexture tex_minimap;
  PTexture tex_screenshot;
}

/// An Event with its levels
struct TriggerEvent {
  string filename, name, comment, author, totaltime;

  bool locked = false;
  UnlockData unlocks;

  TriggerLevel[] levels;
}

/// Dirt particles slow down quickly (the original DirtParticleSystem::tick).
void tickDirtParticles(PParticleSystem psys, float delta)
{
  psys.tick(delta);

  foreach (ref p; psys.part)
    PULLTOWARD(p.linvel, vec3f.zero(), delta * 25.0f);
}

struct RainDrop {
  vec3f drop_pt, drop_vect;
  float life, prevlife;
}

struct SnowFlake {
  vec3f drop_pt;
  vec3f drop_vect;
  float life;
  float prevlife;
}

/// Returns the lowercase basename of `fn` when it matches `^(\w+)(\..+)$`, else null.
private string baseNameLower(string fn)
{
  size_t i = 0;
  while (i < fn.length && (isAlphaNum(fn[i]) || fn[i] == '_')) i++;
  if (i == 0 || i + 1 >= fn.length || fn[i] != '.') return null;
  char[] b = fn[0 .. i].dup;
  foreach (ref c; b) c = cast(char) toLower(c);
  return b.idup;
}

/// This class is the whole Trigger Rally game.
final class MainApp : PApp
{
  int appstate;

  double hratio;
  double vratio;

  UnlockData player_unlocks;

  float splashtimeout;

  TriggerLevel[] levels;
  TriggerEvent[] events;

  Gui gui;
  POption option;
  PControl control;

  LevelState lss;

  PConfig cfg;

  HISCORE1_SORT hs_sort_method = HISCORE1_SORT.BY_TOTALTIME_ASC;
  RaceData race_data;
  TimeEntry[] current_times;

  TriggerGame game;

  PVehicleType vt_tank;

  PTexture tex_fontSourceCodeBold, tex_fontSourceCodeOutlined, tex_fontSourceCodeShadowed;

  PTexture tex_detail;
  PTexture[1] tex_sky;
  PTexture tex_water, tex_waterdefault, tex_dirt, tex_snowflake, tex_shadow,
           tex_hud_revs, tex_hud_revneedle, tex_hud_life, tex_hud_offroad,
           tex_loading_screen, tex_splash_screen, tex_end_screen,
           tex_race_no_screenshot, tex_race_no_minimap, tex_button_next, tex_button_prev,
           tex_damage_front_left, tex_damage_front_right, tex_damage_rear_left, tex_damage_rear_right;

  PTexture[string] tex_codriversigns;
  PAudioSample[string] aud_codriverwords;

  PParticleSystem psys_dirt;

  PAudioSample aud_engine, aud_wind, aud_shiftup, aud_shiftdown, aud_gravel, aud_crash1;

  PAudioInstance audinst_engine, audinst_wind, audinst_gravel;

  PAudioInstance[] audinst;

  float cloudscroll;

  vec3f campos, campos_prev;
  quatf camori;

  vec3f camvel;

  float nextcpangle;

  float cprotate;

  CameraMode cameraview;
  float camera_angle;
  float camera_user_angle;

  bool renderowncar;
  bool showmap;
  bool pauserace;
  bool showui;
  bool showcheckpoint;

  float crashnoise_timeout;

  RainDrop[] rain;
  SnowFlake[] snowfall;

  int loadscreencount;

  float choose_spin;

  int choose_type;

  float fpstime;
  uint fpscount;
  float fps;

  PGhost ghost;

  private float turnaccel = 0.0f;
  private float spinner = 0.0f;

  this(string title, string name)
  {
    super(title, name);
    gui = new Gui();
    cfg = new PConfig(this);
    option = new POption(gui, cfg);
    control = new PControl(gui, cfg);
    ghost = new PGhost(0.1f);
  }

  // --- forwarders for the protected PApp services, used by mainrender.d ---

  void doDrawModel(PModel model, float alpha) { drawModel(model, alpha); }

  void doStereoFrustum(float xmin, float xmax, float ymin, float ymax, float znear, float zfar, float zzps, float eye)
  {
    stereoFrustum(xmin, xmax, ymin, ymax, znear, zfar, zzps, eye);
  }

  // PApp's `cx`, `cy` are protected
  int screenW() { return cx; }
  int screenH() { return cy; }

  /// Checks if the given data was unlocked by the current player.
  bool isUnlockedByPlayer(string udata) const
  {
    return (udata in player_unlocks) !is null;
  }

  /// Checks if the given vehicle is locked.
  bool isVehicleLocked(string vefi) const
  {
    auto xmlfile = new XMLDocument();
    XMLElement rootelem = PUtil.loadRootElement(xmlfile, vefi, "vehicle");

    if (rootelem is null) {
      PUtil.outLog("Couldn't read vehicle \"", vefi, "\"");
      return false;
    }

    string val = rootelem.Attribute("locked");

    if (val !is null && val == "yes")
      return true;

    return false;
  }

  override void config()
  {
    PUtil.setDebugLevel(DEBUGLEVEL_DEVELOPER);

    cfg.loadConfig();
    setScreenMode(cfg.getVideoCx(), cfg.getVideoCy(), cfg.getVideoFullscreen());
    calcScreenRatios();

    if (cfg.getDatadirs().length == 0)
      throw MakePException("Data directory paths are empty: check your trigger-rally.config file.");

    foreach (datadir; cfg.getDatadirs()) {
      bool ok = PVfs.mount(datadir);
      if (!ok && datadir.length && datadir[0] != '/') {
        // also try relative to the executable directory
        ok = PVfs.mount(PVfs.getBaseDir() ~ datadir);
      }
      if (!ok) {
        PUtil.outLog("Failed to add PhysFS search directory \"", datadir, "\"");
        PUtil.outLog("PhysFS: ", PVfs.lastError);
      } else {
        PUtil.outLog("Main game data directory datadir=\"", datadir, "\"");
        break;
      }
    }

    if (cfg.getCopydefplayers())
      copyDefaultPlayers();

    best_times.loadAllTimes();
    player_unlocks = best_times.getUnlockData();

    PUtil.outLog("Player \"", cfg.getPlayername(), "\" unlocks:");
    foreach (s; player_unlocks.byKey)
      PUtil.outLog('\t', s);
  }

  override void load()
  {
    psys_dirt = null;

    audinst_engine = null;
    audinst_wind = null;
    audinst_gravel = null;
    game = null;

    if ((tex_loading_screen = getSSTexture().loadTexture("/textures/splash/loading.png")) is null)
      throw MakePException("Failed to load the Loading screen");

    if ((tex_splash_screen = getSSTexture().loadTexture("/textures/splash/splash.jpg")) is null)
      throw MakePException("Failed to load the Splash screen");

    appstate = AS_LOAD_1;

    loadscreencount = 3;

    splashtimeout = 0.0f;

    // Check that controls are available where requested
    // (can't be done in config because joy info not available)

    foreach (i; 0 .. cast(int) PConfig.ActionCount) {
      auto m = &cfg.getCtrl().map[i];

      final switch (m.type) {
        case PConfig.UserControl.TypeUnassigned:
          break;

        case PConfig.UserControl.TypeKey:
          if (m.key.sym <= 0)
            m.type = PConfig.UserControl.TypeUnassigned;
          break;

        case PConfig.UserControl.TypeJoyButton:
          if (0 >= getNumJoysticks() || m.joybutton.button >= getJoyNumButtons(0))
            m.type = PConfig.UserControl.TypeUnassigned;
          break;

        case PConfig.UserControl.TypeJoyAxis:
          if (0 >= getNumJoysticks() || m.joyaxis.axis >= getJoyNumAxes(0))
            m.type = PConfig.UserControl.TypeUnassigned;
          break;
      }
    }
  }

  /// Copies default players from data to user directory.
  void copyDefaultPlayers()
  {
    enum dppsearchdir = "/defplayers";
    enum dppdestdir = "/players";

    foreach (fname; PVfs.enumerateFiles(dppsearchdir)) {
      // reject files that are already in the user directory
      if (PVfs.exists(dppdestdir ~ '/' ~ fname)) {
        PUtil.outLog("Skipping copy of default player \"", fname, "\"");
        continue;
      }

      // reject files without .PLAYER extension (lowercase)
      enum ext = ".player";
      if (fname.length <= ext.length || fname[$ - ext.length .. $] != ext)
        continue;
      bool okname = true;
      foreach (c; fname[0 .. $ - ext.length])
        if (!(isAlphaNum(c) || c == '_' || c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v')) {
          okname = false;
          break;
        }
      if (!okname) continue;

      if (!PUtil.copyFile(dppsearchdir ~ '/' ~ fname, dppdestdir ~ '/' ~ fname))
        PUtil.outLog("Couldn't copy default player \"", fname, "\"");
    }
  }

  float getCodriverVolume() const { return cfg.getVolumeCodriver(); }

  PCodriverUserConfig getCodriverUserConfig() const { return cfg.getCodriveruserconfig(); }

  /// Returns event that unlocks the vehicle
  string getVehicleUnlockEvent(string vehiclename) const
  {
    foreach (ref ev; events) {
      foreach (s; ev.unlocks.byKey) {
        if (s == vehiclename)
          return ev.name;
      }
    }
    return "";
  }

  bool loadLevel(ref TriggerLevel tl)
  {
    tl.name = "Untitled";
    tl.description = "(no description)";
    tl.comment = "";
    tl.author = "";
    tl.targettime = "";
    tl.targettimeshort = "";
    tl.targettimefloat = 0.0f;
    tl.tex_minimap = null;
    tl.tex_screenshot = null;

    auto xmlfile = new XMLDocument();
    XMLElement rootelem = PUtil.loadRootElement(xmlfile, tl.filename, "level");
    if (rootelem is null) {
      PUtil.outLog("Couldn't read level \"", tl.filename, "\"");
      return false;
    }

    string val;

    val = rootelem.Attribute("name");
    if (val !is null) tl.name = val;

    val = rootelem.Attribute("description");
    if (val !is null) tl.description = val;

    val = rootelem.Attribute("comment");
    if (val !is null) tl.comment = val;
    val = rootelem.Attribute("author");
    if (val !is null) tl.author = val;

    val = rootelem.Attribute("screenshot");
    if (val !is null)
      tl.tex_screenshot = getSSTexture().loadTexture(PUtil.assemblePath(val, tl.filename));

    val = rootelem.Attribute("minimap");
    if (val !is null)
      tl.tex_minimap = getSSTexture().loadTexture(PUtil.assemblePath(val, tl.filename));

    for (XMLElement walk = rootelem.FirstChildElement(); walk !is null; walk = walk.NextSiblingElement()) {
      if (walk.Value() == "race") {
        val = walk.Attribute("targettime");
        if (val !is null) {
          tl.targettime = PUtil.formatTime(cast(float) atof(val));
          tl.targettimeshort = PUtil.formatTimeShort(cast(float) atof(val));
          tl.targettimefloat = atof(val);
        }
      }
    }

    return true;
  }

  bool loadLevelsAndEvents()
  {
    PUtil.outLog("Loading levels and events");

    // Find levels
    auto results = PUtil.findFiles("/maps", ".level");

    foreach (fn; results) {
      TriggerLevel tl;
      tl.filename = fn;

      if (!loadLevel(tl)) continue;

      // Insert level in alphabetical order
      size_t j = 0;
      while (j < levels.length && levels[j].name < tl.name) ++j;
      levels.insertInPlace(j, tl);
    }

    // Find events
    results = PUtil.findFiles("/events", ".event");

    foreach (fn; results) {
      TriggerEvent te;

      te.filename = fn;

      auto xmlfile = new XMLDocument();
      XMLElement rootelem = PUtil.loadRootElement(xmlfile, fn, "event");
      if (rootelem is null) {
        PUtil.outLog("Couldn't read event \"", fn, "\"");
        continue;
      }

      string val;

      val = rootelem.Attribute("name");
      if (val !is null) te.name = val;
      val = rootelem.Attribute("comment");
      if (val !is null) te.comment = val;
      val = rootelem.Attribute("author");
      if (val !is null) te.author = val;

      val = rootelem.Attribute("locked");

      te.locked = (val !is null && val == "yes");

      float evtotaltime = 0.0f;

      for (XMLElement walk = rootelem.FirstChildElement(); walk !is null; walk = walk.NextSiblingElement()) {

        if (walk.Value() == "unlocks") {
          val = walk.Attribute("file");

          if (val is null) {
            PUtil.outLog("Warning: Event has empty unlock");
            continue;
          }

          te.unlocks[val] = true;
        } else if (walk.Value() == "level") {

          TriggerLevel tl;

          val = walk.Attribute("file");
          if (val is null) {
            PUtil.outLog("Warning: Event level has no filename");
            continue;
          }
          tl.filename = PUtil.assemblePath(val, fn);

          if (loadLevel(tl)) {
            te.levels ~= tl;
            evtotaltime += tl.targettimefloat;
          }

          PUtil.outLog(tl.filename);
        }
      }

      if (te.levels.length <= 0) {
        PUtil.outLog("Warning: Event has no levels");
        continue;
      }

      te.totaltime = PUtil.formatTimeShort(evtotaltime);

      // Insert event in alphabetical order
      size_t j = 0;
      while (j < events.length && events[j].name < te.name) ++j;
      events.insertInPlace(j, te);
    }

    return true;
  }

  bool loadAll()
  {
    PTexture ld(string path, bool mip = true, bool clamp = false)
    {
      return getSSTexture().loadTexture(path, mip, clamp);
    }

    if ((tex_fontSourceCodeBold = ld("/textures/font-SourceCodeProBold.png")) is null) return false;
    if ((tex_fontSourceCodeOutlined = ld("/textures/font-SourceCodeProBoldOutlined.png")) is null) return false;
    if ((tex_fontSourceCodeShadowed = ld("/textures/font-SourceCodeProBoldShadowed.png")) is null) return false;

    if ((tex_end_screen = ld("/textures/splash/endgame.jpg")) is null) return false;

    if ((tex_hud_life = ld("/textures/life_helmet.png")) is null) return false;

    if ((tex_detail = ld("/textures/detail.jpg")) is null) return false;
    if ((tex_dirt = ld("/textures/dust.png")) is null) return false;
    if ((tex_shadow = ld("/textures/shadow.png", true, true)) is null) return false;

    if ((tex_hud_revneedle = ld("/textures/rev_needle.png")) is null) return false;

    if ((tex_hud_revs = ld("/textures/dial_rev.png")) is null) return false;

    if ((tex_hud_offroad = ld("/textures/offroad.png")) is null) return false;

    if ((tex_race_no_screenshot = ld("/textures/no_screenshot.png")) is null) return false;

    if ((tex_race_no_minimap = ld("/textures/no_minimap.png")) is null) return false;

    if ((tex_button_next = ld("/textures/button_next.png")) is null) return false;
    if ((tex_button_prev = ld("/textures/button_prev.png")) is null) return false;

    if ((tex_waterdefault = ld("/textures/water/default.png")) is null) return false;

    if ((tex_snowflake = ld("/textures/snowflake.png")) is null) return false;

    if ((tex_damage_front_left = ld("/textures/damage_front_left.png")) is null) return false;
    if ((tex_damage_front_right = ld("/textures/damage_front_right.png")) is null) return false;
    if ((tex_damage_rear_left = ld("/textures/damage_rear_left.png")) is null) return false;
    if ((tex_damage_rear_right = ld("/textures/damage_rear_right.png")) is null) return false;

    loadCodriversigns();

    if (cfg.getEnableSound()) {
      if ((aud_engine = getSSAudio().loadSample("/sounds/engine.wav", false)) is null) return false;
      if ((aud_wind = getSSAudio().loadSample("/sounds/wind.wav", false)) is null) return false;
      if ((aud_shiftup = getSSAudio().loadSample("/sounds/shiftup.wav", false)) is null) return false;
      if ((aud_shiftdown = getSSAudio().loadSample("/sounds/shiftdown.wav", false)) is null) return false;
      if ((aud_gravel = getSSAudio().loadSample("/sounds/gravel.wav", false)) is null) return false;
      if ((aud_crash1 = getSSAudio().loadSample("/sounds/bang.wav", false)) is null) return false;

      loadCodrivername();
    }

    if (!gui.loadColors("/menu.colors"))
      PUtil.outLog("Couldn't load (all) menu colors, continuing with defaults");

    if (!loadLevelsAndEvents()) {
      PUtil.outLog("Couldn't load levels/events");
      return false;
    }

    campos = campos_prev = vec3f(-15.0f, 0.0f, 30.0f);
    camori = quatf.identity();

    camvel = vec3f.zero();

    cloudscroll = 0.0f;

    cprotate = 0.0f;

    cameraview = CameraMode.chase;
    camera_user_angle = 0.0f;

    showmap = true;

    pauserace = false;

    showui = true;

    showcheckpoint = true;

    crashnoise_timeout = 0.0f;

    if (cfg.getDirteffect()) {
      psys_dirt = new PParticleSystem();
      psys_dirt.setColorStart(0.5f, 0.4f, 0.2f, 1.0f);
      psys_dirt.setColorEnd(0.5f, 0.4f, 0.2f, 0.0f);
      psys_dirt.setSize(0.1f, 0.5f);
      psys_dirt.setDecay(6.0f);
      psys_dirt.setTexture(tex_dirt);
      psys_dirt.setBlend(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    } else
      psys_dirt = null;

    choose_type = 0;

    choose_spin = 0.0f;

    return true;
  }

  /// Load configured set of co-driver signs
  void loadCodriversigns()
  {
    if (cfg.getEnableCodriversigns() && cfg.getCodriversigns().length) {
      const origdir = "/textures/CodriverSigns/" ~ cfg.getCodriversigns();

      foreach (fname; PVfs.enumerateFiles(origdir)) {
        PTexture tex_cdsign = getSSTexture().loadTexture(origdir ~ '/' ~ fname);

        if (tex_cdsign !is null) { // failed loads are ignored
          string basefname = baseNameLower(fname);
          if (basefname is null) continue;

          tex_codriversigns[basefname] = tex_cdsign;
        }
      }
    }
  }

  /// Load configured samples of co-driver voice
  void loadCodrivername()
  {
    if (cfg.getCodrivername().length && cfg.getCodrivername() != "mime") {
      const origdir = "/sounds/codriver/" ~ cfg.getCodrivername();

      foreach (fname; PVfs.enumerateFiles(origdir)) {
        PAudioSample aud_cdword = getSSAudio().loadSample(origdir ~ '/' ~ fname, false);

        if (aud_cdword !is null) { // failed loads are ignored
          string basefname = baseNameLower(fname);
          if (basefname is null) continue;

          aud_codriverwords[basefname] = aud_cdword;
        }
      }
    }
  }

  void reloadAll()
  {
    tex_codriversigns = null;
    loadCodriversigns();

    aud_codriverwords = null;
    loadCodrivername();
  }

  override void unload()
  {
    endGame(Gamefinish.not_finished);

    psys_dirt = null;
  }

  /// Prepare to start a new game (a race)
  bool startGame(string filename)
  {
    PUtil.outLog("Starting level \"", filename, "\"");

    // mouse is grabbed during the race
    grabMouse(true);

    game = new TriggerGame(this);

    if (!game.loadVehicles()) {
      PUtil.outLog("Error: failed to load vehicles");
      return false;
    }

    if (!game.loadLevel(filename)) {
      PUtil.outLog("Error: failed to load level");
      return false;
    }

    race_data.playername = cfg.getPlayername();
    race_data.mapname = filename;
    choose_type = 0;

    if (game.vehiclechoices.length > 1) {
      appstate = AS_CHOOSE_VEHICLE;
    } else {
      game.chooseVehicle(game.vehiclechoices[choose_type]);
      if (cfg.getEnableGhost())
        ghost.recordStart(filename, game.vehiclechoices[choose_type].getName());

      if (lss.state == AM_TOP_LVL_PREP) {
        const float bct = best_times.getBestClassTime(filename, game.vehicle[0].type.proper_class);

        if (bct >= 0.0f)
          game.targettime = bct;
      }

      initAudio();
      appstate = AS_IN_GAME;
    }

    // load the sky texture
    tex_sky[0] = null;

    if (game.weather.cloud.texname.length > 0)
      tex_sky[0] = getSSTexture().loadTexture(game.weather.cloud.texname);

    if (tex_sky[0] is null) {
      tex_sky[0] = getSSTexture().loadTexture("/textures/sky/blue.jpg");

      if (tex_sky[0] is null) tex_sky[0] = tex_detail; // last fallback...
    }

    // load water texture
    tex_water = null;

    if (game.water.texname.length)
      tex_water = getSSTexture().loadTexture(game.water.texname);

    if (tex_water is null)
      tex_water = tex_waterdefault;

    fpstime = 0.0f;
    fpscount = 0;
    fps = 0.0f;

    return true;
  }

  /// Turns game sound effects on or off. Codriver voice unaffected.
  void toggleSounds(bool to)
  {
    if (cfg.getEnableSound()) {
      if (audinst_engine !is null && !to) {
        audinst_engine.setGain(0.0f);
        audinst_engine.play();
      }

      if (audinst_wind !is null && !to) {
        audinst_wind.setGain(0.0f);
        audinst_wind.play();
      }

      if (audinst_gravel !is null && !to) {
        audinst_gravel.setGain(0.0f);
        audinst_gravel.play();
      }
    }
  }

  /// Initialize game sounds instances
  void initAudio()
  {
    if (cfg.getEnableSound()) {
      audinst_engine = new PAudioInstance(aud_engine, true);
      audinst_engine.setGain(0.0);
      audinst_engine.play();

      audinst_wind = new PAudioInstance(aud_wind, true);
      audinst_wind.setGain(0.0);
      audinst_wind.play();

      audinst_gravel = new PAudioInstance(aud_gravel, true);
      audinst_gravel.setGain(0.0);
      audinst_gravel.play();
    }
  }

  void endGame(Gamefinish state)
  {
    float coursetime = (state == Gamefinish.not_finished) ? 0.0f :
                       game.coursetime + game.uservehicle.offroadtime_total * game.offroadtime_penalty_multiplier;

    if (state != Gamefinish.not_finished && lss.state != AM_TOP_EVT_PREP) {
      race_data.carname = game.vehicle[0].type.proper_name;
      race_data.carclass = game.vehicle[0].type.proper_class;
      race_data.totaltime = game.coursetime + game.uservehicle.offroadtime_total * game.offroadtime_penalty_multiplier;
      race_data.maxspeed = 0.0f; // TODO: measure this too
      current_times = best_times.insertAndGetCurrentTimesHL(race_data).dup;
      best_times.skipSavePlayer();

      // show the best times
      if (lss.state == AM_TOP_LVL_PREP)
        lss.state = AM_TOP_LVL_TIMES;
      else if (lss.state == AM_TOP_PRAC_SEL_PREP)
        lss.state = AM_TOP_PRAC_TIMES;
    }

    if (cfg.getEnableGhost() && state != Gamefinish.not_finished) {
      ghost.recordStop(race_data.totaltime);
    }

    if (audinst_engine !is null) {
      audinst_engine.release();
      audinst_engine = null;
    }

    if (audinst_wind !is null) {
      audinst_wind.release();
      audinst_wind = null;
    }

    if (audinst_gravel !is null) {
      audinst_gravel.release();
      audinst_gravel = null;
    }

    foreach (a; audinst)
      a.release();
    audinst = null;

    if (game !is null) {
      game = null;
    }

    finishRace(state, coursetime);
  }

  void quitGame()
  {
    endGame(Gamefinish.not_finished);
    splashtimeout = 0.0f;
    appstate = AS_END_SCREEN;
  }

  /// Calculate screen ratios from the current screen width and height.
  void calcScreenRatios()
  {
    const cx = getWidth();
    const cy = getHeight();

    if (cx > cy) {
      hratio = cast(double) cx / cy;
      vratio = 1.0;
    } else if (cx < cy) {
      hratio = 1.0;
      vratio = cast(double) cy / cx;
    } else {
      hratio = 1.0;
      vratio = 1.0;
    }
  }

  override void tick(float delta)
  {
    switch (appstate) {
      case AS_LOAD_1:
        splashtimeout -= delta;
        if (--loadscreencount <= 0)
          appstate = AS_LOAD_2;
        break;
      case AS_LOAD_2:
        splashtimeout -= delta;
        if (!loadAll()) {
          requestExit();
          return;
        }
        appstate = AS_LOAD_3;
        break;
      case AS_LOAD_3:
        splashtimeout -= delta;
        if (splashtimeout <= 0.0f)
          levelScreenAction(AA_INIT, 0);
        break;

      case AS_LEVEL_SCREEN:
        tickStateLevel(delta);
        break;

      case AS_CHOOSE_VEHICLE:
        tickStateChoose(delta);
        break;

      case AS_IN_GAME:
        if (!pauserace)
          tickStateGame(delta);
        break;

      case AS_END_SCREEN:
        splashtimeout += delta * 0.04f;
        if (splashtimeout >= 1.0f)
          requestExit();
        break;

      default:
        break;
    }
  }

  void tickStateChoose(float delta)
  {
    choose_spin += delta * 2.0f;
  }

  void tickCalculateFps(float delta)
  {
    fpstime += delta;
    fpscount++;

    if (fpstime >= 0.1) {
      fps = fpscount / fpstime;
      fpstime = 0.0f;
      fpscount = 0;
    }
  }

  void tickStateGame(float delta)
  {
    PVehicle vehic = game.vehicle[0];

    if (game.isFinished()) {
      endGame(game.getFinishState());
      return;
    }

    cloudscroll = fmodf(cloudscroll + delta * game.weather.cloud.scrollrate, 1.0f);

    cprotate = fmodf(cprotate + delta * 1.0f, 1000.0f);

    // Do input/control processing

    auto map = cfg.getCtrl().map;
    alias UC = PConfig.UserControl;

    float prev_upshift_value = map[PConfig.ActionUpshift].value;
    float prev_downshift_value = map[PConfig.ActionDownshift].value;

    foreach (a; 0 .. cast(int) PConfig.ActionCount) {
      auto m = &cfg.getCtrl().map[a];

      final switch (m.type) {
        case UC.TypeUnassigned:
          break;

        case UC.TypeKey:
          m.value = keyDown(SDL_GetScancodeFromKey(m.key.sym)) ? 1.0f : 0.0f;
          break;

        case UC.TypeJoyButton:
          m.value = getJoyButton(0, m.joybutton.button) ? 1.0f : 0.0f;
          break;

        case UC.TypeJoyAxis:
          m.value = m.joyaxis.sign * getJoyAxis(0, m.joyaxis.axis);

          RANGEADJUST(m.value, m.joyaxis.deadzone, m.joyaxis.maxrange, 0.0f, 1.0f);

          CLAMP_LOWER(m.value, 0.0f);
          break;
      }
    }

    auto ctl = &cfg.getCtrl().map;

    // Bit of a hack for turning, because you simply can't handle analogue
    // and digital steering the same way, afaics

    if ((*ctl)[PConfig.ActionLeft].type == UC.TypeJoyAxis ||
        (*ctl)[PConfig.ActionRight].type == UC.TypeJoyAxis) {

      // Analogue mode
      vehic.ctrl.turn.z = 0.0f;
      vehic.ctrl.turn.z -= (*ctl)[PConfig.ActionLeft].value;
      vehic.ctrl.turn.z += (*ctl)[PConfig.ActionRight].value;

    } else {

      // Digital mode
      if ((*ctl)[PConfig.ActionLeft].value > 0.0f) {
        if (turnaccel > -0.0f) turnaccel = -0.0f;
        turnaccel -= 8.0f * delta;
        vehic.ctrl.turn.z += turnaccel * delta;
      } else if ((*ctl)[PConfig.ActionRight].value > 0.0f) {
        if (turnaccel < 0.0f) turnaccel = 0.0f;
        turnaccel += 8.0f * delta;
        vehic.ctrl.turn.z += turnaccel * delta;
      } else {
        PULLTOWARD(turnaccel, 0.0f, delta * 5.0f);
        PULLTOWARD(vehic.ctrl.turn.z, 0.0f, delta * 5.0f);
      }
    }

    // Computer aided steering
    if (vehic.forwardspeed > 1.0f)
      vehic.ctrl.turn.z -= vehic.body_.getAngularVel().z * cfg.getDrivingassist() / (1.0f + vehic.forwardspeed);

    float throttletarget = 0.0f;
    float braketarget = 0.0f;

    if ((*ctl)[PConfig.ActionForward].value > 0.0f) {
      if (vehic.wheel_angvel > -10.0f)
        throttletarget = (*ctl)[PConfig.ActionForward].value;
      else
        braketarget = (*ctl)[PConfig.ActionForward].value;
    }
    if ((*ctl)[PConfig.ActionBack].value > 0.0f) {
      if (vehic.wheel_angvel < 10.0f)
        throttletarget = -(*ctl)[PConfig.ActionBack].value;
      else
        braketarget = (*ctl)[PConfig.ActionBack].value;
    }

    PULLTOWARD(vehic.ctrl.throttle, throttletarget, delta * 15.0f);
    PULLTOWARD(vehic.ctrl.brake1, braketarget, delta * 25.0f);

    vehic.ctrl.brake2 = (*ctl)[PConfig.ActionHandbrake].value;

    int upshift = (prev_upshift_value < 1.0f && (*ctl)[PConfig.ActionUpshift].value > 0.0f) ? 1 : 0;
    int downshift = (prev_downshift_value < 1.0f && (*ctl)[PConfig.ActionDownshift].value > 0.0f) ? 1 : 0;

    if (cfg.getAutomaticTransmission())
      vehic.ctrl.shift = ShiftAction.Automatic;
    else
      vehic.ctrl.shift = upshift - downshift;

    game.tick(delta);

    // Record ghost car (assumes first vehicle is player vehicle)
    if (cfg.getEnableGhost() && game.vehicle[0] !is null) {
      ghost.recordSample(delta, game.vehicle[0].part[0]);
    }

    if (cfg.getDirteffect()) {

      enum BRIGHTEN_ADD = 0.20f;

      foreach (veh; game.vehicle) {
        foreach (j; 0 .. veh.part.length) {
          const bodydirtpos = veh.body_.getPosition();
          const bdi = PUtil.getDirtInfo(game.terrain.getRoadSurface(bodydirtpos));

          if (bdi.startsize >= 0.30f && veh.forwardspeed > 23.0f) {
            if (veh.canHaveDustTrail()) {
              const float sizemult = veh.forwardspeed * 0.035f;
              const vec3f bodydirtvec = vec3f(0, 0, 1);
              vec3f bodydirtcolor = game.terrain.getCmapColor(bodydirtpos);

              bodydirtcolor.x += BRIGHTEN_ADD;
              bodydirtcolor.y += BRIGHTEN_ADD;
              bodydirtcolor.z += BRIGHTEN_ADD;

              CLAMP(bodydirtcolor.x, 0.0f, 1.0f);
              CLAMP(bodydirtcolor.y, 0.0f, 1.0f);
              CLAMP(bodydirtcolor.z, 0.0f, 1.0f);
              psys_dirt.setColorStart(bodydirtcolor.x, bodydirtcolor.y, bodydirtcolor.z, 1.0f);
              psys_dirt.setColorEnd(bodydirtcolor.x, bodydirtcolor.y, bodydirtcolor.z, 0.0f);
              psys_dirt.setSize(bdi.startsize * sizemult, bdi.endsize * sizemult);
              psys_dirt.setDecay(bdi.decay);
              psys_dirt.addParticle(bodydirtpos, bodydirtvec);
            }
          } else
            foreach (k; 0 .. veh.part[j].wheel.length) {
              if (rand01() * 20.0f < veh.part[j].wheel[k].dirtthrow) {
                const dirtpos = veh.part[j].wheel[k].dirtthrowpos;
                const dirtvec = veh.part[j].wheel[k].dirtthrowvec;
                const di = PUtil.getDirtInfo(game.terrain.getRoadSurface(dirtpos));
                vec3f dirtcolor = game.terrain.getCmapColor(dirtpos);

                dirtcolor.x += BRIGHTEN_ADD;
                dirtcolor.y += BRIGHTEN_ADD;
                dirtcolor.z += BRIGHTEN_ADD;
                CLAMP(dirtcolor.x, 0.0f, 1.0f);
                CLAMP(dirtcolor.y, 0.0f, 1.0f);
                CLAMP(dirtcolor.z, 0.0f, 1.0f);
                psys_dirt.setColorStart(dirtcolor.x, dirtcolor.y, dirtcolor.z, 1.0f);
                psys_dirt.setColorEnd(dirtcolor.x, dirtcolor.y, dirtcolor.z, 0.0f);
                psys_dirt.setSize(di.startsize, di.endsize);
                psys_dirt.setDecay(di.decay);
                psys_dirt.addParticle(dirtpos, dirtvec);
              }
            }
        }
      }
    }

    float angtarg = 0.0f;
    angtarg -= (*ctl)[PConfig.ActionCamLeft].value;
    angtarg += (*ctl)[PConfig.ActionCamRight].value;
    angtarg *= PI * 0.75f;

    PULLTOWARD(camera_user_angle, angtarg, delta * 4.0f);

    quatf tempo;

    // allow temporary camera view changes for this frame
    CameraMode cameraview_mod = cameraview;

    if (game.gamestate == Gamestate.finished) {
      cameraview_mod = CameraMode.chase;
      spinner += 1.4f * delta;
      tempo.fromThreeAxisAngle(vec3f(-PI * 0.5f, 0.0f, spinner));
    } else {
      tempo.fromThreeAxisAngle(vec3f(-PI * 0.5f, 0.0f, 0.0f));
    }

    renderowncar = (cameraview_mod != CameraMode.hood && cameraview_mod != CameraMode.bumper);

    campos_prev = campos;

    PReferenceFrame rf = vehic.getBody();

    vec3f forw = makevec3f(rf.getOrientationMatrix().row[0]);
    float forwangle = atan2(forw.y, forw.x);

    mat44f cammat;

    switch (cameraview_mod) {

      default:
      case CameraMode.chase: {
        quatf temp2;
        temp2.fromZAngle(forwangle + camera_user_angle);

        quatf target = tempo * temp2;

        if (target.dot(camori) < 0.0f) target = target * -1.0f;

        PULLTOWARD(camori, target, delta * 3.0f);

        camori.normalize();

        cammat = camori.getMatrix();
        cammat = cammat.transpose();
        campos = rf.getPosition() +
                 makevec3f(cammat.row[1]) * 1.6f +
                 makevec3f(cammat.row[2]) * 5.0f;
        break;
      }

      case CameraMode.bumper: {
        quatf temp2;
        temp2.fromZAngle(camera_user_angle);

        quatf target = tempo * temp2 * rf.getOrientation();

        if (target.dot(camori) < 0.0f) target = target * -1.0f;

        PULLTOWARD(camori, target, delta * 25.0f);

        camori.normalize();

        cammat = camori.getMatrix();
        cammat = cammat.transpose();
        const rfmat = rf.getInverseOrientationMatrix();
        campos = rf.getPosition() +
                 makevec3f(rfmat.row[1]) * 1.7f +
                 makevec3f(rfmat.row[2]) * 0.4f;
        break;
      }

      // Right wheel
      case CameraMode.side: {
        quatf temp2;
        temp2.fromZAngle(camera_user_angle);

        quatf target = tempo * temp2 * rf.getOrientation();

        if (target.dot(camori) < 0.0f) target = target * -1.0f;

        camori = target;

        camori.normalize();

        cammat = camori.getMatrix();
        cammat = cammat.transpose();
        const rfmat = rf.getInverseOrientationMatrix();
        campos = rf.getPosition() +
                 makevec3f(rfmat.row[0]) * 1.1f +
                 makevec3f(rfmat.row[1]) * 0.3f +
                 makevec3f(rfmat.row[2]) * 0.1f;
        break;
      }

      case CameraMode.hood: {
        quatf temp2;
        temp2.fromZAngle(camera_user_angle);

        quatf target = tempo * temp2 * rf.getOrientation();

        if (target.dot(camori) < 0.0f) target = target * -1.0f;

        camori = target;

        camori.normalize();

        cammat = camori.getMatrix();
        cammat = cammat.transpose();
        const rfmat = rf.getInverseOrientationMatrix();
        campos = rf.getPosition() +
                 makevec3f(rfmat.row[1]) * 0.50f +
                 makevec3f(rfmat.row[2]) * 0.85f;
        break;
      }

      // Periscope view
      case CameraMode.periscope: {
        quatf temp2;
        temp2.fromZAngle(camera_user_angle);

        quatf target = tempo * temp2 * rf.getOrientation();

        if (target.dot(camori) < 0.0f) target = target * -1.0f;

        PULLTOWARD(camori, target, delta * 25.0f);

        camori.normalize();

        cammat = camori.getMatrix();
        cammat = cammat.transpose();
        const rfmat = rf.getInverseOrientationMatrix();
        campos = rf.getPosition() +
                 makevec3f(rfmat.row[1]) * 1.7f +
                 makevec3f(rfmat.row[2]) * 5.0f;
        break;
      }
    }

    forw = makevec3f(cammat.row[0]);
    camera_angle = atan2(forw.y, forw.x);

    vec2f diff = makevec2f(game.checkpt[vehic.nextcp].pt) - makevec2f(vehic.body_.getPosition());
    nextcpangle = -atan2(diff.y, diff.x) - forwangle + PI * 0.5f;

    if (cfg.getEnableSound()) {
      SDL_Haptic* haptic = null;

      if (getNumJoysticks() > 0)
        haptic = getJoyHaptic(0);

      audinst_engine.setGain(cfg.getVolumeEngine());
      audinst_engine.setPitch(vehic.getEngineRPM() / 9000.0f);

      float windlevel = fabs(vehic.forwardspeed) * 0.6f;

      audinst_wind.setGain(windlevel * 0.03f * cfg.getVolumeSfx());
      audinst_wind.setPitch(windlevel * 0.02f + 0.9f);

      float skidlevel = vehic.getSkidLevel();

      audinst_gravel.setGain(skidlevel * 0.1f * cfg.getVolumeSfx());
      audinst_gravel.setPitch(1.0f);

      if (haptic !is null && skidlevel > 500.0f)
        SDL_HapticRumblePlay(haptic, skidlevel * 0.0001f, MAX(1000u, cast(uint)(skidlevel * 0.05f)));

      if (vehic.getFlagGearChange()) {
        switch (vehic.iengine.getShiftDirection()) {
          case 1: { // Shift up
            audinst ~= new PAudioInstance(aud_shiftup);
            audinst[$ - 1].setPitch(0.7f + randm11() * 0.02f);
            audinst[$ - 1].setGain(1.0f * cfg.getVolumeSfx());
            audinst[$ - 1].play();
            break;
          }
          case -1: { // Shift down
            audinst ~= new PAudioInstance(aud_shiftdown);
            audinst[$ - 1].setPitch(0.8f + randm11() * 0.12f);
            audinst[$ - 1].setGain(1.0f * cfg.getVolumeSfx());
            audinst[$ - 1].play();
            break;
          }
          default:
            break;
        }
      }

      if (crashnoise_timeout <= 0.0f) {
        float crashlevel = vehic.getCrashNoiseLevel();
        if (crashlevel > 0.0f) {
          audinst ~= new PAudioInstance(aud_crash1);
          audinst[$ - 1].setPitch(1.0f + randm11() * 0.02f);
          audinst[$ - 1].setGain(cast(float) log(1.0 + crashlevel) * cfg.getVolumeSfx());
          audinst[$ - 1].play();

          if (haptic !is null)
            SDL_HapticRumblePlay(haptic, crashlevel * 0.2f, MAX(1000u, cast(uint)(crashlevel * 20.0f)));
        }
        crashnoise_timeout = rand01() * 0.1f + 0.01f;
      } else {
        crashnoise_timeout -= delta;
      }

      for (size_t i = 0; i < audinst.length; i++) {
        if (!audinst[i].isPlaying()) {
          audinst[i].release();
          audinst = audinst[0 .. i] ~ audinst[i + 1 .. $];
          i--;
          continue;
        }
      }
    }

    if (psys_dirt !is null)
      tickDirtParticles(psys_dirt, delta);

    enum RAIN_START_LIFE = 0.6f;
    enum RAIN_POS_RANDOM = 15.0f;
    enum RAIN_VEL_RANDOM = 2.0f;

    vec3f camvelL = (campos - campos_prev) * (1.0f / delta);

    {
      const def_drop_vect = vec3f(2.5f, 0.0f, 17.0f);

      // randomised number of drops calculation
      float numdrops = game.weather.precip.rain * delta;
      int inumdrops = cast(int) numdrops;
      if (rand01() < numdrops - inumdrops) inumdrops++;
      foreach (i; 0 .. inumdrops) {
        RainDrop d;
        d.drop_pt = vec3f(campos.x, campos.y, 0);
        d.drop_pt += camvelL * RAIN_START_LIFE;
        d.drop_pt += vec3f.rand() * RAIN_POS_RANDOM;
        d.drop_pt.z = game.terrain.getHeight(d.drop_pt.x, d.drop_pt.y);

        if (game.water.enabled && d.drop_pt.z < game.water.height)
          d.drop_pt.z = game.water.height;

        d.drop_vect = def_drop_vect + vec3f.rand() * RAIN_VEL_RANDOM;
        d.life = RAIN_START_LIFE;
        rain ~= d;
      }

      // update life and delete dead raindrops
      size_t j = 0;
      foreach (i; 0 .. rain.length) {
        if (rain[i].life <= 0.0f) continue;
        rain[j] = rain[i];
        rain[j].prevlife = rain[j].life;
        rain[j].life -= delta;
        if (rain[j].life < 0.0f)
          rain[j].life = 0.0f; // will be deleted next time round
        j++;
      }
      rain.length = j;
    }

    enum SNOWFALL_START_LIFE = 6.5f;
    enum SNOWFALL_POS_RANDOM = 110.0f;
    enum SNOWFALL_VEL_RANDOM = 0.8f;

    // snowfall logic; this is rain logic CPM'd (Copied, Pasted and Modified) -- A.B.
    {
      const def_drop_vect = vec3f(1.3f, 0.0f, 6.0f);

      float numflakes = game.weather.precip.snowfall * delta;
      int inumflakes = cast(int) numflakes;
      if (rand01() < numflakes - inumflakes) inumflakes++;
      foreach (i; 0 .. inumflakes) {
        SnowFlake s;
        s.drop_pt = vec3f(campos.x, campos.y, 0);
        s.drop_pt += camvelL * SNOWFALL_START_LIFE / 2;
        s.drop_pt += vec3f.rand() * SNOWFALL_POS_RANDOM;
        s.drop_pt.z = game.terrain.getHeight(s.drop_pt.x, s.drop_pt.y);

        if (game.water.enabled && s.drop_pt.z < game.water.height)
          s.drop_pt.z = game.water.height;

        s.drop_vect = def_drop_vect + vec3f.rand() * SNOWFALL_VEL_RANDOM;
        s.life = SNOWFALL_START_LIFE * rand01();
        snowfall ~= s;
      }

      size_t j = 0;
      foreach (i; 0 .. snowfall.length) {
        if (snowfall[i].life <= 0.0f) continue;
        snowfall[j] = snowfall[i];
        snowfall[j].prevlife = snowfall[j].life;
        snowfall[j].life -= delta;
        if (snowfall[j].life < 0.0f)
          snowfall[j].life = 0.0f; // will be deleted next time round
        j++;
      }
      snowfall.length = j;
    }

    // update stuff for SSRender
    cam_pos = campos;
    cam_orimat = cammat;
    cam_linvel = camvelL;

    tickCalculateFps(delta);
  }

  override void keyEvent(in SDL_KeyboardEvent ke)
  {
    alias UC = PConfig.UserControl;

    bool keyIs(int action)
    {
      return cfg.getCtrl().map[action].type == UC.TypeKey &&
             cfg.getCtrl().map[action].key.sym == ke.keysym.sym;
    }

    if (ke.type == SDL_KEYDOWN) {

      if (ke.keysym.sym == SDLK_F12) {
        saveScreenshot();
        return;
      }

      switch (appstate) {
        case AS_LOAD_1:
        case AS_LOAD_2:
          // no hitting escape allowed... end screen not loaded!
          return;
        case AS_LOAD_3:
          levelScreenAction(AA_INIT, 0);
          return;
        case AS_LEVEL_SCREEN:
          handleLevelScreenKey(ke);
          return;
        case AS_CHOOSE_VEHICLE:

          if (keyIs(PConfig.ActionLeft)) {
            if (--choose_type < 0)
              choose_type = cast(int) game.vehiclechoices.length - 1;
            return;
          }
          if (keyIs(PConfig.ActionRight) || keyIs(PConfig.ActionNext)) {
            if (++choose_type >= cast(int) game.vehiclechoices.length)
              choose_type = 0;
            return;
          }

          switch (ke.keysym.sym) {
            case SDLK_RETURN:
            case SDLK_KP_ENTER: {
              if (!game.vehiclechoices[choose_type].getLocked()) {
                initAudio();
                game.chooseVehicle(game.vehiclechoices[choose_type]);
                if (cfg.getEnableGhost())
                  ghost.recordStart(race_data.mapname, game.vehiclechoices[choose_type].getName());

                if (lss.state == AM_TOP_LVL_PREP) {
                  const float bct = best_times.getBestClassTime(race_data.mapname, game.vehicle[0].type.proper_class);

                  if (bct >= 0.0f)
                    game.targettime = bct;
                }

                appstate = AS_IN_GAME;
                return;
              }
              break;
            }
            case SDLK_ESCAPE:
              endGame(Gamefinish.not_finished);
              return;
            default:
              break;
          }
          break;
        case AS_IN_GAME:

          if (keyIs(PConfig.ActionRecover)) {
            game.vehicle[0].doReset();
            return;
          }
          if (keyIs(PConfig.ActionRecoverAtCheckpoint)) {
            game.resetAtCheckpoint(game.vehicle[0]);
            return;
          }
          if (keyIs(PConfig.ActionCamMode)) {
            cameraview = cast(CameraMode)((cast(int) cameraview + 1) % cast(int) CameraMode.count);
            camera_user_angle = 0.0f;
            return;
          }
          if (keyIs(PConfig.ActionShowMap)) {
            showmap = !showmap;
            return;
          }
          if (keyIs(PConfig.ActionPauseRace)) {
            toggleSounds(pauserace);
            pauserace = !pauserace;
            return;
          }
          if (keyIs(PConfig.ActionShowUi)) {
            showui = !showui;
            return;
          }

          if (keyIs(PConfig.ActionShowCheckpoint)) {
            showcheckpoint = !showcheckpoint;
            return;
          }

          switch (ke.keysym.sym) {
            case SDLK_ESCAPE:
              endGame(game.getFinishState());
              pauserace = false;
              return;
            default:
              break;
          }
          break;
        case AS_END_SCREEN:
          requestExit();
          return;
        default:
          break;
      }

      switch (ke.keysym.sym) {
        case SDLK_ESCAPE:
          quitGame();
          return;
        default:
          break;
      }
    }
  }

  override void mouseMoveEvent(int dx, int dy)
  {
    if (appstate == AS_IN_GAME) {
      PVehicle vehic = game.vehicle[0];
      vehic.ctrl.turn.z += dx * 0.01f;
    }
  }

  override void joyButtonEvent(int which, int button, bool down)
  {
    alias UC = PConfig.UserControl;

    bool btnIs(int action)
    {
      return cfg.getCtrl().map[action].type == UC.TypeJoyButton &&
             cfg.getCtrl().map[action].joybutton.button == button;
    }

    if (which == 0 && down) {

      switch (appstate) {
        case AS_CHOOSE_VEHICLE:

          if (btnIs(PConfig.ActionLeft)) {
            if (--choose_type < 0)
              choose_type = cast(int) game.vehiclechoices.length - 1;
            return;
          }
          if (btnIs(PConfig.ActionRight) || btnIs(PConfig.ActionNext)) {
            if (++choose_type >= cast(int) game.vehiclechoices.length)
              choose_type = 0;
            return;
          }

          break;

        case AS_IN_GAME:

          if (btnIs(PConfig.ActionRecover)) {
            game.vehicle[0].doReset();
            return;
          }
          if (btnIs(PConfig.ActionRecoverAtCheckpoint)) {
            game.resetAtCheckpoint(game.vehicle[0]);
            return;
          }
          if (btnIs(PConfig.ActionCamMode)) {
            cameraview = cast(CameraMode)((cast(int) cameraview + 1) % cast(int) CameraMode.count);
            camera_user_angle = 0.0f;
            return;
          }
          if (btnIs(PConfig.ActionShowMap)) {
            showmap = !showmap;
            return;
          }
          if (btnIs(PConfig.ActionPauseRace)) {
            toggleSounds(pauserace);
            pauserace = !pauserace;
            return;
          }
          if (btnIs(PConfig.ActionShowUi)) {
            showui = !showui;
            return;
          }
          break;

        default:
          break;
      }
    }
  }

  override bool joyAxisEvent(int which, int axis, float value, bool down)
  {
    alias UC = PConfig.UserControl;

    if (which == 0) {

      switch (appstate) {
        case AS_CHOOSE_VEHICLE: {
          auto left = &cfg.getCtrl().map[PConfig.ActionLeft];
          auto right = &cfg.getCtrl().map[PConfig.ActionRight];

          if (left.type == UC.TypeJoyAxis && left.joyaxis.axis == axis && left.joyaxis.sign * value > 0.5) {
            if (!down)
              if (--choose_type < 0)
                choose_type = cast(int) game.vehiclechoices.length - 1;
            return true;
          } else if (right.type == UC.TypeJoyAxis && right.joyaxis.axis == axis && right.joyaxis.sign * value > 0.5) {
            if (!down)
              if (++choose_type >= cast(int) game.vehiclechoices.length)
                choose_type = 0;
            return true;
          } else if ((left.type == UC.TypeJoyAxis && left.joyaxis.axis == axis && left.joyaxis.sign * value <= 0.5) ||
                     (right.type == UC.TypeJoyAxis && right.joyaxis.axis == axis && right.joyaxis.sign * value <= 0.5)) {
            return false;
          }

          break;
        }
        default:
          break;
      }
    }
    return down;
  }

  override float getCtrlActionBackValue()
  {
    return cfg.getCtrl().map[PConfig.ActionBack].value;
  }

  override int getVehicleCurrentGear()
  {
    return game.vehicle[0].getCurrentGear();
  }

  override float getAnisotropy()
  {
    return cfg.getAnisotropy();
  }

  PTexture[string] getCodriverSigns() { return tex_codriversigns; }
  PAudioSample[string] getCodriverWords() { return aud_codriverwords; }

  // ---------------------------------------------------------------------------
  // Menu logic (menu.cpp)
  // ---------------------------------------------------------------------------

  void levelScreenAction(int action, int index)
  {
    appstate = AS_LEVEL_SCREEN;

    switch (action) {
      case AA_INIT:
        lss.state = AM_TOP;
        break;
      case AA_RESUME:
        // lss.state should be AM_TOP_EVT_PREP, continuing event
        break;
      case AA_RELOAD_ALL:
        reloadAll();
        cfg.storeConfig();
        lss.state = AM_TOP;
        break;
      case AA_GO_TOP:
        lss.state = AM_TOP;
        break;
      case AA_GO_EVT:
        if (lss.state == AM_TOP_EVT_PREP &&
            lss.currentlevel > 0 &&
            lss.currentlevel < cast(int) events[lss.currentevent].levels.length) {
          lss.state = AM_TOP_EVT_ABANDON;
        } else {
          lss.currentevent = index;
          lss.state = AM_TOP_EVT;
        }
        break;
      case AA_PICK_EVT:
        lss.currentevent = index;
        lss.currentlevel = 0;
        lss.livesleft = 3;
        lss.leveltimes = null;
        lss.totaltime = 0.0f;
        lss.state = AM_TOP_EVT_PREP;
        break;
      case AA_RESUME_EVT:
        lss.state = AM_TOP_EVT_PREP;
        break;
      case AA_RESTART_EVT:
        lss.currentlevel = 0;
        lss.livesleft = 3;
        lss.leveltimes = null;
        lss.totaltime = 0.0f;
        lss.state = AM_TOP_EVT_PREP;
        break;
      case AA_GO_PRAC:
        lss.currentevent = index;
        lss.state = AM_TOP_PRAC;
        break;
      case AA_PICK_PRAC:
        lss.currentevent = index;
        lss.state = AM_TOP_PRAC_SEL;
        break;
      case AA_PICK_PRAC_LVL:
        lss.currentlevel = index;
        lss.state = AM_TOP_PRAC_SEL_PREP;
        break;
      case AA_GO_LVL:
        lss.currentlevel = index;
        lss.state = AM_TOP_LVL;
        break;
      case AA_PICK_LVL:
        lss.currentlevel = index;
        lss.state = AM_TOP_LVL_PREP;
        break;
      case AA_GO_QUIT:
        lss.state = AM_TOP_QUIT;
        break;
      case AA_QUIT_CONFIRM:
        quitGame();
        break;

      case AA_START_EVT:
      case AA_START_PRAC:
        startGame(events[lss.currentevent].levels[lss.currentlevel].filename);
        return;
      case AA_START_LVL:
        startGame(levels[lss.currentlevel].filename);
        return;

      case AA_SHOWTIMES_LVL:
        lss.currentplayer = index;
        break;

      case AA_SHOWTIMES_PRAC:
        lss.currentplayer = index;
        break;

      case AA_BSHOWTIMES_LVL:
        lss.currentplayer = index;
        lss.state = AM_TOP_LVL_BTIMES;
        current_times = best_times.getCurrentTimes(levels[lss.currentlevel].filename,
                                                   HISCORE1_SORT.BY_TOTALTIME_ASC).dup;
        break;

      case AA_BSHOWTIMES_PRAC:
        lss.currentplayer = index;
        lss.state = AM_TOP_PRAC_BTIMES;
        current_times = best_times.getCurrentTimes(events[lss.currentevent].levels[lss.currentlevel].filename,
                                                   HISCORE1_SORT.BY_TOTALTIME_ASC).dup;
        break;

      case AA_SORT_BY_PLAYERNAME:
        lss.currentplayer = 0;
        hs_sort_method = hs_sort_method == HISCORE1_SORT.BY_PLAYERNAME_ASC ?
                         HISCORE1_SORT.BY_PLAYERNAME_DESC : HISCORE1_SORT.BY_PLAYERNAME_ASC;
        break;

      case AA_SORT_BY_CARNAME:
        lss.currentplayer = 0;
        hs_sort_method = hs_sort_method == HISCORE1_SORT.BY_CARNAME_ASC ?
                         HISCORE1_SORT.BY_CARNAME_DESC : HISCORE1_SORT.BY_CARNAME_ASC;
        break;

      case AA_SORT_BY_CARCLASS:
        lss.currentplayer = 0;
        hs_sort_method = hs_sort_method == HISCORE1_SORT.BY_CARCLASS_ASC ?
                         HISCORE1_SORT.BY_CARCLASS_DESC : HISCORE1_SORT.BY_CARCLASS_ASC;
        break;

      case AA_SORT_BY_TOTALTIME:
        lss.currentplayer = 0;
        hs_sort_method = hs_sort_method == HISCORE1_SORT.BY_TOTALTIME_ASC ?
                         HISCORE1_SORT.BY_TOTALTIME_DESC : HISCORE1_SORT.BY_TOTALTIME_ASC;
        break;

      case AA_GO_OPT:
        lss.state = AM_TOP_OPT;
        break;

      case AA_PICK_OPT:
        option.select(index);
        break;

      case AA_GO_CTRL:
        lss.state = AM_TOP_CTRL;
        break;

      case AA_PICK_CTRL:
        control.select(index);
        break;

      default:
        PUtil.outLog("ERROR: invalid action code ", action);
        requestExit();
        return;
    }

    gui.setSSRender(getSSRender());
    gui.setFont(tex_fontSourceCodeShadowed);
    grabMouse(false);
    gui.clear();
    gui.addLabel(10.0f, 570.0f, "Trigger Rally", PTEXT_HZA_LEFT | PTEXT_VTA_CENTER, 30.0f, LabelStyle.Weak);

    switch (lss.state) {
      case AM_TOP:
        gui.makeClickable(
          gui.addLabel(400.0f, 400.0f, "events", PTEXT_HZA_CENTER | PTEXT_VTA_CENTER, 40.0f), AA_GO_EVT, 0);
        gui.makeClickable(
          gui.addLabel(400.0f, 350.0f, "practice", PTEXT_HZA_CENTER | PTEXT_VTA_CENTER, 40.0f), AA_GO_PRAC, 0);
        gui.makeClickable(
          gui.addLabel(400.0f, 300.0f, "single race", PTEXT_HZA_CENTER | PTEXT_VTA_CENTER, 40.0f), AA_GO_LVL, 0);
        gui.makeClickable(
          gui.addLabel(400.0f, 250.0f, "options", PTEXT_HZA_CENTER | PTEXT_VTA_CENTER, 40.0f), AA_GO_OPT, 0);
        gui.makeClickable(
          gui.addLabel(400.0f, 200.0f, "controls", PTEXT_HZA_CENTER | PTEXT_VTA_CENTER, 40.0f), AA_GO_CTRL, 0);
        gui.makeClickable(
          gui.addLabel(10.0f, 30.0f, "quit", PTEXT_HZA_LEFT | PTEXT_VTA_CENTER, 40.0f), AA_GO_QUIT, 0);

        gui.addLabel(790.0f, 570.0f, "version " ~ PACKAGE_VERSION, PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 30.0f, LabelStyle.Weak);
        gui.addLabel(790.0f, 30.0f, "Build: " ~ __DATE__ ~ " at " ~ __TIME__, PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20.0f,
                     LabelStyle.Weak);
        break;
      case AM_TOP_EVT: {
        gui.makeClickable(
          gui.addLabel(10.0f, 30.0f, "back", PTEXT_HZA_LEFT | PTEXT_VTA_CENTER, 40.0f), AA_GO_TOP, 0);
        gui.addLabel(100.0f, 470.0f, "Choose Event:", PTEXT_HZA_LEFT | PTEXT_VTA_CENTER, 30.0f, LabelStyle.Header);

        int firstraceindex = index;
        const prevbutton = gui.addGraphic(20.0f, 275.0f, 50.0f, 50.0f, tex_button_prev, GraphicStyle.Button);
        const nextbutton = gui.addGraphic(730.0f, 275.0f, 50.0f, 50.0f, tex_button_next, GraphicStyle.Button);

        if (firstraceindex > 0) {
          gui.makeClickable(prevbutton, AA_GO_EVT, firstraceindex - MAX_RACES_ON_SCREEN);
        }

        int racesonscreencount = cast(int) events.length - firstraceindex;

        if (racesonscreencount > MAX_RACES_ON_SCREEN) {
          racesonscreencount = MAX_RACES_ON_SCREEN;
          gui.makeClickable(nextbutton, AA_GO_EVT, firstraceindex + MAX_RACES_ON_SCREEN);
        }

        gui.addLabel(790.0f, 570.0f,
                     "events " ~ to!string(firstraceindex + 1) ~ '-' ~ to!string(firstraceindex + racesonscreencount) ~
                     '/' ~ to!string(events.length),
                     PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20.0f, LabelStyle.Weak);
        gui.addLabel(700, 470, "races (timelimit)", PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20);

        for (int i = firstraceindex; i < firstraceindex + racesonscreencount; i++) {

          const eventlabel = gui.addLabel(100.0f, 440.0f - cast(float)(i - firstraceindex) * 30.0f,
                                          events[i].name, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 25.0f, LabelStyle.List);

          if (!events[i].locked || (events[i].filename in player_unlocks) !is null)
            gui.makeClickable(eventlabel, AA_PICK_EVT, i);

          gui.addLabel(700.0f, 440.0f - cast(float)(i - firstraceindex) * 30.0f,
                       PUtil.formatInt(cast(int) events[i].levels.length) ~ " (" ~ events[i].totaltime ~ ')',
                       PTEXT_HZA_RIGHT | PTEXT_VTA_TOP, 25.0f, LabelStyle.List);
        }
        break;
      }
      case AM_TOP_EVT_PREP:
        gui.makeClickable(
          gui.addLabel(10.0f, 10.0f, "back", PTEXT_HZA_LEFT | PTEXT_VTA_BOTTOM, 40.0f),
          AA_GO_EVT, 0);
        gui.addLabel(790.0f, 570.0f, events[lss.currentevent].name, PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20.0f,
                     LabelStyle.Weak);
        gui.addLabel(100.0f, 470.0f, "Races:", PTEXT_HZA_LEFT | PTEXT_VTA_CENTER, 30.0f, LabelStyle.Header);
        gui.addLabel(700, 470, "status/time", PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20);

        foreach (i; 0 .. events[lss.currentevent].levels.length) {

          LabelStyle namestyle = LabelStyle.List;

          if (lss.currentlevel > cast(int) i)
            namestyle = LabelStyle.Strong;
          else if (lss.currentlevel == cast(int) i)
            namestyle = LabelStyle.Marked;

          gui.addLabel(100.0f, 440.0f - cast(float) i * 30.0f,
                       events[lss.currentevent].levels[i].name, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 25.0f, namestyle);

          string infotext = "not yet raced";
          LabelStyle infostyle = LabelStyle.List;

          if (lss.currentlevel > cast(int) i) {
            infotext = PUtil.formatTime(lss.leveltimes[i]);
            infostyle = LabelStyle.Strong;
          } else if (lss.currentlevel == cast(int) i) {
            infotext = "next";
            infostyle = LabelStyle.Marked;
          }
          gui.addLabel(700.0f, 440.0f - cast(float) i * 30.0f,
                       infotext, PTEXT_HZA_RIGHT | PTEXT_VTA_TOP, 25.0f, infostyle);
        }
        gui.addLabel(700.0f, 430.0f - cast(float) events[lss.currentevent].levels.length * 30.0f,
                     "Total: " ~ PUtil.formatTime(lss.totaltime), PTEXT_HZA_RIGHT | PTEXT_VTA_TOP, 25.0f, LabelStyle.Strong);
        if (lss.livesleft <= 0) {
          gui.addLabel(400.0f, 10.0f, "no tries remaining", PTEXT_HZA_CENTER | PTEXT_VTA_BOTTOM, 20.0f, LabelStyle.Strong);
          gui.makeClickable(
            gui.addLabel(790.0f, 10.0f, "restart", PTEXT_HZA_RIGHT | PTEXT_VTA_BOTTOM, 40.0f),
            AA_RESTART_EVT, 0);
        } else if (lss.currentlevel >= cast(int) events[lss.currentevent].levels.length) {
          gui.addLabel(400.0f, 10.0f, "EVENT COMPLETED!", PTEXT_HZA_CENTER | PTEXT_VTA_BOTTOM, 30.0f, LabelStyle.Marked);
        } else {
          gui.addLabel(400.0f, 10.0f, PUtil.formatInt(lss.livesleft) ~ " tries remaining",
                       PTEXT_HZA_CENTER | PTEXT_VTA_BOTTOM, 20.0f, LabelStyle.Strong);

          foreach (i; 0 .. lss.livesleft) {
            gui.addGraphic(325.0f + i * 50.0f, 30.0f, 50.0f, 50.0f, tex_hud_life);
          }
          gui.makeDefault(
            gui.makeClickable(
              gui.addLabel(790.0f, 10.0f, "race", PTEXT_HZA_RIGHT | PTEXT_VTA_BOTTOM, 40.0f),
              AA_START_EVT, 0));
        }
        break;
      case AM_TOP_EVT_ABANDON:
        gui.addLabel(400.0f, 350.0f, "Really leave Event?", PTEXT_HZA_CENTER | PTEXT_VTA_TOP, 40.0f, LabelStyle.Marked);
        gui.makeClickable(
          gui.addLabel(300.0f, 250.0f, "Yes", PTEXT_HZA_CENTER | PTEXT_VTA_TOP, 40.0f),
          AA_GO_EVT, 0);
        gui.makeClickable(
          gui.addLabel(500.0f, 250.0f, "No", PTEXT_HZA_CENTER | PTEXT_VTA_TOP, 40.0f),
          AA_RESUME_EVT, 0);
        break;
      case AM_TOP_PRAC: {
        gui.makeClickable(
          gui.addLabel(10.0f, 10.0f, "back", PTEXT_HZA_LEFT | PTEXT_VTA_BOTTOM, 40.0f), AA_GO_TOP, 0);
        gui.addLabel(100.0f, 470.0f, "Practice Event:", PTEXT_HZA_LEFT | PTEXT_VTA_CENTER, 30.0f, LabelStyle.Header);

        int firstraceindex = index;
        const prevbutton = gui.addGraphic(20.0f, 275.0f, 50.0f, 50.0f, tex_button_prev, GraphicStyle.Button);
        const nextbutton = gui.addGraphic(730.0f, 275.0f, 50.0f, 50.0f, tex_button_next, GraphicStyle.Button);

        if (firstraceindex > 0) {
          gui.makeClickable(prevbutton, AA_GO_PRAC, firstraceindex - MAX_RACES_ON_SCREEN);
        }

        int racesonscreencount = cast(int) events.length - firstraceindex;

        if (racesonscreencount > MAX_RACES_ON_SCREEN) {
          racesonscreencount = MAX_RACES_ON_SCREEN;
          gui.makeClickable(nextbutton, AA_GO_PRAC, firstraceindex + MAX_RACES_ON_SCREEN);
        }

        gui.addLabel(790.0f, 570.0f,
                     "events " ~ to!string(firstraceindex + 1) ~ '-' ~ to!string(firstraceindex + racesonscreencount) ~
                     '/' ~ to!string(events.length),
                     PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20.0f, LabelStyle.Weak);
        gui.addLabel(700, 470, "races (timelimit)", PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20);

        for (int i = firstraceindex; i < firstraceindex + racesonscreencount; i++) {

          const eventlabel = gui.addLabel(100.0f, 440.0f - cast(float)(i - firstraceindex) * 30.0f,
                                          events[i].name, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 25.0f, LabelStyle.List);

          if (!events[i].locked || (events[i].filename in player_unlocks) !is null)
            gui.makeClickable(eventlabel, AA_PICK_PRAC, i);

          gui.addLabel(700.0f, 440.0f - cast(float)(i - firstraceindex) * 30.0f,
                       PUtil.formatInt(cast(int) events[i].levels.length) ~ " (" ~ events[i].totaltime ~ ')',
                       PTEXT_HZA_RIGHT | PTEXT_VTA_TOP, 25.0f, LabelStyle.List);
        }
        break;
      }
      case AM_TOP_PRAC_SEL: {
        gui.makeClickable(
          gui.addLabel(10.0f, 10.0f, "back", PTEXT_HZA_LEFT | PTEXT_VTA_BOTTOM, 40.0f),
          AA_GO_PRAC, 0);
        gui.addLabel(790.0f, 570.0f, events[lss.currentevent].name, PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20.0f,
                     LabelStyle.Weak);
        gui.addLabel(100.0f, 470.0f, "Choose Race:", PTEXT_HZA_LEFT | PTEXT_VTA_CENTER, 30.0f, LabelStyle.Header);
        gui.addLabel(700, 470, "timelimit", PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20);

        foreach (i; 0 .. events[lss.currentevent].levels.length) {
          gui.makeClickable(
            gui.addLabel(100.0f, 440.0f - cast(float) i * 30.0f,
                         events[lss.currentevent].levels[i].name, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 25.0f, LabelStyle.List),
            AA_PICK_PRAC_LVL, cast(int) i);

          gui.addLabel(700.0f, 440.0f - cast(float) i * 30.0f,
                       events[lss.currentevent].levels[i].targettimeshort, PTEXT_HZA_RIGHT | PTEXT_VTA_TOP, 25.0f, LabelStyle.List);
        }
        break;
      }
      case AM_TOP_PRAC_SEL_PREP: {
        auto tl = &events[lss.currentevent].levels[lss.currentlevel];
        const prevbutton = gui.addGraphic(20.0f, 275.0f, 50.0f, 50.0f, tex_button_prev, GraphicStyle.Button);
        const nextbutton = gui.addGraphic(730.0f, 275.0f, 50.0f, 50.0f, tex_button_next, GraphicStyle.Button);

        int idxnext = lss.currentlevel + 1;
        int idxprev = lss.currentlevel - 1;

        const lastidx = cast(int) events[lss.currentevent].levels.length - 1;
        CLAMP(idxnext, 0, lastidx);
        CLAMP(idxprev, 0, lastidx);

        if (lss.currentlevel < lastidx)
          gui.makeClickable(nextbutton, AA_PICK_PRAC_LVL, idxnext);

        if (lss.currentlevel > 0)
          gui.makeClickable(prevbutton, AA_PICK_PRAC_LVL, idxprev);

        gui.makeClickable(
          gui.addLabel(10.0f, 10.0f, "back", PTEXT_HZA_LEFT | PTEXT_VTA_BOTTOM, 40.0f),
          AA_PICK_PRAC, lss.currentevent);

        gui.makeClickable(
          gui.addLabel(400.0f, 10.0f, "best times", PTEXT_HZA_CENTER | PTEXT_VTA_BOTTOM, 40.0f),
          AA_BSHOWTIMES_PRAC, 0);

        gui.addLabel(790.0f, 570.0f, events[lss.currentevent].name ~ " (" ~
                     PUtil.formatInt(lss.currentlevel + 1) ~ '/' ~ PUtil.formatInt(cast(int) events[lss.currentevent].levels.length) ~ ')',
                     PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20.0f, LabelStyle.Weak);
        gui.addLabel(100.0f, 500.0f, tl.name, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 35.0f, LabelStyle.Header);
        gui.addLabel(100.0f, 462.5f, "by " ~ tl.author, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 20.0f, LabelStyle.Weak);
        gui.addLabel(700.0f, 462.5f, tl.targettimeshort, PTEXT_HZA_RIGHT | PTEXT_VTA_TOP, 20.0f);

        if (tl.tex_screenshot !is null)
          gui.addGraphic(100, 175, 250.0f * 4 / 3, 250, tl.tex_screenshot);
        else
          gui.addGraphic(100, 175, 250.0f * 4 / 3, 250, tex_race_no_screenshot);

        if (tl.tex_minimap !is null)
          gui.addGraphic(450, 175, 250, 250, tl.tex_minimap);
        else
          gui.addGraphic(450, 175, 250, 250, tex_race_no_minimap);

        gui.addLabel(100.0f, 150.0f, tl.description, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 20.0f);
        gui.makeDefault(
          gui.makeClickable(
            gui.addLabel(790.0f, 10.0f, "race", PTEXT_HZA_RIGHT | PTEXT_VTA_BOTTOM, 40.0f),
            AA_START_PRAC, 0));
        break;
      }
      case AM_TOP_LVL: {
        gui.makeClickable(
          gui.addLabel(10.0f, 10.0f, "back", PTEXT_HZA_LEFT | PTEXT_VTA_BOTTOM, 40.0f),
          AA_GO_TOP, 0);
        gui.addLabel(100.0f, 470.0f, "Choose Race:", PTEXT_HZA_LEFT | PTEXT_VTA_CENTER, 30.0f, LabelStyle.Header);

        int firstraceindex = index;
        const prevbutton = gui.addGraphic(20.0f, 275.0f, 50.0f, 50.0f, tex_button_prev, GraphicStyle.Button);
        const nextbutton = gui.addGraphic(730.0f, 275.0f, 50.0f, 50.0f, tex_button_next, GraphicStyle.Button);

        if (firstraceindex > 0) {
          gui.makeClickable(prevbutton, AA_GO_LVL, firstraceindex - MAX_RACES_ON_SCREEN);
        }

        int racesonscreencount = cast(int) levels.length - firstraceindex;

        if (racesonscreencount > MAX_RACES_ON_SCREEN) {
          racesonscreencount = MAX_RACES_ON_SCREEN;
          gui.makeClickable(nextbutton, AA_GO_LVL, firstraceindex + MAX_RACES_ON_SCREEN);
        }
        gui.addLabel(790.0f, 570.0f,
                     "single races " ~ to!string(firstraceindex + 1) ~ '-' ~ to!string(firstraceindex + racesonscreencount) ~
                     '/' ~ to!string(levels.length),
                     PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20.0f, LabelStyle.Weak);

        gui.addLabel(700, 470, "timelimit", PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20);

        for (int i = firstraceindex; i < firstraceindex + racesonscreencount; i++) {
          gui.makeClickable(
            gui.addLabel(100.0f, 440.0f - cast(float)(i - firstraceindex) * 30.0f,
                         levels[i].name, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 25.0f, LabelStyle.List),
            AA_PICK_LVL, i);

          gui.addLabel(700.0f, 440.0f - cast(float)(i - firstraceindex) * 30.0f,
                       levels[i].targettimeshort, PTEXT_HZA_RIGHT | PTEXT_VTA_TOP, 25.0f, LabelStyle.List);
        }
        break;
      }
      case AM_TOP_LVL_PREP: {
        auto tl = &levels[lss.currentlevel];
        const prevbutton = gui.addGraphic(20.0f, 275.0f, 50.0f, 50.0f, tex_button_prev, GraphicStyle.Button);
        const nextbutton = gui.addGraphic(730.0f, 275.0f, 50.0f, 50.0f, tex_button_next, GraphicStyle.Button);

        int idxnext = lss.currentlevel + 1;
        int idxprev = lss.currentlevel - 1;

        const lastidx = cast(int) levels.length - 1;
        CLAMP(idxnext, 0, lastidx);
        CLAMP(idxprev, 0, lastidx);

        if (lss.currentlevel < lastidx)
          gui.makeClickable(nextbutton, AA_PICK_LVL, idxnext);

        if (lss.currentlevel > 0)
          gui.makeClickable(prevbutton, AA_PICK_LVL, idxprev);

        gui.makeClickable(
          gui.addLabel(10.0f, 10.0f, "back", PTEXT_HZA_LEFT | PTEXT_VTA_BOTTOM, 40.0f),
          AA_GO_LVL, (lss.currentlevel / MAX_RACES_ON_SCREEN) * MAX_RACES_ON_SCREEN);

        gui.makeClickable(
          gui.addLabel(400.0f, 10.0f, "best times", PTEXT_HZA_CENTER | PTEXT_VTA_BOTTOM, 40.0f),
          AA_BSHOWTIMES_LVL, 0);

        gui.addLabel(790.0f, 570.0f, "single race " ~ to!string(lss.currentlevel + 1) ~ '/' ~ to!string(levels.length),
                     PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20.0f, LabelStyle.Weak);
        gui.addLabel(100.0f, 500.0f, tl.name, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 35.0f, LabelStyle.Header);
        gui.addLabel(100.0f, 462.5f, "by " ~ tl.author, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 20.0f, LabelStyle.Weak);
        gui.addLabel(700.0f, 462.5f, tl.targettimeshort, PTEXT_HZA_RIGHT | PTEXT_VTA_TOP, 20.0f);

        if (tl.tex_screenshot !is null)
          gui.addGraphic(100, 175, 250.0f * 4 / 3, 250, tl.tex_screenshot);
        else
          gui.addGraphic(100, 175, 250.0f * 4 / 3, 250, tex_race_no_screenshot);

        if (tl.tex_minimap !is null)
          gui.addGraphic(450, 175, 250, 250, tl.tex_minimap);
        else
          gui.addGraphic(450, 175, 250, 250, tex_race_no_minimap);

        gui.addLabel(100.0f, 150.0f, tl.description, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 20.0f);
        gui.makeDefault(
          gui.makeClickable(
            gui.addLabel(790.0f, 10.0f, "race", PTEXT_HZA_RIGHT | PTEXT_VTA_BOTTOM, 40.0f),
            AA_START_LVL, 0));
        break;
      }
      case AM_TOP_QUIT:
        gui.addLabel(400.0f, 350.0f, "Really quit?", PTEXT_HZA_CENTER | PTEXT_VTA_TOP, 40.0f, LabelStyle.Marked);
        gui.makeClickable(
          gui.addLabel(300.0f, 250.0f, "Yes", PTEXT_HZA_CENTER | PTEXT_VTA_TOP, 40.0f),
          AA_QUIT_CONFIRM, 0);
        gui.makeClickable(
          gui.addLabel(500.0f, 250.0f, "No", PTEXT_HZA_CENTER | PTEXT_VTA_TOP, 40.0f),
          AA_GO_TOP, 0);
        break;

      case AM_TOP_LVL_TIMES:
        timesScreen(levels[lss.currentlevel], AA_PICK_LVL, true, AA_SHOWTIMES_LVL, index);
        break;

      case AM_TOP_LVL_BTIMES:
        timesScreen(levels[lss.currentlevel], AA_PICK_LVL, false, AA_SHOWTIMES_LVL, index);
        break;

      case AM_TOP_PRAC_TIMES:
        timesScreen(events[lss.currentevent].levels[lss.currentlevel], AA_PICK_PRAC_LVL, true, AA_SHOWTIMES_PRAC, index);
        break;

      case AM_TOP_PRAC_BTIMES:
        timesScreen(events[lss.currentevent].levels[lss.currentlevel], AA_PICK_PRAC_LVL, false, AA_SHOWTIMES_PRAC, index);
        break;

      case AM_TOP_OPT:
        option.render();
        break;

      case AM_TOP_CTRL:
        control.render();
        break;

      default:
        gui.addLabel(400.0f, 300.0f, "Error in menu system, sorry", PTEXT_HZA_CENTER | PTEXT_VTA_TOP, 30.0f,
                     LabelStyle.Marked);
        gui.makeClickable(
          gui.addLabel(400.0f, 150.0f, "Go to top menu", PTEXT_HZA_CENTER | PTEXT_VTA_TOP, 30.0f),
          AA_GO_TOP, 0);
        break;
    }
  }

  /// The four best-times screens share the same layout; they differ in what gets highlighted.
  private void timesScreen(ref TriggerLevel tl, int backAction, bool highlighted, int pageAction, int index)
  {
    gui.addLabel(100.0f, 500.0f, tl.name, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 35.0f, LabelStyle.Header);
    gui.addLabel(100.0f, 462.5f, "by " ~ tl.author, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 20.0f, LabelStyle.Weak);
    gui.addLabel(700.0f, 462.5f, tl.targettime, PTEXT_HZA_RIGHT | PTEXT_VTA_TOP, 20.0f);
    gui.makeClickable(
      gui.addLabel(10.0f, 10.0f, "back", PTEXT_HZA_LEFT | PTEXT_VTA_BOTTOM, 40.0f),
      backAction, lss.currentlevel);

    if (highlighted)
      current_times = best_times.getCurrentTimesHL(hs_sort_method).dup;
    else
      current_times = best_times.getCurrentTimes("", hs_sort_method).dup;

    int first_time_index = index;

    const prevbutton = gui.addGraphic(20.0f, 275.0f, 50.0f, 50.0f, tex_button_prev, GraphicStyle.Button);
    const nextbutton = gui.addGraphic(730.0f, 275.0f, 50.0f, 50.0f, tex_button_next, GraphicStyle.Button);

    if (first_time_index > 0)
      gui.makeClickable(prevbutton, pageAction, first_time_index - MAX_TIMES_ON_SCREEN);

    int times_on_screen_count = cast(int) current_times.length - first_time_index;

    if (times_on_screen_count > MAX_TIMES_ON_SCREEN) {
      times_on_screen_count = MAX_TIMES_ON_SCREEN;
      gui.makeClickable(nextbutton, pageAction, first_time_index + MAX_TIMES_ON_SCREEN);
    }

    string times_count_msg;
    if (highlighted) {
      times_count_msg = "best times " ~ to!string(first_time_index + 1) ~ '-' ~
                        to!string(first_time_index + times_on_screen_count) ~ '/' ~ to!string(current_times.length);
    } else {
      times_count_msg = "best times";
      if (current_times.length)
        times_count_msg ~= ' ' ~ to!string(first_time_index + 1) ~ '-' ~
                           to!string(first_time_index + times_on_screen_count) ~ '/' ~ to!string(current_times.length);
    }
    gui.addLabel(790.0f, 570.0f, times_count_msg, PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER, 20.0f, LabelStyle.Weak);

    // column buttons
    gui.makeClickable(
      gui.addLabel(XTIMES_PLAYERNAME, 420.0f, "player", PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 20.0f),
      AA_SORT_BY_PLAYERNAME, 0);
    gui.makeClickable(
      gui.addLabel(XTIMES_CARNAME, 420.0f, "car", PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 20.0f),
      AA_SORT_BY_CARNAME, 0);
    gui.makeClickable(
      gui.addLabel(XTIMES_CARCLASS, 420.0f, "class", PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 20.0f),
      AA_SORT_BY_CARCLASS, 0);
    gui.makeClickable(
      gui.addLabel(XTIMES_TOTALTIME, 420.0f, "time", PTEXT_HZA_RIGHT | PTEXT_VTA_TOP, 20.0f),
      AA_SORT_BY_TOTALTIME, 0);

    static string cut(string s, size_t n) { return s.length > n ? s[0 .. n] : s; }

    for (int i = first_time_index; i < first_time_index + times_on_screen_count; ++i) {
      LabelStyle ls = (highlighted && current_times[i].highlighted) ? LabelStyle.Marked : LabelStyle.List;
      const y = 395.0f - cast(float)(i - first_time_index) * 25.0f;

      gui.addLabel(XTIMES_PLAYERNAME, y, to!string(current_times[i].place) ~ ". ", PTEXT_HZA_RIGHT | PTEXT_VTA_TOP, 20.0f, ls);
      gui.addLabel(XTIMES_PLAYERNAME, y, cut(current_times[i].rd.playername, 14), PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 20.0f, ls);
      gui.addLabel(XTIMES_CARNAME, y, cut(current_times[i].rd.carname, 9), PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 20.0f, ls);
      gui.addLabel(XTIMES_CARCLASS, y, cut(current_times[i].rd.carclass, 8), PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 20.0f, ls);
      gui.addLabel(XTIMES_TOTALTIME, y, PUtil.formatTime(current_times[i].rd.totaltime), PTEXT_HZA_RIGHT | PTEXT_VTA_TOP, 20.0f, ls);
    }
  }

  void finishRace(Gamefinish state, float coursetime)
  {
    switch (lss.state) {
      case AM_TOP_EVT_PREP:
        switch (state) {
          case Gamefinish.pass:
            lss.leveltimes.length = events[lss.currentevent].levels.length;
            lss.leveltimes[lss.currentlevel] += coursetime;
            lss.totaltime += coursetime;
            lss.currentlevel++;

            // event was completed so save unlock data
            if (lss.currentlevel >= cast(int) events[lss.currentevent].levels.length) {
              foreach (s; events[lss.currentevent].unlocks.byKey)
                best_times.addNewUnlock(s);

              player_unlocks = best_times.getUnlockData();
              best_times.skipSavePlayer();
            }
            break;

          case Gamefinish.fail:
            lss.totaltime += coursetime;
            lss.livesleft--;
            break;

          default:
            break;
        }
        levelScreenAction(AA_RESUME, 0);
        break;

      case AM_TOP_PRAC_SEL_PREP:
        levelScreenAction(AA_PICK_PRAC_LVL, lss.currentlevel);
        break;

      case AM_TOP_LVL_PREP:
        levelScreenAction(AA_PICK_LVL, lss.currentlevel);
        break;

      case AM_TOP_LVL_TIMES:
        levelScreenAction(AA_SHOWTIMES_LVL, 0);
        break;

      case AM_TOP_PRAC_TIMES:
        levelScreenAction(AA_SHOWTIMES_PRAC, 0);
        break;

      default:
        PUtil.outLog("Race finished in invalid state ", lss.state);
        break;
    }
  }

  void tickStateLevel(float delta)
  {
    gui.tick(delta);
  }

  override void cursorMoveEvent(int posx, int posy)
  {
    if (appstate != AS_LEVEL_SCREEN) return;

    const double margin = (800.0 - 600.0 * cx / cy) / 2.0;

    gui.setCursorPos(
      cast(float) posx / cast(float) getWidth() * (600.0 * cx / cy) + margin,
      (1.0f - cast(float) posy / cast(float) getHeight()) * 600.0f);
  }

  override void mouseButtonEvent(in SDL_MouseButtonEvent mbe)
  {
    if (mbe.type != SDL_MOUSEBUTTONDOWN) return;

    switch (appstate) {
      case AS_LEVEL_SCREEN:
        break;
      case AS_LOAD_3:
        levelScreenAction(AA_INIT, 0);
        break;
      default:
        return;
    }

    const double margin = (800.0 - 600.0 * cx / cy) / 2.0;

    int action, index;

    if (!gui.getClickAction(action, index)) return;

    levelScreenAction(action, index);

    gui.setCursorPos(
      cast(float) mbe.x / cast(float) getWidth() * (600.0 * cx / cy) + margin,
      (1.0f - cast(float) mbe.y / cast(float) getHeight()) * 600.0f);
  }

  void handleLevelScreenKey(in SDL_KeyboardEvent ke)
  {
    if (lss.state == AM_TOP_CTRL)
      if (control.handleKey(ke)) {
        levelScreenAction(AA_GO_CTRL, 0);
        return;
      }

    switch (ke.keysym.sym) {
      case SDLK_ESCAPE:
        switch (lss.state) {
          case AM_TOP:
            levelScreenAction(AA_GO_QUIT, 0);
            break;
          case AM_TOP_EVT_PREP:
          case AM_TOP_EVT_ABANDON:
            levelScreenAction(AA_GO_EVT, 0);
            break;
          case AM_TOP_PRAC_SEL:
            levelScreenAction(AA_GO_PRAC, 0);
            break;
          case AM_TOP_PRAC_SEL_PREP:
            levelScreenAction(AA_PICK_PRAC, lss.currentevent);
            break;
          case AM_TOP_LVL_PREP:
            levelScreenAction(AA_GO_LVL, (lss.currentlevel / MAX_RACES_ON_SCREEN) * MAX_RACES_ON_SCREEN);
            break;
          case AM_TOP_QUIT:
            quitGame();
            break;
          case AM_TOP_LVL_TIMES:
          case AM_TOP_LVL_BTIMES:
            levelScreenAction(AA_PICK_LVL, lss.currentlevel);
            break;
          case AM_TOP_PRAC_TIMES:
          case AM_TOP_PRAC_BTIMES:
            levelScreenAction(AA_PICK_PRAC_LVL, lss.currentlevel);
            break;
          case AM_TOP_OPT:
            levelScreenAction(AA_RELOAD_ALL, 0);
            break;
          case AM_TOP_CTRL:
            levelScreenAction(AA_RELOAD_ALL, 0);
            break;
          default:
            levelScreenAction(AA_GO_TOP, 0);
            break;
        }
        break;
      case SDLK_RETURN:
      case SDLK_KP_ENTER: {
        int data1, data2;

        if (gui.getDefaultAction(data1, data2))
          levelScreenAction(data1, data2);
        break;
      }

      case SDLK_LEFT: {
        int pidx; // previous index

        switch (lss.state) {
          case AM_TOP_LVL_PREP:
            pidx = lss.currentlevel - 1;
            CLAMP_LOWER(pidx, 0);
            levelScreenAction(AA_PICK_LVL, pidx);
            break;

          case AM_TOP_LVL:
            pidx = (lss.currentlevel / MAX_RACES_ON_SCREEN - 1) * MAX_RACES_ON_SCREEN;
            CLAMP_LOWER(pidx, 0);
            levelScreenAction(AA_GO_LVL, pidx);
            break;

          case AM_TOP_EVT:
            pidx = (lss.currentevent / MAX_RACES_ON_SCREEN - 1) * MAX_RACES_ON_SCREEN;
            CLAMP_LOWER(pidx, 0);
            levelScreenAction(AA_GO_EVT, pidx);
            break;

          case AM_TOP_PRAC:
            pidx = (lss.currentevent / MAX_RACES_ON_SCREEN - 1) * MAX_RACES_ON_SCREEN;
            CLAMP_LOWER(pidx, 0);
            levelScreenAction(AA_GO_PRAC, pidx);
            break;

          case AM_TOP_PRAC_SEL_PREP:
            pidx = lss.currentlevel - 1;
            CLAMP_LOWER(pidx, 0);
            levelScreenAction(AA_PICK_PRAC_LVL, pidx);
            break;

          case AM_TOP_LVL_TIMES:
          case AM_TOP_LVL_BTIMES:
            // NOTE: not using AA_BSHOWTIMES_LVL intentionally!
            pidx = (lss.currentplayer / MAX_TIMES_ON_SCREEN - 1) * MAX_TIMES_ON_SCREEN;
            CLAMP_LOWER(pidx, 0);
            levelScreenAction(AA_SHOWTIMES_LVL, pidx);
            break;

          case AM_TOP_PRAC_TIMES:
          case AM_TOP_PRAC_BTIMES:
            pidx = (lss.currentplayer / MAX_TIMES_ON_SCREEN - 1) * MAX_TIMES_ON_SCREEN;
            CLAMP_LOWER(pidx, 0);
            levelScreenAction(AA_SHOWTIMES_PRAC, pidx);
            break;

          default:
            break;
        }

        break;
      }

      case SDLK_RIGHT: {
        int nidx; // next index

        switch (lss.state) {
          case AM_TOP_LVL_PREP:
            nidx = lss.currentlevel + 1;
            CLAMP_UPPER(nidx, cast(int) levels.length - 1);
            levelScreenAction(AA_PICK_LVL, nidx);
            break;

          case AM_TOP_LVL:
            if (cast(int) levels.length - lss.currentlevel <= MAX_RACES_ON_SCREEN)
              break;

            nidx = (lss.currentlevel / MAX_RACES_ON_SCREEN + 1) * MAX_RACES_ON_SCREEN;
            CLAMP_UPPER(nidx, cast(int) levels.length - 1);
            levelScreenAction(AA_GO_LVL, nidx);
            break;

          case AM_TOP_EVT:
            if (cast(int) events.length - lss.currentevent <= MAX_RACES_ON_SCREEN)
              break;

            nidx = (lss.currentevent / MAX_RACES_ON_SCREEN + 1) * MAX_RACES_ON_SCREEN;
            CLAMP_UPPER(nidx, cast(int) events.length - 1);
            levelScreenAction(AA_GO_EVT, nidx);
            break;

          case AM_TOP_PRAC:
            if (cast(int) events.length - lss.currentevent <= MAX_RACES_ON_SCREEN)
              break;

            nidx = (lss.currentevent / MAX_RACES_ON_SCREEN + 1) * MAX_RACES_ON_SCREEN;
            CLAMP_UPPER(nidx, cast(int) events.length - 1);
            levelScreenAction(AA_GO_PRAC, nidx);
            break;

          case AM_TOP_PRAC_SEL_PREP:
            nidx = lss.currentlevel + 1;
            CLAMP_UPPER(nidx, cast(int) events[lss.currentevent].levels.length - 1);
            levelScreenAction(AA_PICK_PRAC_LVL, nidx);
            break;

          case AM_TOP_LVL_TIMES:
          case AM_TOP_LVL_BTIMES:
            if (cast(int) current_times.length - lss.currentplayer <= MAX_TIMES_ON_SCREEN)
              break;

            nidx = (lss.currentplayer / MAX_TIMES_ON_SCREEN + 1) * MAX_TIMES_ON_SCREEN;
            CLAMP_UPPER(nidx, cast(int) current_times.length - 1);
            levelScreenAction(AA_SHOWTIMES_LVL, nidx);
            break;

          case AM_TOP_PRAC_TIMES:
          case AM_TOP_PRAC_BTIMES:
            if (cast(int) current_times.length - lss.currentplayer <= MAX_TIMES_ON_SCREEN)
              break;

            nidx = (lss.currentplayer / MAX_TIMES_ON_SCREEN + 1) * MAX_TIMES_ON_SCREEN;
            CLAMP_UPPER(nidx, cast(int) current_times.length - 1);
            levelScreenAction(AA_SHOWTIMES_PRAC, nidx);
            break;

          default:
            break;
        }

        break;
      }

      default:
        break;
    }
  }

  // --- rendering entry points, implemented in mainrender.d ---

  override void resize() { mainResize(this); }

  override void render(float eyetranslation) { mainRender(this, eyetranslation); }
}
