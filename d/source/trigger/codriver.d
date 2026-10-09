// codriver [trigger]
//
// Copyright (C) 2004-2006 Jasmine Langridge, ja-reiko@users.sourceforge.net
// License: GPL version 2 (see included gpl.txt)
//
// Codriver signs (visual) and voice (audio).
module trigger.codriver;

import core.thread : Thread;
import core.time : msecs;
import std.array : split;

import bindings.gl;
import pengine.audio;
import pengine.texture;

/// Maximum number of characters for a note (not a hard limit).
enum size_t note_maxlength = 128;

struct PCodriverUserConfig {
  float life = 3.00f;   ///< How many seconds until the codriver signs start fading.
  float scale = 0.20f;  ///< Scale of the codriver signs.
  float posx = 0.00f;   ///< X scale centering.
  float posy = 0.45f;   ///< Y scale centering.
}

/// Splits the notes in words and greedily matches the longest concatenation of
/// consecutive words (without spaces) present in `table`.
private T[] matchNotes(T)(string notes, T[string] table)
{
  T[] result;
  auto words = notes.split();
  size_t i = 0;
  string tempnote;

  while (i < words.length) {
    T found = null;
    size_t cut = i;
    tempnote = "";

    for (size_t j = i; j < words.length; ++j) {
      tempnote ~= words[j];

      if (auto p = tempnote in table) {
        found = *p;
        cut = j;
      }
    }

    if (found !is null)
      result ~= found;

    i = cut + 1;
  }
  return result;
}

/// Draws the codriver signs for the driver.
final class PCodriverSigns
{
  private PTexture[string] signs;
  private PCodriverUserConfig uc;
  private PTexture[] cpsigns;
  private float cptime = 0;

  this(PTexture[string] signs, PCodriverUserConfig uc)
  {
    this.signs = signs;
    this.uc = uc;
  }

  /// Sets the current codriver signs.
  void set(string notes, float time)
  {
    cpsigns = matchNotes(notes, signs);
    cptime = time;
  }

  /// Draws the current codriver signs.
  void render(float coursetime)
  {
    if (cpsigns.length == 0)
      return;

    float alpha;

    if (coursetime - cptime < uc.life) {
      alpha = 1.0f;
    } else if (coursetime - cptime < uc.life + 1.0f) {
      alpha = (uc.life + 1.0f) - (coursetime - cptime);
    } else {
      cpsigns = null;
      return;
    }

    glPushMatrix();
    glLoadIdentity();
    glOrtho(-1.0, 1.0, -1.0, 1.0, -1.0, 1.0);
    glTranslatef(uc.posx, uc.posy, 0.0f);
    glScalef(uc.scale, uc.scale, 1.0f);
    glTranslatef(-0.5f * cpsigns.length * 2 + 1.0f, 0.0f, 0.0f);
    glColor4f(1.0f, 1.0f, 1.0f, alpha);

    foreach (cptex; cpsigns) {
      cptex.bind();
      glBegin(GL_QUADS);
      glTexCoord2f(1.0f, 1.0f);
      glVertex2f(1.0f, 1.0f);
      glTexCoord2f(0.0f, 1.0f);
      glVertex2f(-1.0f, 1.0f);
      glTexCoord2f(0.0f, 0.0f);
      glVertex2f(-1.0f, -1.0f);
      glTexCoord2f(1.0f, 0.0f);
      glVertex2f(1.0f, -1.0f);
      glEnd();
      glTranslatef(2.0f, 0.0f, 0.0f);
    }

    glPopMatrix();
  }
}

/// Gives a voice to the codriver. Each utterance is played by a background thread.
final class PCodriverVoice
{
  private PAudioSample[string] words;
  private float volume;

  this(PAudioSample[string] words, float volume)
  {
    this.words = words;
    this.volume = volume;
  }

  void say(string notes)
  {
    if (words.length == 0)
      return;

    PAudioSample[] cpwords = matchNotes(notes, words);
    const vol = volume;

    auto t = new Thread({
      foreach (w; cpwords) {
        auto voice = new PAudioInstance(w);

        voice.setGain(vol);
        voice.play();

        while (voice.isPlaying())
          Thread.sleep(50.msecs);

        voice.release();
      }
    });
    t.isDaemon = true;
    t.start();
  }
}
