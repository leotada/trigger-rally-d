// Copyright (C) 2004-2006 Jasmine Langridge and contributors (see the NOTICE file)
// Part of the D port of Trigger Rally.
// License: GNU General Public License, version 2 or later (see COPYING.txt)
/// Minimal hand-written SDL2 bindings, loaded at run time with dlopen.
module bindings.sdl2;

import core.sys.posix.dlfcn;
import std.traits : ReturnType, Parameters;
import std.string : toStringz, fromStringz;

alias Uint8 = ubyte;
alias Uint16 = ushort;
alias Uint32 = uint;
alias Sint16 = short;
alias Sint32 = int;

alias SDL_Keycode = Sint32;
alias SDL_Scancode = int;
alias SDL_JoystickID = Sint32;

struct SDL_Window;
struct SDL_Joystick;
struct SDL_Haptic;
alias SDL_GLContext = void*;

enum : Uint32 {
  SDL_INIT_TIMER = 0x00000001,
  SDL_INIT_VIDEO = 0x00000020,
  SDL_INIT_JOYSTICK = 0x00000200,
  SDL_INIT_HAPTIC = 0x00001000,
}

enum : Uint32 {
  SDL_WINDOW_FULLSCREEN = 0x00000001,
  SDL_WINDOW_OPENGL = 0x00000002,
}

enum SDL_WINDOWPOS_UNDEFINED = 0x1FFF0000;

enum SDL_GLattr : int {
  SDL_GL_RED_SIZE,
  SDL_GL_GREEN_SIZE,
  SDL_GL_BLUE_SIZE,
  SDL_GL_ALPHA_SIZE,
  SDL_GL_BUFFER_SIZE,
  SDL_GL_DOUBLEBUFFER,
  SDL_GL_DEPTH_SIZE,
  SDL_GL_STENCIL_SIZE,
  SDL_GL_ACCUM_RED_SIZE,
  SDL_GL_ACCUM_GREEN_SIZE,
  SDL_GL_ACCUM_BLUE_SIZE,
  SDL_GL_ACCUM_ALPHA_SIZE,
  SDL_GL_STEREO,
}

enum : Uint32 {
  SDL_QUIT = 0x100,
  SDL_KEYDOWN = 0x300,
  SDL_KEYUP = 0x301,
  SDL_MOUSEMOTION = 0x400,
  SDL_MOUSEBUTTONDOWN = 0x401,
  SDL_MOUSEBUTTONUP = 0x402,
  SDL_JOYAXISMOTION = 0x600,
  SDL_JOYBALLMOTION = 0x601,
  SDL_JOYHATMOTION = 0x602,
  SDL_JOYBUTTONDOWN = 0x603,
  SDL_JOYBUTTONUP = 0x604,
}

enum SDL_SCANCODE_MASK = 1 << 30;
enum : SDL_Keycode {
  SDLK_UNKNOWN = 0,
  SDLK_RETURN = '\r',
  SDLK_ESCAPE = 27,
  SDLK_F12 = 69 | SDL_SCANCODE_MASK,
  SDLK_RIGHT = 79 | SDL_SCANCODE_MASK,
  SDLK_LEFT = 80 | SDL_SCANCODE_MASK,
  SDLK_KP_ENTER = 88 | SDL_SCANCODE_MASK,
}

enum : Uint8 {
  SDL_HAT_UP = 0x01,
  SDL_HAT_RIGHT = 0x02,
  SDL_HAT_DOWN = 0x04,
  SDL_HAT_LEFT = 0x08,
}

enum SDL_DISABLE = 0;
enum SDL_ENABLE = 1;

Uint32 SDL_BUTTON(int x) { return 1u << (x - 1); }

struct SDL_Keysym {
  SDL_Scancode scancode;
  SDL_Keycode sym;
  Uint16 mod;
  Uint32 unused;
}

struct SDL_KeyboardEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 windowID;
  Uint8 state;
  Uint8 repeat;
  Uint8 padding2;
  Uint8 padding3;
  SDL_Keysym keysym;
}

struct SDL_MouseMotionEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 windowID;
  Uint32 which;
  Uint32 state;
  Sint32 x;
  Sint32 y;
  Sint32 xrel;
  Sint32 yrel;
}

struct SDL_MouseButtonEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 windowID;
  Uint32 which;
  Uint8 button;
  Uint8 state;
  Uint8 clicks;
  Uint8 padding1;
  Sint32 x;
  Sint32 y;
}

struct SDL_JoyAxisEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_JoystickID which;
  Uint8 axis;
  Uint8 padding1;
  Uint8 padding2;
  Uint8 padding3;
  Sint16 value;
  Uint16 padding4;
}

struct SDL_JoyButtonEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_JoystickID which;
  Uint8 button;
  Uint8 state;
  Uint8 padding1;
  Uint8 padding2;
}

struct SDL_JoyHatEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_JoystickID which;
  Uint8 hat;
  Uint8 value;
  Uint8 padding1;
  Uint8 padding2;
}

union SDL_Event {
  Uint32 type;
  SDL_KeyboardEvent key;
  SDL_MouseMotionEvent motion;
  SDL_MouseButtonEvent button;
  SDL_JoyAxisEvent jaxis;
  SDL_JoyButtonEvent jbutton;
  SDL_JoyHatEvent jhat;
  Uint8[56] padding;
}

struct SDL_DisplayMode {
  Uint32 format;
  int w;
  int h;
  int refresh_rate;
  void* driverdata;
}

private struct SDLProcs {
  extern (C) nothrow {
    int function(Uint32) SDL_Init;
    void function() SDL_Quit;
    const(char)* function() SDL_GetError;
    Uint32 function() SDL_GetTicks;
    int function(SDL_GLattr, int) SDL_GL_SetAttribute;
    SDL_Window* function(const(char)*, int, int, int, int, Uint32) SDL_CreateWindow;
    void function(SDL_Window*) SDL_DestroyWindow;
    SDL_GLContext function(SDL_Window*) SDL_GL_CreateContext;
    void function(SDL_GLContext) SDL_GL_DeleteContext;
    void function(SDL_Window*) SDL_GL_SwapWindow;
    void* function(const(char)*) SDL_GL_GetProcAddress;
    int function(const(char)*) SDL_GL_ExtensionSupported;
    int function(int, SDL_DisplayMode*) SDL_GetCurrentDisplayMode;
    int function(int, SDL_DisplayMode*) SDL_GetDesktopDisplayMode;
    int function(SDL_Event*) SDL_PollEvent;
    int function(SDL_Event*) SDL_WaitEvent;
    const(Uint8)* function(int*) SDL_GetKeyboardState;
    Uint32 function(int*, int*) SDL_GetMouseState;
    SDL_Keycode function(const(char)*) SDL_GetKeyFromName;
    const(char)* function(SDL_Keycode) SDL_GetKeyName;
    SDL_Scancode function(SDL_Keycode) SDL_GetScancodeFromKey;
    int function(int) SDL_ShowCursor;
    int function() SDL_NumJoysticks;
    SDL_Joystick* function(int) SDL_JoystickOpen;
    const(char)* function(SDL_Joystick*) SDL_JoystickName;
    int function(SDL_Joystick*) SDL_JoystickNumAxes;
    int function(SDL_Joystick*) SDL_JoystickNumButtons;
    int function(SDL_Joystick*) SDL_JoystickNumHats;
    Sint16 function(SDL_Joystick*, int) SDL_JoystickGetAxis;
    Uint8 function(SDL_Joystick*, int) SDL_JoystickGetButton;
    Uint8 function(SDL_Joystick*, int) SDL_JoystickGetHat;
    int function(int) SDL_JoystickEventState;
    SDL_Haptic* function(SDL_Joystick*) SDL_HapticOpenFromJoystick;
    int function(SDL_Haptic*) SDL_HapticRumbleInit;
    int function(SDL_Haptic*, float, Uint32) SDL_HapticRumblePlay;
    void function(SDL_Haptic*) SDL_HapticClose;
  }
}

private __gshared SDLProcs procs;
private __gshared void* libHandle;

/// Loads the SDL2 shared library. Returns false on failure.
bool loadSDL2()
{
  if (libHandle !is null) return true;

  foreach (name; ["libSDL2-2.0.so.0", "libSDL2.so", "libSDL2-2.0.so"]) {
    libHandle = dlopen(name.toStringz, RTLD_NOW | RTLD_GLOBAL);
    if (libHandle !is null) break;
  }
  if (libHandle is null) return false;

  static foreach (m; __traits(allMembers, SDLProcs)) {
    __traits(getMember, procs, m) = cast(typeof(__traits(getMember, procs, m))) dlsym(libHandle, m.toStringz);
    if (__traits(getMember, procs, m) is null) return false;
  }
  return true;
}

// Forwarding D functions with the same names as the C API.
static foreach (m; __traits(allMembers, SDLProcs)) {
  mixin("pragma(inline, true) ReturnType!(typeof(SDLProcs." ~ m ~ ")) " ~ m ~ "(Parameters!(typeof(SDLProcs." ~ m ~ ")) args) { return procs." ~ m ~ "(args); }");
}

string SDL_GetErrorString()
{
  return fromStringz(procs.SDL_GetError()).idup;
}
