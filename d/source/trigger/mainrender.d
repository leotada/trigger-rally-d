// mainrender [trigger]
//
// Copyright (C) 2004-2006 Jasmine Langridge, ja-reiko@users.sourceforge.net
// Copyright (C) 2015 Andrei Bondor, ab396356@users.sourceforge.net
// License: GPL version 2 (see included gpl.txt)
//
// Rendering part of MainApp (render.cpp), written as free functions taking the app.
module trigger.mainrender;

import core.stdc.math : fmodf;
import std.format : format;
import std.math : abs, atan2, cos, exp, fabs, sin;
import std.conv : to;

import bindings.gl;
import pengine.config;
import pengine.render;
import pengine.terrain;
import pengine.texture;
import pengine.util;
import pengine.vmath;
import psim.damage;
import psim.vehicle;
import trigger.game;
import trigger.ghost;
import trigger.mainapp;
import trigger.menu;

void mainResize(MainApp app)
{
  glClearColor(1.0, 1.0, 1.0, 1.0);
  glEnable(GL_TEXTURE_2D);

  glEnable(GL_BLEND);
  glBlendFunc(GL_ONE, GL_ZERO);

  glDepthFunc(GL_LEQUAL);
  glEnable(GL_DEPTH_TEST);
  glClearDepth(1.0);

  glEnable(GL_CULL_FACE);

  glViewport(0, 0, app.getWidth(), app.getHeight());

  glEnable(GL_FOG);
  glFogi(GL_FOG_MODE, GL_EXP);

  glEnable(GL_LIGHT0);
  glEnable(GL_LIGHTING);

  const float[4] ambcol = [0.1f, 0.1f, 0.1f, 0.0f];
  glLightModelfv(GL_LIGHT_MODEL_AMBIENT, ambcol);

  float[4] white = [1.0f, 1.0f, 1.0f, 1.0f];
  glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, white);

  float[4] spec = [0.3f, 0.5f, 0.5f, 1.0f];
  glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, spec);
  glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, 6.0f);

  float[4] litcol = [0.6f, 0.6f, 0.6f, 0.0f];
  glLightfv(GL_LIGHT0, GL_DIFFUSE, litcol);
  glLightfv(GL_LIGHT0, GL_SPECULAR, litcol);

  glEnable(GL_NORMALIZE);
}

void drawBlades(float radius, float ang, float trace)
{
  float invtrace = 1.0 / trace;
  glPushMatrix();
  glScalef(radius, radius, 1.0);
  for (float ba = 0; ba < PI * 2.0 - 0.01; ba += PI / 2.0) {
    glBegin(GL_TRIANGLE_FAN);
    glColor4f(0.1, 0.1, 0.1, 0.24 * invtrace);
    glVertex2f(0.0, 0.0);
    glColor4f(0.1, 0.1, 0.1, 0.06 * invtrace);
    int num = cast(int)(trace / 0.1);
    if (num < 2) num = 2;
    float mult = trace / cast(float)(num - 1);
    float angadd = ba + ang;
    for (int i = 0; i < num; ++i) {
      float a = cast(float) i * mult + angadd;
      glVertex2f(cos(a), sin(a));
    }
    glEnd();
  }
  glPopMatrix();
}

void renderWater(MainApp app)
{
  with (app) {
    tex_water.bind();
    {
      float[4] tgens = [0.5f, 0, 0, 0];
      float[4] tgent = [0, 0.5f, 0, 0];
      glTexGeni(GL_S, GL_TEXTURE_GEN_MODE, GL_OBJECT_LINEAR);
      glTexGenfv(GL_S, GL_OBJECT_PLANE, tgens);
      glTexGeni(GL_T, GL_TEXTURE_GEN_MODE, GL_OBJECT_LINEAR);
      glTexGenfv(GL_T, GL_OBJECT_PLANE, tgent);
    }
    glEnable(GL_TEXTURE_GEN_S);
    glEnable(GL_TEXTURE_GEN_T);
    glPushMatrix();
    glScalef(20.0, 20.0, 1.0);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnable(GL_BLEND);
    {
      int minx = cast(int)(campos.x / 20.0) - 20,
          maxx = minx + 40,
          miny = cast(int)(campos.y / 20.0) - 20,
          maxy = miny + 40;
      for (int y = miny; y < maxy; ++y) {
        glBegin(GL_TRIANGLE_STRIP);
        for (int x = minx; x <= maxx; ++x) {
          float maxalpha = 0.5f;

          if (game.water.useralpha)
            maxalpha = game.water.alpha;

          if (game.water.fixedalpha) {
            glColor4f(1.0f, 1.0f, 1.0f, maxalpha);
            glVertex3f(x, y + 1, game.water.height);
            glVertex3f(x, y, game.water.height);
          } else {
            float ht, alpha;
            ht = game.terrain.getHeight((x) * 20.0, (y + 1) * 20.0);
            alpha = 1.0 - exp(ht - game.water.height);
            CLAMP(alpha, 0.0f, maxalpha);
            glColor4f(1.0, 1.0, 1.0, alpha);
            glVertex3f(x, y + 1, game.water.height);
            ht = game.terrain.getHeight((x) * 20.0, (y) * 20.0);
            alpha = 1.0 - exp(ht - game.water.height);
            CLAMP(alpha, 0.0f, maxalpha);
            glColor4f(1.0, 1.0, 1.0, alpha);
            glVertex3f(x, y, game.water.height);
          }
        }
        glEnd();
      }
    }
    glPopMatrix();
    glBlendFunc(GL_ONE, GL_ZERO);

    glDisable(GL_TEXTURE_GEN_S);
    glDisable(GL_TEXTURE_GEN_T);
  }
}

void renderSky(MainApp app, in mat44f cammat)
{
  enum CLRANGE = 10;
  enum CLFACTOR = 0.02;

  with (app) {
    glFogf(GL_FOG_DENSITY, game.weather.fog.density_sky);
    glDepthRange(0.999, 1.0);
    glDisable(GL_CULL_FACE);
    glPushMatrix(); // 1
    glLoadIdentity();
    glMultMatrixf(cammat);
    tex_sky[0].bind();
    glMatrixMode(GL_TEXTURE);
    glPushMatrix();
    glTranslatef(cloudscroll, 0.0, 0.0);
    glRotatef(30.0, 0.0, 0.0, 1.0);
    glScalef(0.4, 0.4, 1.0);
    for (int y = -CLRANGE; y < CLRANGE; y++) {
      glBegin(GL_TRIANGLE_STRIP);
      for (int x = -CLRANGE; x < CLRANGE + 1; x++) {
        glTexCoord2i(x, y);
        glVertex3f(x, y, 0.3 - (x * x + y * y) * CLFACTOR);
        glTexCoord2i(x, y + 1);
        glVertex3f(x, y + 1, 0.3 - (x * x + (y + 1) * (y + 1)) * CLFACTOR);
      }
      glEnd();
    }
    glPopMatrix();
    glMatrixMode(GL_MODELVIEW);
    glPopMatrix(); // 1
    glEnable(GL_CULL_FACE);
    glDepthRange(0.0, 0.999);
    glFogf(GL_FOG_DENSITY, game.weather.fog.density);
  }
}

void mainRender(MainApp app, float eyetranslation)
{
  switch (app.appstate) {
    case AS_LOAD_1:
      renderStateLoading(app, eyetranslation);
      break;

    case AS_LOAD_2:
    case AS_LOAD_3:
      break;

    case AS_LEVEL_SCREEN:
      renderStateLevel(app, eyetranslation);
      break;

    case AS_CHOOSE_VEHICLE:
      renderStateChoose(app, eyetranslation);
      break;

    case AS_IN_GAME:
      renderStateGame(app, eyetranslation);
      break;

    case AS_END_SCREEN:
      renderStateEnd(app, eyetranslation);
      break;

    default:
      break;
  }

  glFinish();
}

/// Draws the background image (square, cropped according to the aspect ratio).
private void drawBackgroundQuad(MainApp app)
{
  glBegin(GL_QUADS);
  if (cast(float) app.getWidth() / cast(float) app.getHeight() > 1.0f) {
    // lower and upper offset based on aspect ratio
    float off_l = (1 - (cast(float) app.getHeight() / cast(float) app.getWidth())) / 2.0f;
    float off_u = 1 - off_l;
    glTexCoord2f(1.0f, off_u); glVertex2f(1.0f, 1.0f);
    glTexCoord2f(0.0f, off_u); glVertex2f(-1.0f, 1.0f);
    glTexCoord2f(0.0f, off_l); glVertex2f(-1.0f, -1.0f);
    glTexCoord2f(1.0f, off_l); glVertex2f(1.0f, -1.0f);
  } else {
    float off_l = (1 - (cast(float) app.getWidth() / cast(float) app.getHeight())) / 2.0f;
    float off_u = 1 - off_l;
    glTexCoord2f(off_u, 1.0f); glVertex2f(1.0f, 1.0f);
    glTexCoord2f(off_l, 1.0f); glVertex2f(-1.0f, 1.0f);
    glTexCoord2f(off_l, 0.0f); glVertex2f(-1.0f, -1.0f);
    glTexCoord2f(off_u, 0.0f); glVertex2f(1.0f, -1.0f);
  }
  glEnd();
}

void renderStateLoading(MainApp app, float eyetranslation)
{
  glMatrixMode(GL_PROJECTION);
  glPushMatrix();
  glLoadIdentity();
  glOrtho(-1.0, 1.0, -1.0, 1.0, -1.0, 1.0);
  glMatrixMode(GL_MODELVIEW);

  app.tex_splash_screen.bind();

  glDisable(GL_DEPTH_TEST);
  glDisable(GL_FOG);
  glDisable(GL_LIGHTING);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  glColor4f(1.0f, 1.0f, 1.0f, 1.0f);

  drawBackgroundQuad(app);

  app.tex_loading_screen.bind();

  GLfloat logovratio = cast(float) app.getWidth() / app.getHeight();
  GLfloat logohratio = cast(float) app.getHeight() / app.getWidth();

  // FIXME: nasty, nasty code
  if (logovratio > 1.0f)
    logohratio = 1.0f;
  else if (logohratio > 1.0f)
    logovratio = 1.0f;

  const LOGO_VRATIO = logovratio / 3.5;
  const LOGO_HRATIO = logohratio / 3.5;
  glBegin(GL_QUADS);
  glTexCoord2f(1.0f, 1.0f); glVertex2f(LOGO_HRATIO, LOGO_VRATIO);
  glTexCoord2f(0.0f, 1.0f); glVertex2f(-LOGO_HRATIO, LOGO_VRATIO);
  glTexCoord2f(0.0f, 0.0f); glVertex2f(-LOGO_HRATIO, -LOGO_VRATIO);
  glTexCoord2f(1.0f, 0.0f); glVertex2f(LOGO_HRATIO, -LOGO_VRATIO);
  glEnd();

  glEnable(GL_DEPTH_TEST);
  glEnable(GL_FOG);
  glEnable(GL_LIGHTING);

  glMatrixMode(GL_PROJECTION);
  glPopMatrix();
  glMatrixMode(GL_MODELVIEW);
}

private immutable string[] creditstext = [
  "Trigger Rally " ~ PACKAGE_VERSION,
  "",
  "Copyright (C) 2004-2006",
  "Jasmine Langridge and Richard Langridge",
  "Posit Interactive",
  "",
  "Copyright (C) 2006-2016",
  "Various Contributors",
  "(see DATA_AUTHORS.txt)",
  "",
  "",
  "",
  "Coding",
  "Jasmine Langridge",
  "",
  "Art & SFX",
  "Richard Langridge",
  "",
  "",
  "",
  "Contributors",
  "",
  "Build system",
  "Matze Braune",
  "",
  "Stereo support",
  "Chuck Sites",
  "",
  "Mac OS X porting",
  "Tim Douglas",
  "",
  "Fixes & New Features",
  "LavaPunk",
  "Bernhard Kaindl",
  "Liviu Andronic",
  "Ishmael Turner",
  "Iwan 'qubodup' Gabovitch",
  "Farrer",
  "Andrei Bondor",
  "Nikolay Orlyuk",
  "Emanuele Sorce",
  "Martin Scherer",
  "Eugene MC",
  "Kirada",
  "",
  "New levels",
  "Tim Wintle",
  "David Pagnier",
  "Jared Buckner",
  "Andreas Rosdal",
  "Ivan",
  "Viktor Radnai",
  "Pierre-Alexis",
  "Bruno 'Fuddl' Kleinert",
  "Agnius Vasiliauskas",
  "Matthias Keysermann",
  "Marcio Bremm",
  "Onsemeliot",
  "",
  "Graphics",
  "Alex",
  "Roberto Diez Gonzalez",
  "",
  "",
  "",
  "",
  "",
  "Thanks to Jonathan C. Hatfull",
  "",
  "",
  "",
  "",
  "And thanks to Simon Brown too",
  "",
  "",
  "",
  "",
  "",
  "",
  "Thanks for playing Trigger"
];

void renderStateEnd(MainApp app, float eyetranslation)
{
  with (app) {
    glMatrixMode(GL_PROJECTION);
    glPushMatrix();
    glLoadIdentity();
    glOrtho(-1.0, 1.0, -1.0, 1.0, -1.0, 1.0);
    glMatrixMode(GL_MODELVIEW);

    tex_end_screen.bind();

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_FOG);
    glDisable(GL_LIGHTING);
    glBlendFunc(GL_ONE, GL_ZERO);

    glColor4f(1.0f, 1.0f, 1.0f, 1.0f);

    drawBackgroundQuad(app);

    tex_fontSourceCodeOutlined.bind();

    glMatrixMode(GL_PROJECTION);
    glPopMatrix();
    glPushMatrix();
    glLoadIdentity();
    glOrtho(0 - hratio, hratio, 0 - vratio, vratio, 0 - 1.0, 1.0);
    glMatrixMode(GL_MODELVIEW);

    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glPushMatrix();

    float scroll = splashtimeout;
    const float maxscroll = cast(float)(creditstext.length - 1) * 2.0f;
    RANGEADJUST(scroll, 0.0f, 0.9f, -10.0f, maxscroll);
    CLAMP_UPPER(scroll, maxscroll);

    glScalef(0.1f, 0.1f, 1.0f);

    glTranslatef(0.0f, scroll, 0.0f);

    for (int i = 0; i < cast(int) creditstext.length; i++) {
      float level = fabs(scroll + cast(float) i * -2.0f);
      RANGEADJUST(level, 0.0f, 9.0f, 3.0f, 0.0f);

      if (level > 0.0f) {
        CLAMP_UPPER(level, 1.0f);

        glPushMatrix();
        glTranslatef(0.0f, cast(float) i * -2.0f, 0.0f);

        float enlarge = 1.0f;

        if (splashtimeout > 0.9f) {
          float amt = (splashtimeout - 0.9f) * 10.0f;
          float amt2 = amt * amt;

          enlarge += amt2 / ((1.0001f - amt) * (1.0001f - amt));
          level -= amt2;
        }

        glScalef(enlarge, enlarge, 0.0f);
        glColor4f(1.0f, 1.0f, 1.0f, level);

        getSSRender().drawText(creditstext[i], PTEXT_HZA_CENTER | PTEXT_VTA_CENTER);
        glPopMatrix();
      }
    }

    glPopMatrix();

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_FOG);
    glEnable(GL_LIGHTING);

    glMatrixMode(GL_PROJECTION);
    glPopMatrix();
    glMatrixMode(GL_MODELVIEW);
  }
}

void renderStateLevel(MainApp app, float eyetranslation)
{
  with (app) {
    glMatrixMode(GL_PROJECTION);
    glPushMatrix();
    glLoadIdentity();

    const double margin = (800.0 - 600.0 * screenW() / screenH()) / 2.0;

    glOrtho(margin, 600.0 * screenW() / screenH() + margin, 0.0, 600.0, -1.0, 1.0);

    glPushMatrix();
    glLoadIdentity();
    glOrtho(-1.0, 1.0, -1.0, 1.0, -1.0, 1.0);

    glMatrixMode(GL_MODELVIEW);

    // draw background image
    glBlendFunc(GL_ONE, GL_ZERO);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_FOG);
    glDisable(GL_LIGHTING);

    tex_splash_screen.bind();

    glColor4f(1.0f, 1.0f, 1.0f, 1.0f); // use image's normal colors

    drawBackgroundQuad(app);

    glMatrixMode(GL_PROJECTION);
    glPopMatrix();

    glMatrixMode(GL_MODELVIEW);
    // draw GUI

    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glColor4f(1.0f, 1.0f, 1.0f, 0.2f);

    tex_fontSourceCodeOutlined.bind();

    glPushMatrix(); // 0

    gui.render();

    glPopMatrix(); // 0

    glBlendFunc(GL_ONE, GL_ZERO);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_FOG);
    glEnable(GL_LIGHTING);

    glMatrixMode(GL_PROJECTION);
    glPopMatrix();
    glMatrixMode(GL_MODELVIEW);
  }
}

private void drawLabel(MainApp app, float x, float y, float size, in vec4f col, string text, uint flags)
{
  glPushMatrix(); // 1
  glTranslatef(x, y, 0.0f);
  glScalef(size, size, 1.0f);
  glColor4f(col.x, col.y, col.z, col.w);
  app.getSSRender().drawText(text, flags);
  glPopMatrix(); // 1
}

/// Renders the car selection menu.
void renderStateChoose(MainApp app, float eyetranslation)
{
  with (app) {
    PVehicleType vtype = game.vehiclechoices[choose_type];

    glClearColor(0.0, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glMatrixMode(GL_PROJECTION);

    glPushMatrix();
    glLoadIdentity();
    glOrtho(-1.0, 1.0, -1.0, 1.0, -1.0, 1.0);

    glMatrixMode(GL_MODELVIEW);

    // draw background image
    glBlendFunc(GL_ONE, GL_ZERO);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_FOG);
    glDisable(GL_LIGHTING);

    tex_splash_screen.bind();

    glColor4f(1.0f, 1.0f, 1.0f, 1.0f);

    drawBackgroundQuad(app);

    glMatrixMode(GL_PROJECTION);
    glPopMatrix();

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();

    float fnear = 0.1f, fov = 0.6f;
    float aspect = cast(float) getWidth() / cast(float) getHeight();
    doStereoFrustum(-fnear * aspect * fov, fnear * aspect * fov, -fnear * fov, fnear * fov, fnear, 100000.0f,
                    0.8f, eyetranslation);
    glMatrixMode(GL_MODELVIEW);

    glPushMatrix(); // 0

    glTranslatef(-eyetranslation, 0.9f, -5.0f);
    glRotatef(28.0f, 1.0f, 0.0f, 0.0f);

    glDisable(GL_FOG);
    glEnable(GL_LIGHTING);
    glEnable(GL_DEPTH_TEST);

    vec4f lpos = vec4f(0.0f, 1.0f, 0.0f, 0.0f);
    glLightfv(GL_LIGHT0, GL_POSITION, lpos);

    float tmp = cast(float) cos(choose_spin * 2.0f) * 0.5f;
    tmp += choose_spin;
    glRotatef(90.0f, -1.0f, 0.0f, 0.0f);
    glRotatef(DEGREES(tmp), 0.0f, 0.0f, 1.0f);

    // render vehicle
    foreach (i; 0 .. vtype.part.length) {
      glPushMatrix(); // 1

      vec3f vpos = vtype.part[i].render_ref_local.getPosition();
      glTranslatef(vpos.x, vpos.y, vpos.z);

      mat44f vorim = vtype.part[i].render_ref_local.getInverseOrientationMatrix();
      glMultMatrixf(vorim);
      if (vtype.part[i].model !is null) {
        glPushMatrix(); // 2

        float scale = vtype.part[i].scale;
        glScalef(scale, scale, scale);
        doDrawModel(vtype.part[i].model, 1.0f);

        glPopMatrix(); // 2
      }

      // render wheels
      if (vtype.wheelmodel !is null) {
        foreach (j; 0 .. vtype.part[i].wheel.length) {

          glPushMatrix(); // 2

          vec3f wpos = vtype.part[i].wheel[j].pt;
          glTranslatef(wpos.x, wpos.y, wpos.z);

          float scale = vtype.wheelscale * vtype.part[i].wheel[j].radius;
          glScalef(scale, scale, scale);

          doDrawModel(vtype.wheelmodel, 1.0f);

          glPopMatrix(); // 2
        }
      }

      glPopMatrix(); // 1
    }

    glPopMatrix(); // 0

    glDisable(GL_LIGHTING);

    glMatrixMode(GL_PROJECTION);
    glPushMatrix();
    glLoadIdentity();
    glOrtho(-1.0, 1.0, -1.0, 1.0, -1.0, 1.0);
    glMatrixMode(GL_MODELVIEW);

    // use the same colors as the menu
    const gwc = gui.getColors();

    tex_fontSourceCodeShadowed.bind();

    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_LIGHTING);

    glPushMatrix(); // 0

    const double margin = (800.0 - 600.0 * screenW() / screenH()) / 2.0;

    glOrtho(margin, 600.0 * screenW() / screenH() + margin, 0.0, 600.0, -1.0, 1.0);

    drawLabel(app, 10.0f, 570.0f, 30.0f, gwc.weak, "Trigger Rally", PTEXT_HZA_LEFT | PTEXT_VTA_CENTER);
    drawLabel(app, 790.0f, 570.0f, 20.0f, gwc.weak,
              "car selection " ~ to!string(choose_type + 1) ~ '/' ~ to!string(game.vehiclechoices.length),
              PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER);

    static string cut(string s, size_t n) { return s.length > n ? s[0 .. n] : s; }

    drawLabel(app, 100.0f, 230.0f, 30.0f, gwc.header, cut(vtype.proper_name, 9), PTEXT_HZA_LEFT | PTEXT_VTA_CENTER);
    drawLabel(app, 100.0f, 200.0f, 20.0f, gwc.strong, cut(vtype.proper_class, 8), PTEXT_HZA_LEFT | PTEXT_VTA_CENTER);
    drawLabel(app, 500.0f, 230.0f, 20.0f, gwc.weak, "Weight (Kg)", PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER);
    drawLabel(app, 500.0f, 190.0f, 20.0f, gwc.weak, "Engine (BHP)", PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER);
    drawLabel(app, 500.0f, 150.0f, 20.0f, gwc.weak, "Wheel drive", PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER);
    drawLabel(app, 500.0f, 110.0f, 20.0f, gwc.weak, "Roadholding", PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER);
    drawLabel(app, 520.0f, 230.0f, 30.0f, gwc.strong, to!string(cast(int) vtype.mass), PTEXT_HZA_LEFT | PTEXT_VTA_CENTER);
    drawLabel(app, 520.0f, 190.0f, 30.0f, gwc.strong, vtype.pstat_enginepower, PTEXT_HZA_LEFT | PTEXT_VTA_CENTER);
    drawLabel(app, 520.0f, 150.0f, 30.0f, gwc.strong, vtype.pstat_wheeldrive, PTEXT_HZA_LEFT | PTEXT_VTA_CENTER);
    drawLabel(app, 520.0f, 110.0f, 30.0f, gwc.strong, vtype.pstat_roadholding, PTEXT_HZA_LEFT | PTEXT_VTA_CENTER);

    string racename;

    if (lss.state == AM_TOP_EVT_PREP || lss.state == AM_TOP_PRAC_SEL_PREP)
      racename = events[lss.currentevent].name ~ ": " ~ events[lss.currentevent].levels[lss.currentlevel].name;
    else if (lss.state == AM_TOP_LVL_PREP)
      racename = levels[lss.currentlevel].name;

    drawLabel(app, 400.0f, 30.0f, 20.0f, gwc.weak, racename, PTEXT_HZA_CENTER | PTEXT_VTA_CENTER);

    if (vtype.getLocked()) {
      const unlockevent = getVehicleUnlockEvent(vtype.getName());

      drawLabel(app, 400.0f, 425.0f, 40.0f, gwc.marked, "Locked", PTEXT_HZA_CENTER | PTEXT_VTA_CENTER);

      if (unlockevent != "") {
        drawLabel(app, 400.0f, 375.0f, 20.0f, gwc.marked, "Complete event " ~ unlockevent ~ " to unlock",
                  PTEXT_HZA_CENTER | PTEXT_VTA_CENTER);
      }
    }

    glPopMatrix(); // 0

    glBlendFunc(GL_ONE, GL_ZERO);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_FOG);
    glEnable(GL_LIGHTING);

    glMatrixMode(GL_PROJECTION);
    glPopMatrix();
    glMatrixMode(GL_MODELVIEW);
  }
}

private void drawUnitQuad()
{
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
}

void renderStateGame(MainApp app, float eyetranslation)
{
  with (app) {
    PVehicle vehic = game.vehicle[0];

    glClear(GL_DEPTH_BUFFER_BIT);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();

    float fnear = 0.1f, fov = 0.6f;
    float aspect = cast(float) getWidth() / cast(float) getHeight();
    doStereoFrustum(-fnear * aspect * fov, fnear * aspect * fov, -fnear * fov, fnear * fov, fnear, 100000.0f,
                    0.8f, eyetranslation);
    glMatrixMode(GL_MODELVIEW);

    glColor3f(1.0, 1.0, 1.0);

    vec4f fogcolor = vec4f(game.weather.fog.color, 1.0f);
    glFogfv(GL_FOG_COLOR, fogcolor);

    glDepthRange(0.0, 0.999);

    glPushMatrix(); // 0

    mat44f cammat = camori.getMatrix();
    mat44f cammat_inv = cammat.transpose();

    glTranslatef(-eyetranslation, 0.0f, 0.0f);

    glMultMatrixf(cammat);

    glTranslatef(-campos.x, -campos.y, -campos.z);

    float[4] lpos = [0.2f, 0.5f, 1.0f, 0.0f];
    glLightfv(GL_LIGHT0, GL_POSITION, lpos);

    glColor3ub(255, 255, 255);

    glDisable(GL_LIGHTING);

    glActiveTextureARB(GL_TEXTURE1_ARB);
    glEnable(GL_TEXTURE_2D);
    glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_COMBINE);
    glTexEnvi(GL_TEXTURE_ENV, GL_COMBINE_RGB, GL_ADD_SIGNED);
    glTexEnvi(GL_TEXTURE_ENV, GL_COMBINE_ALPHA, GL_MODULATE);
    tex_detail.bind();
    glTexGeni(GL_S, GL_TEXTURE_GEN_MODE, GL_OBJECT_LINEAR);
    glTexGeni(GL_T, GL_TEXTURE_GEN_MODE, GL_OBJECT_LINEAR);
    float[4] tgens = [0.05f, 0.0f, 0.0f, 0.0f];
    float[4] tgent = [0.0f, 0.05f, 0.0f, 0.0f];
    glTexGenfv(GL_S, GL_OBJECT_PLANE, tgens);
    glTexGenfv(GL_T, GL_OBJECT_PLANE, tgent);
    glEnable(GL_TEXTURE_GEN_S);
    glEnable(GL_TEXTURE_GEN_T);
    glActiveTextureARB(GL_TEXTURE0_ARB);

    // draw terrain
    game.terrain.render(campos, cammat_inv);

    glDisable(GL_TEXTURE_GEN_S);
    glDisable(GL_TEXTURE_GEN_T);

    glActiveTextureARB(GL_TEXTURE1_ARB);
    glDisable(GL_TEXTURE_2D);
    glActiveTextureARB(GL_TEXTURE0_ARB);

    if (renderowncar) {
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

      tex_shadow.bind();

      glColor4f(1.0f, 1.0f, 1.0f, 0.7f);

      vec3f vpos = game.vehicle[0].body_.getPosition();
      vec3f forw = makevec3f(game.vehicle[0].body_.getOrientationMatrix().row[0]);
      float forwangle = atan2(forw.y, forw.x);
      game.terrain.drawSplat(vpos.x, vpos.y, 1.4f, forwangle + PI * 0.5f);

      glBlendFunc(GL_ONE, GL_ZERO);
    }

    renderSky(app, cammat);

    glEnable(GL_LIGHTING);

    foreach (v; 0 .. game.vehicle.length) {
      if (!renderowncar && v == 0) continue;

      PVehicle veh = game.vehicle[v];
      foreach (i; 0 .. veh.part.length) {
        renderVehiclePart(app, veh.type, veh.part[i], veh.type.part[i], 1.0f);
      }
    }

    glDisable(GL_LIGHTING);

    PGhost.GhostData ghostdata;
    string vehiclename = "";

    if (cfg.getEnableGhost() && ghost.getReplayData(ghostdata, vehiclename)) {
      auto vehiclepart = new PVehiclePart();

      vehiclepart.ref_world.setPosition(ghostdata.pos);
      vehiclepart.ref_world.setOrientation(ghostdata.ori);
      vehiclepart.ref_world.updateMatrices();

      foreach (i; 0 .. ghostdata.wheel.length) {
        auto wheel = new PVehicleWheel();

        wheel.ref_world.setPosition(ghostdata.wheel[i].pos);
        wheel.ref_world.setOrientation(ghostdata.wheel[i].ori);
        wheel.ref_world.updateMatrices();
        vehiclepart.wheel ~= wheel;
      }

      // Theoretically there can be multiple vehicles with multiple parts.
      // However, the assumption is, that the model of the first part is relevant.
      foreach (choice; game.vehiclechoices) {
        if (choice.getName() == vehiclename) {
          renderVehiclePart(app, choice, vehiclepart, choice.part[0], 0.5f);
          break;
        }
      }
    }

    glDepthMask(GL_FALSE);
    glDisable(GL_CULL_FACE);

    glDisable(GL_TEXTURE_2D);

    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    enum RAINDROP_WIDTH = 0.015;
    const raindrop_col = vec4f(0.5f, 0.5f, 0.5f, 0.4f);

    vec3f offsetdrops = campos - campos_prev;

    foreach (ref r; rain) {
      vec3f tempv;
      const float prevlife = r.prevlife;
      vec3f pt1 = r.drop_pt + r.drop_vect * prevlife + offsetdrops;
      vec3f pt2 = r.drop_pt + r.drop_vect * r.life;
      vec3f zag = campos - r.drop_pt;
      zag = zag.cross(r.drop_vect);
      zag *= RAINDROP_WIDTH / zag.length();
      glBegin(GL_TRIANGLE_STRIP);
      glColor4f(raindrop_col.x, raindrop_col.y, raindrop_col.z, 0.0);
      tempv = pt1 - zag;
      glVertex3fv(tempv);
      tempv = pt2 - zag;
      glVertex3fv(tempv);

      glColor4fv(raindrop_col);
      glVertex3fv(pt1);
      glVertex3fv(pt2);

      glColor4f(raindrop_col.x, raindrop_col.y, raindrop_col.z, 0.0);
      tempv = pt1 + zag;
      glVertex3fv(tempv);
      tempv = pt2 + zag;
      glVertex3fv(tempv);
      glEnd();
    }

    enum SNOWFLAKE_POINT_SIZE = 3.0f;
    enum SNOWFLAKE_BOX_SIZE = 0.175f;

    // NOTE: must be greater than 1.0f
    enum SNOWFLAKE_MAXLIFE = 4.5f;

    GLfloat ops = 1.0f; // Original Point Size, for to be restored

    if (cfg.getSnowflaketype() == PConfig.SnowFlakeType.point) {
      glEnable(GL_VERTEX_PROGRAM_POINT_SIZE);
      glGetFloatv(GL_POINT_SIZE, ops);
      glPointSize(SNOWFLAKE_POINT_SIZE);
    } else if (cfg.getSnowflaketype() == PConfig.SnowFlakeType.textured) {
      glEnable(GL_TEXTURE_2D);
      glBlendFunc(GL_SRC_COLOR, GL_ONE);
      tex_snowflake.bind();
    }

    foreach (ref sf; snowfall) {
      const vec3f pt = sf.drop_pt + sf.drop_vect * sf.life;
      GLfloat alpha;

      if (sf.life > SNOWFLAKE_MAXLIFE) {
        alpha = 0.0f;
      } else if (sf.life > 1.0f) {
        enum ML = SNOWFLAKE_MAXLIFE;
        // this equation ensures that snowflaks fade in
        alpha = (sf.life - ML) / (1 - ML);
      } else
        alpha = 1.0f;

      if (cfg.getSnowflaketype() == PConfig.SnowFlakeType.point) {
        glBegin(GL_POINTS);
        glColor4f(1.0f, 1.0f, 1.0f, alpha);
        glVertex3fv(pt);
        glEnd();
      } else {
        enum SBS = SNOWFLAKE_BOX_SIZE;
        vec3f zag = campos - sf.drop_pt;

        zag = zag.cross(sf.drop_vect);
        zag.normalize();
        zag *= SBS;

        if (cfg.getSnowflaketype() == PConfig.SnowFlakeType.square) {
          glBegin(GL_TRIANGLE_STRIP);
          glColor4f(1.0f, 1.0f, 1.0f, alpha);
          glVertex3f(pt.x, pt.y, pt.z);
          glVertex3f(pt.x, pt.y, pt.z + zag.z + SBS);
          glVertex3f(pt.x + zag.x, pt.y + zag.y, pt.z);
          glVertex3f(pt.x + zag.x, pt.y + zag.y, pt.z + zag.z + SBS);
          glEnd();
        } else { // textured
          glBegin(GL_TRIANGLE_STRIP);
          glColor4f(1.0f, 1.0f, 1.0f, alpha);
          glTexCoord2f(1.0f, 1.0f);
          glVertex3f(pt.x, pt.y, pt.z);
          glTexCoord2f(0.0f, 1.0f);
          glVertex3f(pt.x, pt.y, pt.z + zag.z + SBS);
          glTexCoord2f(1.0f, 0.0f);
          glVertex3f(pt.x + zag.x, pt.y + zag.y, pt.z);
          glTexCoord2f(0.0f, 0.0f);
          glVertex3f(pt.x + zag.x, pt.y + zag.y, pt.z + zag.z + SBS);
          glEnd();
        }
      }
    }

    if (cfg.getSnowflaketype() == PConfig.SnowFlakeType.point)
      glPointSize(ops); // restore original point size

    // disable textures
    if (cfg.getSnowflaketype() == PConfig.SnowFlakeType.textured) {
      glDisable(GL_TEXTURE_2D);
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    }

    const vec4f[3] checkpoint_col = [
      vec4f(1.0f, 0.0f, 0.0f, 0.8f),  // 0 = next checkpoint
      vec4f(0.7f, 0.7f, 0.1f, 0.6f),  // 1 = checkpoint after next
      vec4f(0.2f, 0.8f, 0.2f, 0.4f)   // 2 = all other checkpoints
    ];

    if (showcheckpoint) {
      foreach (i; 0 .. game.checkpt.length) {
        vec4f colr = checkpoint_col[2];

        if (cast(int) i == vehic.nextcp)
          colr = checkpoint_col[0];
        else if (cast(int) i == (vehic.nextcp + 1) % cast(int) game.checkpt.length)
          colr = checkpoint_col[1];

        glPushMatrix(); // 1
        glTranslatef(game.checkpt[i].pt.x, game.checkpt[i].pt.y, game.checkpt[i].pt.z);
        glScalef(25.0f, 25.0f, 1.0f);

        // Regular checkpoint style
        glBegin(GL_TRIANGLE_STRIP);
        float ht = sin(cprotate * 6.0f) * 7.0f + 8.0f;
        glColor4f(colr.x, colr.y, colr.z, 0.0f);
        glVertex3f(1.0f, 0.0f, ht - 1.0f);
        glColor4f(colr.x, colr.y, colr.z, colr.w);
        glVertex3f(1.0f, 0.0f, ht + 0.0f);
        for (float a = PI / 10.0f; a < PI * 2.0f - 0.01f; a += PI / 10.0f) {
          glColor4f(colr.x, colr.y, colr.z, 0.0f);
          glVertex3f(cos(a), sin(a), ht - 1.0f);
          glColor4f(colr.x, colr.y, colr.z, colr.w);
          glVertex3f(cos(a), sin(a), ht + 0.0f);
        }
        glColor4f(colr.x, colr.y, colr.z, 0.0f);
        glVertex3f(1.0f, 0.0f, ht - 1.0f);
        glColor4f(colr.x, colr.y, colr.z, colr.w);
        glVertex3f(1.0f, 0.0f, ht + 0.0f);
        glEnd();

        glBegin(GL_TRIANGLE_STRIP);
        glColor4f(colr.x, colr.y, colr.z, colr.w);
        glVertex3f(1.0f, 0.0f, ht - 0.0f);
        glColor4f(colr.x, colr.y, colr.z, 0.0f);
        glVertex3f(1.0f, 0.0f, ht + 1.0f);
        for (float a = PI / 10.0f; a < PI * 2.0f - 0.01f; a += PI / 10.0f) {
          glColor4f(colr.x, colr.y, colr.z, colr.w);
          glVertex3f(cos(a), sin(a), ht - 0.0f);
          glColor4f(colr.x, colr.y, colr.z, 0.0f);
          glVertex3f(cos(a), sin(a), ht + 1.0f);
        }
        glColor4f(colr.x, colr.y, colr.z, colr.w);
        glVertex3f(1.0f, 0.0f, ht - 0.0f);
        glColor4f(colr.x, colr.y, colr.z, 0.0f);
        glVertex3f(1.0f, 0.0f, ht + 1.0f);
        glEnd();
        glPopMatrix(); // 1
      }
    }

    glEnable(GL_TEXTURE_2D);

    if (game.water.enabled)
      renderWater(app);

    if (psys_dirt !is null) // cfg_dirteffect == false
      getSSRender().render(psys_dirt);

    glDepthMask(GL_TRUE);
    glBlendFunc(GL_ONE, GL_ZERO);
    glEnable(GL_LIGHTING);
    glEnable(GL_CULL_FACE);
    glEnable(GL_FOG);

    glDisable(GL_LIGHTING);

    glPopMatrix(); // 0

    glDisable(GL_DEPTH_TEST);

    glMatrixMode(GL_PROJECTION);
    glPushMatrix(); // 0
    glLoadIdentity();

    glOrtho(0 - hratio, hratio, 0 - vratio, vratio, 0 - 1.0, 1.0);
    glMatrixMode(GL_MODELVIEW);

    glPushMatrix(); // 1

    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    if (showui) {
      game.renderCodriverSigns();

      glPushMatrix(); // 2
      // position of rpm dial and needle
      glTranslatef(hratio * (1.0f - (2.5f / 50.0f)) - 0.3f, -vratio * (43.5f / 50.0f) + 0.22f, 0.0f);
      glScalef(0.30f, 0.30f, 1.0f);

      tex_hud_revs.bind();
      glColor3f(1.0f, 1.0f, 1.0f);
      drawUnitQuad();

      // draw the needle of the RPM dial
      glRotatef(225.0f - vehic.getEngineRPM() * 15.0f / 1000.0f, 0.0f, 0.0f, 1.0f);
      tex_hud_revneedle.bind();
      glColor3f(1.0f, 1.0f, 1.0f);
      glPushMatrix(); // 3
      glTranslatef(0.62f, 0.0f, 0.0f);
      glScalef(0.16f, 0.16f, 0.16f);
      drawUnitQuad();
      glPopMatrix(); // 3
      glDisable(GL_TEXTURE_2D);
      glPopMatrix(); // 2
    }

    if (showmap) {
      // position and size of map
      glViewport(cast(int)(getWidth() * (2.5f / 100.0f)), cast(int)(getHeight() * (2.5f / 100.0f)),
                 cast(int)(getHeight() / 3.5f), cast(int)(getHeight() / 3.5f));

      glPushMatrix(); // 2
      glScalef(hratio, vratio, 1.0f);

      if (game.terrain.getHUDMapTexture() !is null) {
        glEnable(GL_TEXTURE_2D);
        game.terrain.getHUDMapTexture().bind();
      }

      glMatrixMode(GL_TEXTURE);
      glPushMatrix(); // 3
      float scalefac = 1.0f / game.terrain.getMapSize();
      glScalef(scalefac, scalefac, 1.0f);
      glTranslatef(campos.x, campos.y, 0.0f);
      glRotatef(DEGREES(camera_angle), 0.0f, 0.0f, 1.0f);
      glScalef(1.0f / 0.003f, 1.0f / 0.003f, 1.0f);

      glBegin(GL_QUADS);
      glColor4f(1.0f, 1.0f, 1.0f, 0.7f);
      glTexCoord2f(1.0f, 1.0f);
      glVertex2f(1.0f, 1.0f);
      glTexCoord2f(-1.0f, 1.0f);
      glVertex2f(-1.0f, 1.0f);
      glTexCoord2f(-1.0f, -1.0f);
      glVertex2f(-1.0f, -1.0f);
      glTexCoord2f(1.0f, -1.0f);
      glVertex2f(1.0f, -1.0f);
      glEnd();

      glPopMatrix(); // 3
      glMatrixMode(GL_MODELVIEW);

      glDisable(GL_TEXTURE_2D);

      glPushMatrix(); // 3
      glScalef(0.003f, 0.003f, 1.0f);
      glRotatef(DEGREES(-camera_angle), 0.0f, 0.0f, 1.0f);
      glTranslatef(-campos.x, -campos.y, 0.0f);
      foreach (i; 0 .. game.checkpt.length) {
        glPushMatrix(); // 4
        vec3f cpos = game.checkpt[i].pt;
        glTranslatef(cpos.x, cpos.y, 0.0f);
        glRotatef(DEGREES(camera_angle), 0.0f, 0.0f, 1.0f);
        glScalef(30.0f, 30.0f, 1.0f);
        vec4f colr = checkpoint_col[2];
        if (cast(int) i == vehic.nextcp) {
          float sc = 1.5f + sin(cprotate * 10.0f) * 0.5f;
          glScalef(sc, sc, 1.0f);
          colr = checkpoint_col[0];
        } else if (cast(int) i == (vehic.nextcp + 1) % cast(int) game.checkpt.length) {
          colr = checkpoint_col[1];
        }
        glBegin(GL_TRIANGLE_FAN);
        glColor4fv(colr);
        glVertex2f(0.0f, 0.0f);
        glColor4f(colr.x, colr.y, colr.z, 0.0f);
        glVertex2f(1.0f, 0.0f);
        glVertex2f(0.0f, 1.0f);
        glVertex2f(-1.0f, 0.0f);
        glVertex2f(0.0f, -1.0f);
        glVertex2f(1.0f, 0.0f);
        glEnd();
        glPopMatrix(); // 4
      }
      foreach (veh; game.vehicle) {
        glPushMatrix(); // 4
        vec3f vpos = veh.body_.getPosition();
        glTranslatef(vpos.x, vpos.y, 0.0f);
        glRotatef(DEGREES(camera_angle), 0.0f, 0.0f, 1.0f);
        glScalef(30.0f, 30.0f, 1.0f);
        glBegin(GL_TRIANGLE_FAN);
        glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
        glVertex2f(0.0f, 0.0f);
        glColor4f(1.0f, 1.0f, 1.0f, 0.0f);
        glVertex2f(1.0f, 0.0f);
        glVertex2f(0.0f, 1.0f);
        glVertex2f(-1.0f, 0.0f);
        glVertex2f(0.0f, -1.0f);
        glVertex2f(1.0f, 0.0f);
        glEnd();
        glPopMatrix(); // 4
      }
      glPopMatrix(); // 3

      glPopMatrix(); // 2

      glViewport(0, 0, getWidth(), getHeight());
    }

    glEnable(GL_TEXTURE_2D);

    if (showui) {
      // Work-around for the "TIME" label once penalty time is displayed
      float time_offset = 0.0f;

      tex_fontSourceCodeOutlined.bind();

      // time counter
      glPushMatrix(); // 2

      glTranslatef(-hratio + hratio * (2.5f / 50.0f), vratio - vratio * (5.5f / 50.0f), 0.0f);

      // time label
      glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
      glScalef(0.125f, 0.125f, 1.0f);
      if (game.gamestate == Gamestate.finished) {
        getSSRender().drawText(PUtil.formatTime(game.coursetime), PTEXT_HZA_LEFT | PTEXT_VTA_TOP);
      } else if (game.coursetime < game.cptime + 1.50f) {
        getSSRender().drawText(PUtil.formatTime(game.cptime), PTEXT_HZA_LEFT | PTEXT_VTA_TOP);
      } else if (game.coursetime < game.cptime + 3.50f) {
        float a = (((game.cptime + 3.50f) - game.coursetime) / 2);
        glColor4f(1.0f, 1.0f, 1.0f, a);
        getSSRender().drawText(PUtil.formatTime(game.cptime), PTEXT_HZA_LEFT | PTEXT_VTA_TOP);
      } else {
        getSSRender().drawText(PUtil.formatTime(game.coursetime), PTEXT_HZA_LEFT | PTEXT_VTA_TOP);
      }

      // show target time
      glColor4f(0.5f, 1.0f, 0.5f, 1.0f);
      glTranslatef(0.0f, -0.8f, 0.0f);
      getSSRender().drawText(PUtil.formatTime(game.targettime), PTEXT_HZA_LEFT | PTEXT_VTA_TOP);

      {
        // show the time penalty if there is any
        const float timepen = game.uservehicle.offroadtime_total * game.offroadtime_penalty_multiplier;

        if (timepen >= 0.1f) {
          glColor4f(1.0f, 1.0f, 0.5f, 1.0f);
          glTranslatef(0.0f, -0.8f, 0.0f);
          getSSRender().drawText(PUtil.formatTime(timepen) ~ '+', PTEXT_HZA_LEFT | PTEXT_VTA_TOP);
          time_offset = 0.8;
        }
      }

      glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
      glTranslatef(0.0f, 1.32f + time_offset, 0.0f);
      glScalef(0.65f, 0.65f, 1.0f);
      getSSRender().drawText("TIME", PTEXT_HZA_LEFT | PTEXT_VTA_TOP);

      glPopMatrix(); // 2

      // show Next/Total checkpoints
      {
        glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
        glPushMatrix(); // 2
        const totalcp = to!string(game.checkpt.length);
        const nextcp = to!string(vehic.nextcp);

        glTranslatef(hratio - hratio * (2.5f / 50.0f), vratio - vratio * (5.5f / 50.0f), 0.0f);
        glScalef(0.125f, 0.125f, 1.0f);

        if (game.getFinishState() != Gamefinish.not_finished)
          getSSRender().drawText(totalcp ~ '/' ~ totalcp, PTEXT_HZA_RIGHT | PTEXT_VTA_TOP);
        else
          getSSRender().drawText(nextcp ~ '/' ~ totalcp, PTEXT_HZA_RIGHT | PTEXT_VTA_TOP);

        // checkpoint label
        glTranslatef(0.0f, 0.52f, 0.0f);
        glScalef(0.65f, 0.65f, 1.0f);
        getSSRender().drawText("CKPT", PTEXT_HZA_RIGHT | PTEXT_VTA_TOP);

        glPopMatrix(); // 2
      }

      // show Current/Total laps
      if (game.number_of_laps > 1) {
        const currentlap = to!string(vehic.currentlap);
        const number_of_laps = to!string(game.number_of_laps);

        glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
        glPushMatrix(); // 2
        glTranslatef(hratio - hratio * (2.5f / 50.0f), vratio - vratio * (5.5f / 50.0f) - 0.20f, 0.0f);
        glScalef(0.125f, 0.125f, 1.0f);

        if (game.getFinishState() != Gamefinish.not_finished)
          getSSRender().drawText(number_of_laps ~ '/' ~ number_of_laps, PTEXT_HZA_RIGHT | PTEXT_VTA_TOP);
        else
          getSSRender().drawText(currentlap ~ '/' ~ number_of_laps, PTEXT_HZA_RIGHT | PTEXT_VTA_TOP);

        glTranslatef(0.0f, 0.52f, 0.0f);
        glScalef(0.65f, 0.65f, 1.0f);
        getSSRender().drawText("LAP", PTEXT_HZA_RIGHT | PTEXT_VTA_TOP);

        glPopMatrix(); // 2
      }

      if (cfg.getEnableFps()) {
        glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
        glPushMatrix(); // 2
        glTranslatef(0.0f, vratio - vratio * (5.5f / 50.0f), 0.0f);
        glScalef(0.125f, 0.125f, 1.0f);
        getSSRender().drawText(format("%.1f", fps), PTEXT_HZA_CENTER | PTEXT_VTA_TOP);

        glTranslatef(0.0f, 0.52f, 0.0f);
        glScalef(0.65f, 0.65f, 1.0f);
        getSSRender().drawText("FPS", PTEXT_HZA_CENTER | PTEXT_VTA_TOP);
        glPopMatrix(); // 2
      }

      glColor4f(1.0f, 1.0f, 1.0f, 1.0f);

      tex_fontSourceCodeBold.bind();

      // show current gear and speed
      {
        // gear number
        const int gear = vehic.getCurrentGear();
        const string buff = (gear >= 0) ? PUtil.formatInt(gear + 1, 1) : "R";

        glPushMatrix(); // 2
        // If we have automatic transmission, draw gear in blue
        if (cfg.getAutomaticTransmission())
          glColor4f(0.3f, 0.6f, 1.0f, 1.0f);
        glTranslatef(hratio * (1.0f - (2.5f / 50.0f)) - 0.3f, -vratio * (43.5f / 50.0f) + 0.21f, 0.0f);
        glScalef(0.20f, 0.20f, 1.0f);
        getSSRender().drawText(buff, PTEXT_HZA_CENTER | PTEXT_VTA_CENTER);
        // Restore color
        if (cfg.getAutomaticTransmission())
          glColor4f(1.0f, 1.0f, 1.0f, 1.0f);

        // speed number
        const int speed = cast(int)(fabs(vehic.getWheelSpeed()) * cfg.getHudSpeedoMpsSpeedMult());
        string speedstr = to!string(speed);

        glTranslatef(1.1f, -0.625f, 0.0f);
        glScalef(0.5f, 0.5f, 1.0f);
        getSSRender().drawText(speedstr, PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER);

        // speed label
        glTranslatef(0.0f, -0.82f, 0.0f);
        glScalef(0.5f, 0.5f, 1.0f);

        if (cfg.getSpeedUnit() == PConfig.Speedunit.mph)
          getSSRender().drawText("MPH", PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER);
        else
          getSSRender().drawText("km/h", PTEXT_HZA_RIGHT | PTEXT_VTA_CENTER);

        glPopMatrix(); // 2
      }

      renderDamageIndicatorGroup(app);
    }

    tex_fontSourceCodeShadowed.bind();

    // draw "off road" warning sign and text
    if (game.isRacing()) {
      const vec3f bodypos = vehic.body_.getPosition();

      if (!game.terrain.getRmapOnRoad(bodypos)) {
        glPushMatrix(); // 2
        glLoadIdentity();
        glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
        glScalef(0.25f, 0.25f, 1.0f);
        tex_hud_offroad.bind();
        drawUnitQuad();
        glPopMatrix(); // 2
        glPushMatrix(); // 2
        glScalef(0.1f, 0.1f, 1.0f);
        glTranslatef(0.0f, -2.5f, 0.0f);
        glColor4f(1.0f, 1.0f, 0.0f, 1.0f);
        tex_fontSourceCodeOutlined.bind();
        getSSRender().drawText(
          to!string(cast(int)(game.getOffroadTime() * game.offroadtime_penalty_multiplier)) ~ " seconds",
          PTEXT_HZA_CENTER | PTEXT_VTA_TOP);
        glPopMatrix(); // 2
      }
    }

    {
      tex_fontSourceCodeOutlined.bind();

      glColor4f(1.0f, 0.0f, 0.0f, 1.0f);
      glPushMatrix(); // 2
      glTranslatef(0.0f, 0.2f, 0.0f);
      glScalef(0.6f, 0.6f, 1.0f);
      if (game.gamestate == Gamestate.countdown) {
        float sizer = fmodf(game.othertime, 1.0f) + 0.5f;
        glScalef(sizer, sizer, 1.0f);
        getSSRender().drawText(PUtil.formatInt(cast(int) game.othertime + 1, 1), PTEXT_HZA_CENTER | PTEXT_VTA_CENTER);
      } else if (game.gamestate == Gamestate.finished) {
        if (game.getFinishState() == Gamefinish.pass) {
          glColor4f(0.5f, 1.0f, 0.5f, 1.0f);
          getSSRender().drawText("WIN", PTEXT_HZA_CENTER | PTEXT_VTA_CENTER);
        } else {
          glScalef(0.5f, 0.5f, 1.0f);
          glColor4f(0.5f, 0.0f, 0.0f, 1.0f);
          getSSRender().drawText("TIME EXCEEDED", PTEXT_HZA_CENTER | PTEXT_VTA_CENTER);
        }
      } else if (game.coursetime < 1.0f) {
        glColor4f(0.5f, 1.0f, 0.5f, 1.0f);
        getSSRender().drawText("GO!", PTEXT_HZA_CENTER | PTEXT_VTA_CENTER);
      } else if (game.coursetime < 2.0f) {
        float a = 1.0f - (game.coursetime - 1.0f);
        glColor4f(0.5f, 1.0f, 0.5f, a);
        getSSRender().drawText("GO!", PTEXT_HZA_CENTER | PTEXT_VTA_CENTER);
      }
      glPopMatrix(); // 2

      if (game.gamestate == Gamestate.countdown) {
        glPushMatrix(); // 2
        glTranslatef(0.0f, 0.6f, 0.0f);
        glScalef(0.08f, 0.08f, 1.0f);
        if (game.othertime < 1.0f) {
          glColor4f(1.0f, 1.0f, 1.0f, game.othertime);
          getSSRender().drawText(game.comment, PTEXT_HZA_CENTER | PTEXT_VTA_CENTER);
        } else {
          glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
          getSSRender().drawText(game.comment, PTEXT_HZA_CENTER | PTEXT_VTA_CENTER);
        }
        glPopMatrix(); // 2
      }

      if (pauserace) {
        glPushMatrix(); // 2
        glColor4f(0.25f, 0.25f, 1.0f, 1.0f);
        glScalef(0.25f, 0.25f, 1.0f);
        getSSRender().drawText("PAUSED", PTEXT_HZA_CENTER | PTEXT_VTA_CENTER);
        glPopMatrix(); // 2
      }
    }

    glPopMatrix(); // 1

    glMatrixMode(GL_PROJECTION);
    glPopMatrix(); // 0
    glMatrixMode(GL_MODELVIEW);

    glBlendFunc(GL_ONE, GL_ZERO);

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_LIGHTING);
  }
}

void renderDamageIndicator(MainApp app, PTexture texture, float posx, float posy, float scalex, float scaley, float damage)
{
  float red = 0.0f;
  float green = 0.0f;
  float blue = 0.0f;

  if (damage > 1.0f)
    damage = 1.0f;

  if (damage < 0.0f) {
    red = 1.0;
    green = 1.0;
    blue = 1.0;
  } else if (damage < 0.5f) {
    red = 2.0f * damage;
    green = 1.0;
  } else {
    red = 1.0;
    green = 2.0 * (1.0 - damage);
  }

  glPushMatrix(); // 2

  glTranslatef(posx, posy, 0.0f);
  glScalef(scalex, scaley, 1.0f);
  texture.bind();
  glColor4f(red, green, blue, 0.5f);

  drawUnitQuad();

  glPopMatrix(); // 2
}

void renderDamageIndicatorGroup(MainApp app)
{
  with (app) {
    // Theoretically there can be multiple vehicles with multiple parts.
    // However, the assumption is, that the damage of the first part of the first vehicle is relevant.
    PVehiclePart part = game.vehicle[0].part[0];

    renderDamageIndicator(app,
      tex_damage_front_left, hratio * 45.0f / 50.0f - 0.075f, -vratio * 32.5f / 50.0f + 0.032f, 0.025f, 0.032f,
      part.damage.getDamage(PDamage.DamageSide.DamageFrontLeft));
    renderDamageIndicator(app,
      tex_damage_front_right, hratio * 45.0f / 50.0f - 0.025f, -vratio * 32.5f / 50.0f + 0.032f, 0.025f, 0.032f,
      part.damage.getDamage(PDamage.DamageSide.DamageFrontRight));
    renderDamageIndicator(app,
      tex_damage_rear_left, hratio * 45.0f / 50.0f - 0.075f, -vratio * 32.5f / 50.0f - 0.032f, 0.025f, 0.032f,
      part.damage.getDamage(PDamage.DamageSide.DamageRearLeft));
    renderDamageIndicator(app,
      tex_damage_rear_right, hratio * 45.0f / 50.0f - 0.025f, -vratio * 32.5f / 50.0f - 0.032f, 0.025f, 0.032f,
      part.damage.getDamage(PDamage.DamageSide.DamageRearRight));
  }
}

void renderVehiclePart(MainApp app, PVehicleType type, PVehiclePart part, PVehicleTypePart typepart, float alpha)
{
  if (typepart.model !is null) {
    glPushMatrix();

    vec3f vpos = part.ref_world.getPosition();
    glTranslatef(vpos.x, vpos.y, vpos.z);

    mat44f vorim = part.ref_world.getInverseOrientationMatrix();
    glMultMatrixf(vorim);

    float scale = typepart.scale;
    glScalef(scale, scale, scale);

    app.doDrawModel(typepart.model, alpha);

    glPopMatrix();
  }

  if (type.wheelmodel !is null) {
    foreach (i; 0 .. typepart.wheel.length) {
      glPushMatrix();

      vec3f wpos = part.wheel[i].ref_world.getPosition();
      glTranslatef(wpos.x, wpos.y, wpos.z);

      mat44f worim = part.wheel[i].ref_world.getInverseOrientationMatrix();
      glMultMatrixf(worim);

      float scale = type.wheelscale * typepart.wheel[i].radius;
      glScalef(scale, scale, scale);

      app.doDrawModel(type.wheelmodel, alpha);

      glPopMatrix();
    }
  }
}
