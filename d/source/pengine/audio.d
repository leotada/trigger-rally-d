// audio [pengine]
//
// Copyright (C) 2004-2006 Jasmine Langridge, ja-reiko@users.sourceforge.net
// License: GPL version 2 (see included gpl.txt)
//
// OpenAL audio subsystem. ALUT is replaced by a small built-in WAV (PCM) parser.
module pengine.audio;

import bindings.openal;
import pengine.app : PApp;
import pengine.pvfs;
import pengine.subsys;
import pengine.util;
import pengine.vmath;

private __gshared ALCdevice* alDevice;
private __gshared ALCcontext* alContext;

final class PSSAudio : PSubsystem
{
  private PResourceList!PAudioSample samplist;

  this(PApp parentApp)
  {
    super(parentApp);
    PUtil.outLog("Initialising audio subsystem [OpenAL]");

    if (!loadOpenAL())
      throw MakePException("OpenAL library could not be loaded");

    alDevice = alcOpenDevice(null);
    if (alDevice is null)
      throw MakePException("OpenAL: alcOpenDevice() error");

    alContext = alcCreateContext(alDevice, null);
    if (alContext is null || alcMakeContextCurrent(alContext) == 0)
      throw MakePException("OpenAL: could not create an audio context");
  }

  override void shutdown()
  {
    PUtil.outLog("Shutting down audio subsystem");
    samplist.clear();
    if (alContext !is null) {
      alcMakeContextCurrent(null);
      alcDestroyContext(alContext);
      alContext = null;
    }
    if (alDevice !is null) {
      alcCloseDevice(alDevice);
      alDevice = null;
    }
  }

  override void tick(float delta, const ref vec3f eyepos, const ref mat44f eyeori, const ref vec3f eyevel)
  {
  }

  PAudioSample loadSample(string name, bool positional3D = true)
  {
    PAudioSample samp = samplist.find(name);

    if (samp is null) {
      try {
        samp = new PAudioSample(name, positional3D);
      } catch (PException e) {
        if (PUtil.isDebugLevel(DEBUGLEVEL_ENDUSER))
          PUtil.outLog("Failed to load ", name, ": ", e.msg);

        return null;
      }
      samplist.add(samp);
    }
    return samp;
  }
}

private uint le32(const(ubyte)[] d, size_t o)
{
  return d[o] | (cast(uint) d[o + 1] << 8) | (cast(uint) d[o + 2] << 16) | (cast(uint) d[o + 3] << 24);
}

private uint le16(const(ubyte)[] d, size_t o)
{
  return d[o] | (cast(uint) d[o + 1] << 8);
}

final class PAudioSample : PResource
{
  private ALuint buffer;

  this(string filename, bool positional3D = false)
  {
    buffer = 0;

    if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
      PUtil.outLog("Loading sample \"", filename, "\"");

    name = filename;
    PFile pfile = PVfs.openRead(filename);

    if (pfile is null)
      throw MakePException("Load failed: PhysFS: " ~ PVfs.lastError);

    auto d = pfile.readAll();
    pfile.close();

    if (d.length < 12 || d[0 .. 4] != cast(const(ubyte)[]) "RIFF" || d[8 .. 12] != cast(const(ubyte)[]) "WAVE")
      throw MakePException("Sample load failed: not a RIFF/WAVE file");

    uint fmtTag = 0, channels = 0, rate = 0, bits = 0;
    const(ubyte)[] pcm;
    bool haveFmt = false;

    size_t pos = 12;
    while (pos + 8 <= d.length) {
      const id = d[pos .. pos + 4];
      size_t len = le32(d, pos + 4);
      const start = pos + 8;
      if (start + len > d.length) len = d.length - start;
      if (id == cast(const(ubyte)[]) "fmt " && len >= 16) {
        fmtTag = le16(d, start);
        channels = le16(d, start + 2);
        rate = le32(d, start + 4);
        bits = le16(d, start + 14);
        if (fmtTag == 0xFFFE && len >= 26)
          fmtTag = le16(d, start + 24); // WAVE_FORMAT_EXTENSIBLE sub format
        haveFmt = true;
      } else if (id == cast(const(ubyte)[]) "data") {
        pcm = d[start .. start + len];
      }
      pos = start + len + (len & 1);
    }

    if (!haveFmt || pcm is null || fmtTag != 1)
      throw MakePException("Sample load failed: unsupported WAV format");

    ALenum format;
    if (channels == 1 && bits == 8) format = AL_FORMAT_MONO8;
    else if (channels == 1 && bits == 16) format = AL_FORMAT_MONO16;
    else if (channels == 2 && bits == 8) format = AL_FORMAT_STEREO8;
    else if (channels == 2 && bits == 16) format = AL_FORMAT_STEREO16;
    else throw MakePException("Sample load failed: unsupported channel/bit depth");

    alGenBuffers(1, &buffer);
    alBufferData(buffer, format, pcm.ptr, cast(ALsizei) pcm.length, cast(ALsizei) rate);

    if (buffer == AL_NONE)
      throw MakePException("Sample load failed");
  }

  void unload()
  {
    if (buffer) {
      alDeleteBuffers(1, &buffer);
      buffer = 0;
    }
  }
}

/// A playing (or ready to play) instance of a sample. Call `release()` when done with it.
final class PAudioInstance
{
  private PAudioSample samp;
  private ALuint source;

  this(PAudioSample _samp, bool looping = false)
  {
    samp = _samp;

    alGenSources(1, &source);

    alSourcei(source, AL_BUFFER, cast(ALint) samp.buffer);
    alSourcei(source, AL_LOOPING, looping ? AL_TRUE : AL_FALSE);
  }

  /// Stops the sound and frees the OpenAL source (the equivalent of the C++ destructor).
  void release()
  {
    if (source == 0) return;
    if (isPlaying()) stop();
    alDeleteSources(1, &source);
    source = 0;
  }

  void update(in vec3f pos, in vec3f vel)
  {
    alSourcefv(source, AL_POSITION, &pos.x);
    alSourcefv(source, AL_VELOCITY, &vel.x);
  }

  void setGain(float gain) { alSourcef(source, AL_GAIN, gain); }
  void setHalfDistance(float lambda) { alSourcef(source, AL_REFERENCE_DISTANCE, lambda); }
  void setPitch(float pitch) { alSourcef(source, AL_PITCH, pitch); }

  void play()
  {
    alSourceRewind(source);
    alSourcePlay(source);
  }

  void stop() { alSourceStop(source); }

  bool isPlaying()
  {
    int state = AL_STOPPED;
    alGetSourcei(source, AL_SOURCE_STATE, &state);
    return state == AL_PLAYING;
  }
}
