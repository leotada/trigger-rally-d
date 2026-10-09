// render [pengine]
//
// Copyright 2004-2006 Jasmine Langridge, jas@jareiko.net
// License: GPL version 2 (see included gpl.txt)
//
// Render subsystem: particle systems, text drawing and model drawing.
module pengine.render;

import bindings.gl;
import pengine.app : PApp;
import pengine.fxman;
import pengine.model;
import pengine.subsys;
import pengine.texture;
import pengine.util;
import pengine.vmath;

struct PParticle_s
{
  vec3f pos, linvel;
  float life = 0;

  vec2f orix, oriy; // orientation vectors (2d)
}

final class PParticleSystem
{
  float[4] colorstart = [1.0f, 1.0f, 1.0f, 1.0f];
  float[4] colorend = [1.0f, 1.0f, 1.0f, 0.0f];
  float startsize = 0.0f, endsize = 1.0f;
  float decay = 1.0f;
  PTexture tex = null;
  GLenum blendparam1 = GL_SRC_ALPHA, blendparam2 = GL_ONE;

  PParticle_s[] part;

  void setColorStart(float r, float g, float b, float a)
  {
    colorstart[0] = r; colorstart[1] = g; colorstart[2] = b; colorstart[3] = a;
  }

  void setColorEnd(float r, float g, float b, float a)
  {
    colorend[0] = r; colorend[1] = g; colorend[2] = b; colorend[3] = a;
  }

  void setColor(float r, float g, float b)
  {
    colorstart[0] = colorend[0] = r;
    colorstart[1] = colorend[1] = g;
    colorstart[2] = colorend[2] = b;
  }

  void setSize(float start, float end)
  {
    startsize = start; endsize = end;
  }

  void setDecay(float _decay) { decay = _decay; }

  void setTexture(PTexture texptr) { tex = texptr; }

  void setBlend(GLenum b1, GLenum b2)
  {
    blendparam1 = b1;
    blendparam2 = b2;
  }

  void addParticle(in vec3f pos, in vec3f linvel)
  {
    PParticle_s p;
    p.pos = pos;
    p.linvel = linvel;
    p.life = 1.0f;

    float ang = randm11() * PI;
    p.orix = vec2f(cos(ang), sin(ang));
    p.oriy = vec2f(-sin(ang), cos(ang));
    part ~= p;
  }

  void tick(float delta)
  {
    float decr = delta * decay;

    // update life and delete dead particles
    size_t j = 0;
    for (size_t i = 0; i < part.length; i++) {
      part[j] = part[i];
      part[j].life -= decr;
      if (part[j].life > 0.0) j++;
    }
    part.length = j;

    for (size_t i = 0; i < part.length; i++) {
      part[i].pos += part[i].linvel * delta;
    }
  }
}

private import std.math : cos, sin;

struct PVert_tv
{
  vec2f st;
  vec3f xyz;
}

enum uint PTEXT_HZA_LEFT = 0x00000000; // default
enum uint PTEXT_HZA_CENTER = 0x00000001;
enum uint PTEXT_HZA_RIGHT = 0x00000002;
enum uint PTEXT_VTA_BOTTOM = 0x00000000; // default
enum uint PTEXT_VTA_CENTER = 0x00000100;
enum uint PTEXT_VTA_TOP = 0x00000200;
enum uint PTEXT_HIGHLIGHT = 0x00010000;

/// The Char at (0, 11) is used to display "unprintable" characters.
private enum PTEXT_HARDCODED_DEFAROW = 0;
private enum PTEXT_HARDCODED_DEFACOL = 11;

/// Hardcoded positions for the characters in the font texture, one string per row
/// (bottom row first); the index in the string is the column.
private immutable string[8] fontRows = [
  "&'()*+,-./ ",   // row 0
  "\\]^_:;?!\"#$%", // row 1
  "89<=>`@{|}~[",  // row 2
  "WXYZ01234567",  // row 3
  "KLMNOPQRSTUV",  // row 4
  "yzABCDEFGHIJ",  // row 5
  "mnopqrstuvwx",  // row 6
  "abcdefghijkl",  // row 7
];

private bool lookupGlyph(char c, out int row, out int col)
{
  foreach (r, s; fontRows)
    foreach (i, ch; s)
      if (ch == c) {
        row = cast(int) r;
        col = cast(int) i;
        return true;
      }
  return false;
}

final class PSSRender : PSubsystem
{
  private vec3f cam_pos;
  private mat44f cam_orimat;

  this(PApp parentApp)
  {
    super(parentApp);
    PUtil.outLog("Initialising render subsystem");
  }

  override void shutdown()
  {
    PUtil.outLog("Shutting down render subsystem");
  }

  override void tick(float delta, const ref vec3f eyepos, const ref mat44f eyeori, const ref vec3f eyevel)
  {
    cam_pos = eyepos;
    cam_orimat = eyeori;
  }

  void render(PParticleSystem psys)
  {
    vec3f pushx = makevec3f(cam_orimat.row[0]);
    vec3f pushy = makevec3f(cam_orimat.row[1]);
    vec3f vert;

    glBlendFunc(psys.blendparam1, psys.blendparam2);

    if (psys.tex !is null) psys.tex.bind();
    else glDisable(GL_TEXTURE_2D);

    glBegin(GL_QUADS);
    for (size_t i = 0; i < psys.part.length; i++) {
      PParticle_s* part = &psys.part[i];
      float sizenow = INTERP(psys.endsize, psys.startsize, part.life);
      vec3f pushxt = pushx * sizenow;
      vec3f pushyt = pushy * sizenow;
      vec3f pushx2 = pushxt * part.orix.x + pushyt * part.orix.y;
      vec3f pushy2 = pushxt * part.oriy.x + pushyt * part.oriy.y;

      glColor4f(INTERP(psys.colorend[0], psys.colorstart[0], part.life),
                INTERP(psys.colorend[1], psys.colorstart[1], part.life),
                INTERP(psys.colorend[2], psys.colorstart[2], part.life),
                INTERP(psys.colorend[3], psys.colorstart[3], part.life));

      vert = part.pos - pushx2 - pushy2;
      glTexCoord2i(0, 0);
      glVertex3fv(vert);
      vert = part.pos + pushx2 - pushy2;
      glTexCoord2i(1, 0);
      glVertex3fv(vert);
      vert = part.pos + pushx2 + pushy2;
      glTexCoord2i(1, 1);
      glVertex3fv(vert);
      vert = part.pos - pushx2 + pushy2;
      glTexCoord2i(0, 1);
      glVertex3fv(vert);
    }
    glEnd();

    if (psys.tex is null) glEnable(GL_TEXTURE_2D);
  }

  void drawModel(PModel model, PSSEffect ssEffect, PSSTexture ssTexture)
  {
    foreach (mesh; model.mesh) {
      if (mesh.effect is null)
        mesh.effect = ssEffect.loadEffect(mesh.fxname);

      int numPasses = 0;
      if (mesh.effect.renderBegin(numPasses, ssTexture)) {
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
    }
  }

  /// Draws a text to the screen. Flags can be
  /// (PTEXT_VTA_CENTER xor PTEXT_VTA_TOP) or (PTEXT_HZA_CENTER xor PTEXT_HZA_RIGHT).
  void drawText(string text, uint flags)
  {
    const GLfloat font_aspect = 8.0f / 12.0f;
    const GLfloat addx = 1.0f / 12.0f;
    const GLfloat addy = 1.0f / 8.0f;

    float[4] color;
    glGetFloatv(GL_CURRENT_COLOR, color);

    glPushMatrix();

    if (flags & PTEXT_VTA_CENTER)
      glTranslatef(0.0f, -0.5f, 0.0f);
    else if (flags & PTEXT_VTA_TOP)
      glTranslatef(0.0f, -1.0f, 0.0f);

    if (flags & PTEXT_HZA_CENTER)
      glTranslatef(-0.5f * text.length * font_aspect, 0.0f, 0.0f);
    else if (flags & PTEXT_HZA_RIGHT)
      glTranslatef(-1.0f * text.length * font_aspect, 0.0f, 0.0f);

    foreach (idx; 0 .. text.length) {
      const char ch = text[idx];
      GLfloat tx;
      GLfloat ty;

      int row, col;
      if (lookupGlyph(ch, row, col)) {
        tx = col * addx;
        ty = row * addy;
      } else {
        tx = PTEXT_HARDCODED_DEFACOL * addx;
        ty = PTEXT_HARDCODED_DEFAROW * addy;
      }

      if (flags & PTEXT_HIGHLIGHT) {
        float ystart = 0.0f;
        float yend = font_aspect;

        if (text.length != 1) {
          if (idx == 0)
            yend = font_aspect * 0.875f;
          else if (idx == text.length - 1)
            ystart = font_aspect * 0.125f;
          else {
            ystart = font_aspect * 0.125f;
            yend = font_aspect * 0.875f;
          }
        }

        glScalef(4.0f / 3.0f, 4.0f / 3.0f, 1.0f);
        glTranslatef(-1.0f / 12.0f, -1.0f / 12.0f, 0.0f);
        glDisable(GL_TEXTURE_2D);
        glColor4f(0.0f, 0.0f, 0.0f, 0.25f);
        glBegin(GL_TRIANGLE_STRIP);
        glVertex2f(ystart, 0.0f);
        glVertex2f(yend, 0.0f);
        glVertex2f(ystart, 1.0f);
        glVertex2f(yend, 1.0f);
        glEnd();
        glEnable(GL_TEXTURE_2D);
        glTranslatef(1.0f / 12.0f, 1.0f / 12.0f, 0.0f);
        glScalef(0.75f, 0.75f, 1.0f);
      }

      glColor4fv(color.ptr);
      glBegin(GL_TRIANGLE_STRIP);
      glTexCoord2f(tx, ty);
      glVertex2f(0.0f, 0.0f);
      glTexCoord2f(tx + addx, ty);
      glVertex2f(font_aspect, 0.0f);
      glTexCoord2f(tx, ty + addy);
      glVertex2f(0.0f, 1.0f);
      glTexCoord2f(tx + addx, ty + addy);
      glVertex2f(font_aspect, 1.0f);
      glEnd();
      glTranslatef(font_aspect, 0.0f, 0.0f);
    }

    glPopMatrix();
  }

  vec2f getTextDims(string text)
  {
    const float font_aspect = 8.0f / 12.0f;

    return vec2f(cast(float) text.length * font_aspect, 1.0f);
  }
}
