// app [pengine]
//
// Copyright 2004-2006 Jasmine Langridge, jas@jareiko.net
// License: GPL version 2 (see included gpl.txt)
//
// The application base class: window/GL/audio initialisation and the main loop.
module pengine.app;

import core.stdc.stdlib : srand, rand;
import std.format : format;
import std.string : fromStringz, toStringz;

import bindings.gl;
import bindings.openal : loadOpenAL;
import bindings.sdl2;
import pengine.audio;
import pengine.fxman;
import pengine.model;
import pengine.pvfs;
import pengine.render;
import pengine.subsys;
import pengine.texture;
import pengine.util;
import pengine.vmath;
import trigger.hiscore1;

enum PACKAGE_VERSION = "0.6.7";

struct joystick_s {
  SDL_Joystick* sdl_joystick;
  SDL_Haptic* sdl_haptic;
  string name;
  float[] axis;
  bool[] button;
  vec2i[] hat;
}

class PApp
{
  enum StereoMode {
    StereoNone,
    StereoQuadBuffer,
    StereoRedBlue,
    StereoRedGreen,
    StereoRedCyan,
    StereoYellowBlue
  }
  alias StereoNone = StereoMode.StereoNone;
  alias StereoQuadBuffer = StereoMode.StereoQuadBuffer;
  alias StereoRedBlue = StereoMode.StereoRedBlue;
  alias StereoRedGreen = StereoMode.StereoRedGreen;
  alias StereoRedCyan = StereoMode.StereoRedCyan;
  alias StereoYellowBlue = StereoMode.StereoYellowBlue;

  HiScore1 best_times;

  private string appname, apptitle;

  private SDL_Window* screen; // TODO: rename this to "window" maybe
  private SDL_GLContext context;

  /// Attempts to set fullscreen at native resolution.
  private bool autoVideo = false;

  protected int cx, cy, bpp;

  private bool fullscr, noframe;
  private bool reqRGB, reqAlpha, reqDepth, reqStencil;
  private bool grabinput;

  private StereoMode stereo;
  private float stereoEyeTranslation;

  private const(ubyte)* sdl_keymap;
  private int sdl_numkeys;
  private uint sdl_mousemap;
  private joystick_s[] sdl_joy;

  private bool exit_requested, screenshot_requested;

  private PSSRender ssrdr;
  private PSSTexture sstex;
  private PSSEffect ssfx;
  private PSSModel ssmod;
  private PSSAudio ssaud;

  // the derived app should keep these up to date
  protected vec3f cam_pos;
  protected mat44f cam_orimat;
  protected vec3f cam_linvel;

  this(string title = "PGame", string name = ".pgame")
  {
    appname = name;   // for ~/.name
    apptitle = title; // for window title
    best_times = new HiScore1("/players");

    if (!loadSDL2()) {
      PUtil.outLog("Failed to load the SDL2 library");
    } else {
      const si = SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER | SDL_INIT_JOYSTICK | SDL_INIT_HAPTIC);

      if (si < 0)
        PUtil.outLog("Failed to initialize SDL: ", SDL_GetErrorString());
    }

    cx = cy = 0;
    bpp = 0;
    fullscr = false;
    noframe = false;
    exit_requested = false;
    screenshot_requested = false;
    reqRGB = reqAlpha = reqDepth = reqStencil = false;
    stereo = StereoMode.StereoNone;
    stereoEyeTranslation = 0.0f;
    grabinput = false;
  }

  int getWidth() const { return cx; }
  int getHeight() const { return cy; }

  int getNumJoysticks() { return cast(int) sdl_joy.length; }
  int getJoyNumAxes(int j) { return cast(int) sdl_joy[j].axis.length; }
  int getJoyNumButtons(int j) { return cast(int) sdl_joy[j].button.length; }
  int getJoyNumHats(int j) { return cast(int) sdl_joy[j].hat.length; }
  float getJoyAxis(int j, int a) { return sdl_joy[j].axis[a]; }
  bool getJoyButton(int j, int b) { return sdl_joy[j].button[b]; }
  vec2i getJoyHat(int j, int h) { return sdl_joy[j].hat[h]; }
  SDL_Haptic* getJoyHaptic(int j) { return sdl_joy[j].sdl_haptic; }

  PSSRender getSSRender() { return ssrdr; }
  PSSTexture getSSTexture() { return sstex; }
  PSSEffect getSSEffect() { return ssfx; }
  PSSModel getSSModel() { return ssmod; }
  PSSAudio getSSAudio() { return ssaud; }

  void automaticVideoMode(bool av = false) { autoVideo = av; }
  void requireRGB(bool req = true) { reqRGB = req; }
  void requireAlpha(bool req = true) { reqAlpha = req; }
  void requireDepth(bool req = true) { reqDepth = req; }
  void requireStencil(bool req = true) { reqStencil = req; }
  void setStereoMode(StereoMode mode) { stereo = mode; }
  void setStereoEyeSeperation(float distance) { stereoEyeTranslation = distance * 0.5f; }

  protected bool keyDown(int key) { return sdl_keymap[key] != 0; }
  protected bool mouseButtonDown(int bt) { return (sdl_mousemap & SDL_BUTTON(bt)) != 0; }
  protected void requestExit() { exit_requested = true; }
  protected void saveScreenshot() { screenshot_requested = true; }

  protected void setScreenBPP(int _bpp)
  {
    if (autoVideo)
      return;

    bpp = _bpp;
  }

  /// Anisotropic filtering level used by the texture subsystem (overridden by the game).
  float getAnisotropy() { return 1.0f; }

  protected void setScreenModeAutoWindow()
  {
    cy = 1024 * 6 / 7;
    cx = cy * 4 / 3;

    fullscr = false;
  }

  protected void setScreenModeFastFullScreen()
  {
    cx = 1280;
    cy = 1024;

    fullscr = false;

    noframe = true;
  }

  /// This routine performs the perspective projection for one eye's subfield.
  /// The projection is in the direction of the negative z axis.
  protected void stereoGLProject(float xmin, float xmax, float ymin, float ymax, float znear, float zfar,
                                 float zzps, float dist, float eye)
  {
    float xmid, ymid, clip_near, clip_far, top, bottom, left, right, dx, dy, n_over_d;

    dx = xmax - xmin;
    dy = ymax - ymin;

    xmid = (xmax + xmin) / 2.0;
    ymid = (ymax + ymin) / 2.0;

    clip_near = dist + zzps - znear;
    clip_far = dist + zzps - zfar;

    n_over_d = clip_near / dist;

    top = n_over_d * dy / 2.0;
    bottom = -top;
    right = n_over_d * (dx / 2.0 - eye);
    left = n_over_d * (-dx / 2.0 - eye);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glFrustum(left, right, bottom, top, clip_near, clip_far);
    glTranslatef(-xmid - eye, -ymid, -zzps - dist);
  }

  protected void stereoFrustum(float xmin, float xmax, float ymin, float ymax, float znear, float zfar,
                               float zzps, float eye)
  {
    float xmove = -eye * znear / zzps;

    glFrustum(xmin + xmove, xmax + xmove, ymin, ymax, znear, zfar);
  }

  /// Set size of game screen
  protected void setScreenMode(int w, int h, bool fullScreen = false, bool hideFrame = false)
  {
    // use automatic video mode
    if (autoVideo) {
      SDL_DisplayMode dm;

      if (SDL_GetCurrentDisplayMode(0, &dm) == 0) {
        cx = dm.w;
        cy = dm.h;
        fullscr = fullScreen;
        noframe = hideFrame;
        PUtil.outLog("Automatic video mode resolution: ", cx, 'x', cy);
      } else {
        PUtil.outLog("SDL error, SDL_GetCurrentDisplayMode(): ", SDL_GetErrorString());
        autoVideo = false;
      }
    }

    // not written as an `else` branch because `autoVideo` may have
    // been updated in the case that automatic video mode failed
    if (!autoVideo) {
      cx = w;
      cy = h;
      fullscr = fullScreen;
      noframe = hideFrame;
    }
  }

  protected void grabMouse(bool grab = true)
  {
    SDL_ShowCursor(grab ? SDL_DISABLE : SDL_ENABLE);

    grabinput = grab;
  }

  protected void drawModel(PModel model, float alpha)
  {
    foreach (mesh; model.mesh) {
      if (mesh.effect is null)
        mesh.effect = getSSEffect().loadEffect(mesh.fxname);

      for (int j = 0; j < mesh.effect.getNumTechniques(); j++) {
        mesh.effect.setCurrentTechnique(j);

        int numPasses = 0;
        if (mesh.effect.renderBegin(numPasses, getSSTexture())) {
          if (mesh.effect.getTechniqueName(j) == "EmissionTechMTL"
              && (getCtrlActionBackValue() < 0.5f || getVehicleCurrentGear() == -1 || alpha < 1.0f)) {
            continue;
          }
          if (alpha < 1.0f) {
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            glEnable(GL_BLEND);
            glColor4f(1.0f, 1.0f, 1.0f, 0.5f);
          }

          for (int i = 0; i < numPasses; i++) {
            mesh.effect.renderPass(i);
            glBegin(GL_TRIANGLES);
            foreach (ref f; mesh.face) {
              foreach (k; 0 .. 3) {
                glNormal3fv(mesh.norm[f.nr[k]]);
                glTexCoord2fv(mesh.texco[f.tc[k]]);
                glVertex3fv(mesh.vert[f.vt[k]]);
              }
            }
            glEnd();
          }
          mesh.effect.renderEnd();
        }
        if (alpha < 1.0f)
          glBlendFunc(GL_ONE, GL_ZERO);
      }
    }
  }

  // callbacks for derived classes
  protected void config() { }  // very light setup/config func
  protected void load() { }    // main resource loading
  protected void unload() { }  // free resources

  protected void tick(float delta) { }
  protected void resize() { }

  protected void render(float eyetranslation)
  {
    glClearColor(0.5, 0.5, 0.5, 0.0);

    glClear(GL_COLOR_BUFFER_BIT);
  }

  protected void keyEvent(in SDL_KeyboardEvent ke)
  {
    if (ke.type != SDL_KEYDOWN) return;

    switch (ke.keysym.sym) {
      case SDLK_ESCAPE:
        requestExit();
        break;
      default:
        break;
    }
  }

  protected void mouseButtonEvent(in SDL_MouseButtonEvent mbe) { }
  protected void mouseMoveEvent(int dx, int dy) { }
  protected void cursorMoveEvent(int posx, int posy) { }
  protected void joyButtonEvent(int which, int button, bool down) { }
  protected bool joyAxisEvent(int which, int axis, float value, bool down) { return false; }

  protected float getCtrlActionBackValue() { return 0.0f; }
  protected int getVehicleCurrentGear() { return 0; }

  private PSubsystem[] sslist;

  private void teardown(bool withWindow)
  {
    foreach_reverse (ss; sslist)
      ss.shutdown();
    sslist = null;

    if (withWindow) {
      if (context !is null) SDL_GL_DeleteContext(context);
      if (screen !is null) SDL_DestroyWindow(screen);
    }
    SDL_Quit();
    PVfs.deinit();
  }

  int run(string[] args)
  {
    PUtil.outLog(apptitle, " init");

    PUtil.outLog("Build: ", PACKAGE_VERSION, " on ", __DATE__, " at ", __TIME__);

    if (exit_requested) {
    PUtil.outLog("Exit requested");
      return 0;
    }

    PUtil.outLog("Initialising virtual file system");

    PVfs.init();

    {
      string lsdbuff = PVfs.getPrefDir("trigger-rally-team", "trigger-rally");

      PUtil.outLog("Setting writable user directory to \"", lsdbuff, "\"");

      if (!PVfs.setWriteDir(lsdbuff))
        PUtil.outLog("Failed to set writable directory to \"", lsdbuff, "\"\nPhysFS: ", PVfs.lastError);

      if (!PVfs.mkdir("/players"))
        PUtil.outLog("Failed to create directory \"/players\"\nPhysFS: ", PVfs.lastError);

      string basedir = PVfs.getBaseDir();
      PUtil.outLog("Application base directory \"", basedir, '"');
      if (!PVfs.mount(basedir, true))
        PUtil.outLog("Failed to add search directory \"", basedir, "\"\nPhysFS: ", PVfs.lastError);

      if (!PVfs.mount(lsdbuff, true))
        PUtil.outLog("Failed to add search directory \"", lsdbuff, "\"\nPhysFS: ", PVfs.lastError);

      // we run MainApp::config() here in order to add data dirs to the search path
      try {
        config();
      } catch (PException e) {
        PUtil.outLog("Config failed: ", e.msg);

        PVfs.deinit();

        return 1;
      }

      // Find any .zip files and add them to search path
      foreach (zf; PUtil.findFiles("", ".zip")) {
        string realpath = PVfs.getRealDir(zf);

        if (realpath !is null) {
          string fullpath = realpath ~ zf;

          if (!PVfs.mount(fullpath, true))
            PUtil.outLog("Failed to add archive \"", fullpath, "\"\nPhysFS: ", PVfs.lastError);
        } else {
          PUtil.outLog("Failed to find path of archive \"", zf, "\"\nPhysFS: ", PVfs.lastError);
        }
      }
    }

    srand(SDL_GetTicks());

    PUtil.outLog("Create window and set video mode");
    SDL_GL_SetAttribute(SDL_GLattr.SDL_GL_DOUBLEBUFFER, 1);

    if (reqRGB) {
      SDL_GL_SetAttribute(SDL_GLattr.SDL_GL_RED_SIZE, 8);
      SDL_GL_SetAttribute(SDL_GLattr.SDL_GL_GREEN_SIZE, 8);
      SDL_GL_SetAttribute(SDL_GLattr.SDL_GL_BLUE_SIZE, 8);
    }

    if (reqAlpha)
      SDL_GL_SetAttribute(SDL_GLattr.SDL_GL_ALPHA_SIZE, 8);

    if (reqDepth)
      SDL_GL_SetAttribute(SDL_GLattr.SDL_GL_DEPTH_SIZE, 24);

    if (reqStencil)
      SDL_GL_SetAttribute(SDL_GLattr.SDL_GL_STENCIL_SIZE, 8);

    if (stereo == StereoMode.StereoQuadBuffer)
      SDL_GL_SetAttribute(SDL_GLattr.SDL_GL_STEREO, 1);

    if (cx <= 0 || cy <= 0) setScreenModeAutoWindow();

    if (!autoVideo) {
      screen = SDL_CreateWindow(apptitle.toStringz, SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                cx, cy, SDL_WINDOW_OPENGL | (fullscr ? SDL_WINDOW_FULLSCREEN : 0));
    } else { // automatic video mode
      // NOTE: SDL_WINDOW_FULLSCREEN_DESKTOP is unreliable on Linux in some SDL2 versions,
      // so the desktop display mode is queried instead.
      SDL_DisplayMode dm;

      if (SDL_GetDesktopDisplayMode(0, &dm) == 0) {
        cx = dm.w;
        cy = dm.h;
        PUtil.outLog("Desktop video mode resolution: ", cx, 'x', cy);
      } else {
        PUtil.outLog("SDL error, SDL_GetDesktopDisplayMode(): ", SDL_GetErrorString());
        cx = 800;
        cy = 600;
      }

      screen = SDL_CreateWindow(apptitle.toStringz, SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                cx, cy, SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN);
    }

    if (screen is null) {
      PUtil.outLog("Failed to create window or set video mode");
      PUtil.outLog("SDL error: ", SDL_GetErrorString());
      PUtil.outLog("Try changing your video settings in trigger-rally.config");
      teardown(false);
      return 1;
    }

    context = SDL_GL_CreateContext(screen);

    if (context is null) {
      PUtil.outLog("Failed to create OpenGL context for game window");
      PUtil.outLog("SDL error: ", SDL_GetErrorString());
      teardown(true);
      return 1;
    }

    sdl_mousemap = 0;

    sdl_joy.length = SDL_NumJoysticks();

    PUtil.outLog("Found ", sdl_joy.length, " joystick", sdl_joy.length == 1 ? "" : "s");

    for (int i = 0; i < cast(int) sdl_joy.length; i++) {
      PUtil.outLog("Joystick ", i + 1, ": ");
      sdl_joy[i].sdl_joystick = SDL_JoystickOpen(i);
      if (sdl_joy[i].sdl_joystick is null) {
        PUtil.outLog("failed to open joystick");
        teardown(true);
        return 1;
      }
      auto js = sdl_joy[i].sdl_joystick;
      sdl_joy[i].name = fromStringz(SDL_JoystickName(js)).idup;
      sdl_joy[i].axis.length = SDL_JoystickNumAxes(js);
      foreach (j; 0 .. sdl_joy[i].axis.length)
        sdl_joy[i].axis[j] = (cast(float) SDL_JoystickGetAxis(js, cast(int) j) + 0.5f) / 32767.5f;
      sdl_joy[i].button.length = SDL_JoystickNumButtons(js);
      foreach (j; 0 .. sdl_joy[i].button.length)
        sdl_joy[i].button[j] = (SDL_JoystickGetButton(js, cast(int) j) != 0);
      sdl_joy[i].hat.length = SDL_JoystickNumHats(js);
      foreach (j; 0 .. sdl_joy[i].hat.length) {
        ubyte state = SDL_JoystickGetHat(js, cast(int) j);
        sdl_joy[i].hat[j] = vec2i.zero();
        if (state & SDL_HAT_RIGHT) sdl_joy[i].hat[j].x = 1;
        else if (state & SDL_HAT_LEFT) sdl_joy[i].hat[j].x = -1;
        if (state & SDL_HAT_UP) sdl_joy[i].hat[j].y = 1;
        else if (state & SDL_HAT_DOWN) sdl_joy[i].hat[j].y = -1;
      }

      PUtil.outLog(sdl_joy[i].name, ", ", sdl_joy[i].axis.length, " axis, ", sdl_joy[i].button.length,
                   " button, ", sdl_joy[i].hat.length, " hat");

      sdl_joy[i].sdl_haptic = SDL_HapticOpenFromJoystick(js);
      if (sdl_joy[i].sdl_haptic !is null) {
        if (SDL_HapticRumbleInit(sdl_joy[i].sdl_haptic) != 0) {
          SDL_HapticClose(sdl_joy[i].sdl_haptic);
          sdl_joy[i].sdl_haptic = null;
        }
      }
    }

    SDL_JoystickEventState(SDL_ENABLE);

    auto missing = loadGL();
    if (missing.length) {
      // ARB extension entry points are optional (VBO emulation); core ones are not
      string[] core;
      foreach (m; missing)
        if (m.length < 3 || m[$ - 3 .. $] != "ARB") core ~= m;
      if (core.length) {
        PUtil.outLog("OpenGL entry points missing: ", core);
        teardown(true);
        return 1;
      }
    }

    PUtil.outLog("OpenGL entry points loaded");

    PUtil.outLog("Graphics: ", fromStringz(cast(const(char)*) glGetString(GL_VENDOR)), " ",
                 fromStringz(cast(const(char)*) glGetString(GL_RENDERER)));

    PUtil.outLog("Using OpenGL ", fromStringz(cast(const(char)*) glGetString(GL_VERSION)));

    final switch (stereo) {
      case StereoMode.StereoNone:
        break;
      case StereoMode.StereoQuadBuffer:
        PUtil.outLog("Using hardware quad buffer stereo, separation =", stereoEyeTranslation * 2.0f);
        break;
      case StereoMode.StereoRedBlue:
        PUtil.outLog("Using red-blue anaglyph stereo, separation = ", stereoEyeTranslation * 2.0f);
        break;
      case StereoMode.StereoRedGreen:
        PUtil.outLog("Using red-green anaglyph stereo, separation = ", stereoEyeTranslation * 2.0f);
        break;
      case StereoMode.StereoRedCyan:
        PUtil.outLog("Using red-cyan anaglyph stereo, separation = ", stereoEyeTranslation * 2.0f);
        break;
      case StereoMode.StereoYellowBlue:
        PUtil.outLog("Using yellow-blue anaglyph stereo, separation = ", stereoEyeTranslation * 2.0f);
        break;
    }

    try {
      sslist ~= (ssrdr = new PSSRender(this));
      sslist ~= (sstex = new PSSTexture(this));
      sslist ~= (ssfx = new PSSEffect(this));
      sslist ~= (ssmod = new PSSModel(this));
      sslist ~= (ssaud = new PSSAudio(this));
    } catch (PException e) {
      PUtil.outLog("Subsystem failed to init: ", e.msg);
      teardown(true);
      return 1;
    }

    PUtil.outLog("Performing app load");

    try {
      load();
    } catch (PException e) {
      PUtil.outLog("App load failed: ", e.msg);
      teardown(true);
      return 1;
    }

    sdl_keymap = SDL_GetKeyboardState(&sdl_numkeys);

    resize();

    PUtil.outLog("Initialisation complete, entering main loop");

    srand(rand() + SDL_GetTicks());

    bool active = true, repaint = true, axis_down = false;
    uint curtime = SDL_GetTicks() - 1;

    while (true) {
      SDL_Event event;

      while (SDL_PollEvent(&event)) {
        switch (event.type) {
          case SDL_KEYDOWN:
          case SDL_KEYUP:
            keyEvent(event.key);
            break;

          case SDL_MOUSEMOTION:
            if (grabinput)
              mouseMoveEvent(event.motion.xrel, -event.motion.yrel);
            else
              cursorMoveEvent(event.motion.x, event.motion.y);
            break;

          case SDL_MOUSEBUTTONDOWN:
          case SDL_MOUSEBUTTONUP:
            mouseButtonEvent(event.button);
            break;

          case SDL_JOYAXISMOTION:
            sdl_joy[event.jaxis.which].axis[event.jaxis.axis] = (cast(float) event.jaxis.value + 0.5f) / 32767.5f;
            axis_down = joyAxisEvent(event.jaxis.which, event.jaxis.axis,
                                     sdl_joy[event.jaxis.which].axis[event.jaxis.axis], axis_down);
            break;

          case SDL_JOYBUTTONDOWN:
            sdl_joy[event.jbutton.which].button[event.jbutton.button] = true;
            joyButtonEvent(event.jbutton.which, event.jbutton.button, true);
            break;

          case SDL_JOYBUTTONUP:
            sdl_joy[event.jbutton.which].button[event.jbutton.button] = false;
            joyButtonEvent(event.jbutton.which, event.jbutton.button, false);
            break;

          case SDL_JOYHATMOTION: {
            auto h = &sdl_joy[event.jhat.which].hat[event.jhat.hat];
            *h = vec2i.zero();
            if (event.jhat.value & SDL_HAT_RIGHT) h.x = 1;
            else if (event.jhat.value & SDL_HAT_LEFT) h.x = -1;
            if (event.jhat.value & SDL_HAT_UP) h.y = 1;
            else if (event.jhat.value & SDL_HAT_DOWN) h.y = -1;
            break;
          }

          case SDL_QUIT:
            requestExit();
            break;

          default:
            break;
        }
        if (exit_requested) break;
      }

      if (exit_requested)
        break;

      sdl_mousemap = SDL_GetMouseState(null, null);

      enum TIMESCALE = 1.0;

      uint nowtime = SDL_GetTicks();

      {
        uint timepassed = nowtime - curtime;
        if (timepassed > 100) timepassed = 100;
        if (timepassed > 0) {
          float delta = cast(float) timepassed * 0.001 * TIMESCALE;

          tick(delta);

          foreach (ss; sslist)
            ss.tick(delta, cam_pos, cam_orimat, cam_linvel);
        }
      }

      curtime = nowtime;

      if (exit_requested) break;

      if (active || repaint) {
        final switch (stereo) {
          case StereoMode.StereoNone: // Normal, non-stereo rendering
            render(0.0f);
            glFlush();
            SDL_GL_SwapWindow(screen);
            break;

          case StereoMode.StereoQuadBuffer: // Hardware quad buffer stereo
            glDrawBuffer(GL_BACK_LEFT);
            render(-stereoEyeTranslation);
            glFlush();

            glDrawBuffer(GL_BACK_RIGHT);
            render(stereoEyeTranslation);
            glFlush();

            SDL_GL_SwapWindow(screen);
            break;

          case StereoMode.StereoRedBlue: // Red-blue anaglyph stereo
            // Green will not be rendered to, so clear it
            glColorMask(GL_FALSE, GL_TRUE, GL_FALSE, GL_TRUE);
            glClearColor(0.5, 0.5, 0.5, 0.5);
            glClear(GL_COLOR_BUFFER_BIT);

            glColorMask(GL_TRUE, GL_FALSE, GL_FALSE, GL_TRUE);
            render(-stereoEyeTranslation);
            glFlush();

            glColorMask(GL_FALSE, GL_FALSE, GL_TRUE, GL_TRUE);
            render(stereoEyeTranslation);
            glFlush();

            SDL_GL_SwapWindow(screen);
            break;

          case StereoMode.StereoRedGreen: // Red-green anaglyph stereo
            // Blue will not be rendered to, so clear it
            glColorMask(GL_FALSE, GL_FALSE, GL_TRUE, GL_TRUE);
            glClearColor(0.5, 0.5, 0.5, 0.5);
            glClear(GL_COLOR_BUFFER_BIT);

            glColorMask(GL_TRUE, GL_FALSE, GL_FALSE, GL_TRUE);
            render(-stereoEyeTranslation);
            glFlush();

            glColorMask(GL_FALSE, GL_TRUE, GL_FALSE, GL_TRUE);
            render(stereoEyeTranslation);
            glFlush();

            SDL_GL_SwapWindow(screen);
            break;

          case StereoMode.StereoRedCyan: // Red-cyan anaglyph stereo
            glColorMask(GL_TRUE, GL_FALSE, GL_FALSE, GL_TRUE);
            render(-stereoEyeTranslation);
            glFlush();

            glColorMask(GL_FALSE, GL_TRUE, GL_TRUE, GL_TRUE);
            render(stereoEyeTranslation);
            glFlush();

            SDL_GL_SwapWindow(screen);
            break;

          case StereoMode.StereoYellowBlue: // Yellow-blue anaglyph stereo
            glColorMask(GL_TRUE, GL_TRUE, GL_FALSE, GL_TRUE);
            render(-stereoEyeTranslation);
            glFlush();

            glColorMask(GL_FALSE, GL_FALSE, GL_TRUE, GL_TRUE);
            render(stereoEyeTranslation);
            glFlush();

            SDL_GL_SwapWindow(screen);
            break;
        }
        repaint = false;

        if (screenshot_requested) {
          glReadBuffer(GL_FRONT);
          ubyte[] data1 = new ubyte[cx * (cy + 1) * 3];
          glReadPixels(0, 0, cx, cy, GL_RGB, GL_UNSIGNED_BYTE, data1.ptr);
          glReadBuffer(GL_BACK);
          const rowsize = cx * 3;
          for (int i = 0; i < cy / 2; ++i) {
            // swap rows i and cy-1-i (image is stored bottom-up by OpenGL)
            data1[cy * rowsize .. cy * rowsize + rowsize] = data1[(cy - 1 - i) * rowsize .. (cy - i) * rowsize];
            data1[(cy - 1 - i) * rowsize .. (cy - i) * rowsize] = data1[i * rowsize .. (i + 1) * rowsize];
            data1[i * rowsize .. (i + 1) * rowsize] = data1[cy * rowsize .. cy * rowsize + rowsize];
          }
          string header = format("P6\n# CREATOR: Trigger PNM Screenshot\n%d %d\n255\n", cx, cy);
          string filename = format("screen-%09u.ppm", SDL_GetTicks());
          PUtil.outLog("Writing screenshot \"", filename, "\"");
          PFile pfile = PVfs.openWrite(filename);
          if (pfile !is null) {
            pfile.write(header);
            pfile.write(data1[0 .. cx * cy * 3]);
            pfile.close();
          } else {
            PUtil.outLog("Screenshot write failed");
            PUtil.outLog("PhysFS: ", PVfs.lastError);
          }
          screenshot_requested = false;
        }
      } else {
        SDL_WaitEvent(null);
      }

      if (exit_requested) break;
    }

    PUtil.outLog("Exit requested");

    unload();

    foreach_reverse (ss; sslist)
      ss.shutdown();
    sslist = null;

    SDL_ShowCursor(SDL_ENABLE);

    SDL_GL_DeleteContext(context);
    SDL_DestroyWindow(screen);
    SDL_Quit();

    best_times.savePlayer();

    PVfs.deinit();

    PUtil.outLog("Shutdown complete");

    return 0;
  }
}
