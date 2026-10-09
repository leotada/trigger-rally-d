/// Minimal hand-written OpenAL bindings, loaded at run time with dlopen.
module bindings.openal;

import core.sys.posix.dlfcn;
import std.traits : ReturnType, Parameters;
import std.string : toStringz;

alias ALuint = uint;
alias ALint = int;
alias ALenum = int;
alias ALsizei = int;
alias ALboolean = byte;
alias ALfloat = float;

struct ALCdevice;
struct ALCcontext;

enum : ALenum {
  AL_NONE = 0,
  AL_FALSE = 0,
  AL_TRUE = 1,
  AL_PITCH = 0x1003,
  AL_POSITION = 0x1004,
  AL_VELOCITY = 0x1006,
  AL_LOOPING = 0x1007,
  AL_BUFFER = 0x1009,
  AL_GAIN = 0x100A,
  AL_SOURCE_STATE = 0x1010,
  AL_PLAYING = 0x1012,
  AL_STOPPED = 0x1014,
  AL_REFERENCE_DISTANCE = 0x1020,
  AL_FORMAT_MONO8 = 0x1100,
  AL_FORMAT_MONO16 = 0x1101,
  AL_FORMAT_STEREO8 = 0x1102,
  AL_FORMAT_STEREO16 = 0x1103,
}

private struct ALProcs {
  extern (C) nothrow {
    void function(ALsizei, ALuint*) alGenSources;
    void function(ALsizei, const(ALuint)*) alDeleteSources;
    void function(ALsizei, ALuint*) alGenBuffers;
    void function(ALsizei, const(ALuint)*) alDeleteBuffers;
    void function(ALuint, ALenum, const(void)*, ALsizei, ALsizei) alBufferData;
    void function(ALuint, ALenum, ALint) alSourcei;
    void function(ALuint, ALenum, ALfloat) alSourcef;
    void function(ALuint, ALenum, const(ALfloat)*) alSourcefv;
    void function(ALuint, ALenum, ALint*) alGetSourcei;
    void function(ALuint) alSourcePlay;
    void function(ALuint) alSourceStop;
    void function(ALuint) alSourceRewind;
    ALenum function() alGetError;
    ALCdevice* function(const(char)*) alcOpenDevice;
    ALCcontext* function(ALCdevice*, const(ALint)*) alcCreateContext;
    ALboolean function(ALCcontext*) alcMakeContextCurrent;
    void function(ALCcontext*) alcDestroyContext;
    ALboolean function(ALCdevice*) alcCloseDevice;
  }
}

private __gshared ALProcs procs;
private __gshared void* libHandle;

/// Loads the OpenAL shared library. Returns false on failure.
bool loadOpenAL()
{
  if (libHandle !is null) return true;

  foreach (name; ["libopenal.so.1", "libopenal.so"]) {
    libHandle = dlopen(name.toStringz, RTLD_NOW | RTLD_GLOBAL);
    if (libHandle !is null) break;
  }
  if (libHandle is null) return false;

  static foreach (m; __traits(allMembers, ALProcs)) {
    __traits(getMember, procs, m) = cast(typeof(__traits(getMember, procs, m))) dlsym(libHandle, m.toStringz);
    if (__traits(getMember, procs, m) is null) return false;
  }
  return true;
}

static foreach (m; __traits(allMembers, ALProcs)) {
  mixin("pragma(inline, true) ReturnType!(typeof(ALProcs." ~ m ~ ")) " ~ m ~ "(Parameters!(typeof(ALProcs." ~ m ~ ")) args) { return procs." ~ m ~ "(args); }");
}
