// fxman [pengine]
//
// Copyright 2004-2006 Jasmine Langridge, jas@jareiko.net
// License: GPL version 2 (see included gpl.txt)
//
// Effects (render state descriptions) subsystem: .fx files and OBJ .mtl files.
module pengine.fxman;

import std.string : indexOf;

import bindings.gl;
import pengine.app : PApp;
import pengine.cutil;
import pengine.pvfs;
import pengine.subsys;
import pengine.texture;
import pengine.util;
import pengine.vmath;

enum CULLFACE_NONE = 0;
enum CULLFACE_CW = 1;
enum CULLFACE_CCW = 2;

enum BLEND_NONE = 0;
enum BLEND_ADD = 1;
enum BLEND_MULTIPLY = 2;
enum BLEND_ALPHA = 3;
enum BLEND_PREMULTALPHA = 4;

struct fx_alphatest_s
{
  GLenum func;
  float ref_ = 0;
}

struct fx_texunit_s
{
  int texindex = -1;
}

struct fx_renderstate_s
{
  bool depthtest;

  bool lighting;
  bool lightmodeltwoside;

  fx_alphatest_s alphatest;

  int cullface;

  int blendmode;

  fx_texunit_s[1] texunit;
}

struct fx_pass_s
{
  fx_renderstate_s rs;
}

struct fx_technique_s
{
  string name;

  fx_pass_s[] pass;

  bool validated;
  bool textures_ready;
}

struct fx_texture_s
{
  string name;

  string filename;

  GLenum type;

  // This is filled in just before rendering
  PTexture texobject;
}

__gshared fx_renderstate_s def_rs;
__gshared int max_tex_units;

final class PSSEffect : PSubsystem
{
  private PResourceList!PEffect fxlist;

  this(PApp parentApp)
  {
    super(parentApp);
    PUtil.outLog("Initialising effects subsystem");

    def_rs.depthtest = true;

    def_rs.lighting = true;
    def_rs.lightmodeltwoside = false;

    def_rs.alphatest.func = GL_ALWAYS;
    def_rs.alphatest.ref_ = 0.0f; // not important for GL_ALWAYS anyway

    def_rs.cullface = CULLFACE_CW;

    def_rs.blendmode = BLEND_NONE;

    def_rs.texunit[0].texindex = -1;

    glGetIntegerv(GL_MAX_TEXTURE_UNITS, max_tex_units);
  }

  override void shutdown()
  {
    PUtil.outLog("Shutting down effects subsystem");
    fxlist.clear();
  }

  PEffect loadEffect(string name)
  {
    PEffect fx = fxlist.find(name);
    if (fx is null) {
      try {
        fx = new PEffect(name);
      } catch (PException e) {
        if (PUtil.isDebugLevel(DEBUGLEVEL_ENDUSER))
          PUtil.outLog("Failed to load ", name, ": ", e.msg);
        return null;
      }
      fx.setFirstValidTechnique();
      fxlist.add(fx);
    }
    return fx;
  }
}

private class FxParseFailure : Exception
{
  this() { super("parse error"); }
}

final class PEffect : PResource
{
  // resources
  private fx_texture_s[] tex;

  // techniques
  private fx_technique_s[] tech;

  private int cur_tech;

  this(string filename)
  {
    cur_tech = -1;

    /* Let's check each effect type will load (FX or OBJ's MTL) */
    if (filename.indexOf(".fx") >= 0) {
      loadFX(filename);
    } else {
      loadMTL(filename);
    }
  }

  void unload()
  {
    tex = null;
    tech = null;
  }

  /// Load an OBJ's MTL file as the effect definition. It just creates a default
  /// effect using the material's textures, ignoring the rest.
  void loadMTL(string filename)
  {
    enum BUF_SIZE = 1024;
    string tok;
    string value;
    int numMaterials = 0;

    if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
      PUtil.outLog("Loading .mtl Material \"", filename, "\"");

    /* Unload previous loaded effect */
    unload();

    /* Let's read from file */
    PFile pfile = PVfs.openRead(filename);
    if (pfile is null)
      throw MakePException("PhysFS: " ~ PVfs.lastError);

    name = filename;

    string line;
    while ((line = PUtil.fgets2(pfile, BUF_SIZE)) !is null) {
      if (PUtil.getToken(line, tok, value)) {
        if (numMaterials > 1) {
          /* FIXME: ignoring all further materials. */
        } else if (tok == "newmtl") {
          numMaterials++;
        } else if (tok == "map_Kd") {
          /* Define the FX single texture */
          fx_texture_s curtex;
          curtex.texobject = null;
          curtex.name = value;
          curtex.type = GL_TEXTURE_2D;
          curtex.filename = PUtil.assemblePath(value, filename);
          tex ~= curtex;

          /* Define the default Technique */
          fx_technique_s curtech;
          curtech.name = "DefaultTechMTL";
          fx_pass_s curpass;
          curpass.rs = def_rs;
          curpass.rs.depthtest = true;
          curpass.rs.cullface = CULLFACE_CW;
          curpass.rs.texunit[0].texindex = 0;
          curtech.pass ~= curpass;
          tech ~= curtech;
        } else if (tok == "map_Ke") {
          /* Define the FX single texture */
          fx_texture_s curtex;
          curtex.texobject = null;
          curtex.name = value;
          curtex.type = GL_TEXTURE_2D;
          curtex.filename = PUtil.assemblePath(value, filename);
          tex ~= curtex;

          /* Define the emission Technique */
          fx_technique_s curtech;
          curtech.name = "EmissionTechMTL";
          fx_pass_s curpass;
          curpass.rs = def_rs;
          curpass.rs.depthtest = true;
          curpass.rs.cullface = CULLFACE_CW;
          curpass.rs.lighting = false;
          curpass.rs.blendmode = BLEND_ADD;
          curpass.rs.alphatest.func = GL_GREATER;
          curpass.rs.alphatest.ref_ = 0.5f;
          curpass.rs.texunit[0].texindex = 1;
          curtech.pass ~= curpass;
          tech ~= curtech;
        } else {
          /* Ignore everithing, as the FX will only use the texture. */
        }
      }
    }

    /* Done! */
    pfile.close();
  }

  void loadFX(string filename)
  {
    if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
      PUtil.outLog("Loading fx shader \"", filename, "\"");

    // unload eventual previous loaded effect
    unload();

    PFile pfile = PVfs.openRead(filename);
    if (pfile is null)
      throw MakePException("PhysFS: " ~ PVfs.lastError);

    name = filename;

    string source = cast(string) pfile.readAll().idup;
    pfile.close();

    size_t scan = 0;
    int linec = 1;
    string detail = "parse error";

    void fail() { throw new FxParseFailure(); }

    bool atEnd() { return scan >= source.length; }
    char cur() { return scan < source.length ? source[scan] : '\0'; }

    void skipWhite()
    {
      while (scan < source.length && (source[scan] == ' ' || source[scan] == '\t' ||
                                      source[scan] == '\n' || source[scan] == '\r')) {
        if (source[scan] == '\n') linec++;
        scan++;
      }
    }

    // reads a token (quoted string or identifier characters)
    string readToken()
    {
      string token;
      if (cur() == '"') {
        scan++;
        size_t s = scan;
        while (!atEnd() && cur() != '"') scan++;
        token = source[s .. scan];
        scan++;
      } else {
        size_t s = scan;
        while (!atEnd() && ((cur() >= 'a' && cur() <= 'z') || (cur() >= 'A' && cur() <= 'Z') ||
                            (cur() >= '0' && cur() <= '9') || cur() == '_')) scan++;
        token = source[s .. scan];
      }
      return token;
    }

    string readNumToken()
    {
      size_t s = scan;
      while (!atEnd() && ((cur() >= '0' && cur() <= '9') || cur() == '-' || cur() == '.')) scan++;
      return source[s .. scan];
    }

    // skip whitespace and fail at end of input
    void ws() { skipWhite(); if (atEnd()) fail(); }
    // read a token and fail if the input ended right after it
    string tokenF() { auto t = readToken(); if (atEnd()) fail(); return t; }
    void expect(char c) { ws(); if (cur() != c) fail(); scan++; }
    // "= value ;" helper pieces
    void eq() { expect('='); ws(); }
    void semi() { expect(';'); }

    try {
      while (true) {
        skipWhite();
        if (atEnd()) break;

        string token = tokenF();

        if (token == "texture") {
          fx_texture_s curtex;
          curtex.texobject = null;

          ws();
          curtex.name = tokenF();

          ws();
          if (cur() != '{') fail();
          scan++;

          while (true) {
            ws();
            if (cur() == '}') {
              scan++;
              break;
            }

            token = tokenF();

            // type = [ TEX_2D | TEX_3D | TEX_CUBE ];
            if (token == "type") {
              eq();
              token = tokenF();
              if (token == "TEX_2D")
                curtex.type = GL_TEXTURE_2D;
              else if (token == "TEX_3D")
                curtex.type = GL_TEXTURE_3D;
              else if (token == "TEX_CUBE")
                curtex.type = GL_TEXTURE_CUBE_MAP;
              else
                fail();
              semi();
            }
            // src = "blah.png";
            else if (token == "src") {
              eq();
              token = tokenF();
              curtex.filename = PUtil.assemblePath(token, filename);
              semi();
            } else
              fail();
          }
          tex ~= curtex;
        } else if (token == "technique") {
          fx_technique_s curtech;

          ws();
          curtech.name = tokenF();

          ws();
          if (cur() != '{') fail();
          scan++;

          while (true) {
            ws();
            if (cur() == '}') fail();

            token = tokenF();

            if (token == "pass") {
              fx_pass_s curpass;
              curpass.rs = def_rs;

              ws();
              if (cur() != '{') fail();
              scan++;

              while (true) {
                ws();
                if (cur() == '}') fail();

                token = tokenF();

                // depthtest = [ true | false ];
                if (token == "depthtest") {
                  eq();
                  token = tokenF();
                  if (token == "true")
                    curpass.rs.depthtest = true;
                  else if (token == "false")
                    curpass.rs.depthtest = false;
                  else
                    fail();
                  semi();
                }
                // alphatest = { FUNC, value };
                else if (token == "alphatest") {
                  eq();
                  if (cur() != '{') fail();
                  scan++;
                  ws();
                  token = tokenF();
                  if (token == "LESS")
                    curpass.rs.alphatest.func = GL_LESS;
                  else if (token == "EQUAL")
                    curpass.rs.alphatest.func = GL_EQUAL;
                  else if (token == "LEQUAL")
                    curpass.rs.alphatest.func = GL_LEQUAL;
                  else if (token == "GREATER")
                    curpass.rs.alphatest.func = GL_GREATER;
                  else if (token == "NOTEQUAL")
                    curpass.rs.alphatest.func = GL_NOTEQUAL;
                  else if (token == "GEQUAL")
                    curpass.rs.alphatest.func = GL_GEQUAL;
                  else if (token == "ALWAYS")
                    curpass.rs.alphatest.func = GL_ALWAYS;
                  else {
                    detail = "invalid alphatest func";
                    fail();
                  }
                  ws();
                  if (cur() != ',') fail();
                  scan++;
                  ws();
                  token = readNumToken();
                  if (atEnd()) fail();
                  curpass.rs.alphatest.ref_ = cast(float) atof(token);
                  ws();
                  if (cur() != '}') fail();
                  scan++;
                  semi();
                }
                // cullface
                else if (token == "cullface") {
                  eq();
                  token = tokenF();
                  if (token == "NONE")
                    curpass.rs.cullface = CULLFACE_NONE;
                  else if (token == "CW")
                    curpass.rs.cullface = CULLFACE_CW;
                  else if (token == "CCW")
                    curpass.rs.cullface = CULLFACE_CCW;
                  else {
                    detail = "invalid cullface mode";
                    fail();
                  }
                  semi();
                }
                // blendmode
                else if (token == "blendmode") {
                  eq();
                  token = tokenF();
                  if (token == "NONE")
                    curpass.rs.blendmode = BLEND_NONE;
                  else if (token == "ADD")
                    curpass.rs.blendmode = BLEND_ADD;
                  else if (token == "MULTIPLY")
                    curpass.rs.blendmode = BLEND_MULTIPLY;
                  else if (token == "ALPHA")
                    curpass.rs.blendmode = BLEND_ALPHA;
                  else if (token == "PREMULTALPHA")
                    curpass.rs.blendmode = BLEND_PREMULTALPHA;
                  else {
                    detail = "invalid blendmode mode";
                    fail();
                  }
                  semi();
                }
                // texunit0 = <texture>;
                else if (token == "texunit0") {
                  eq();
                  token = tokenF();
                  size_t iter;
                  for (iter = 0; iter < tex.length; iter++)
                    if (token == tex[iter].name)
                      break;
                  if (iter == tex.length) {
                    detail = "texture name " ~ token ~ " not found";
                    fail();
                  }
                  curpass.rs.texunit[0].texindex = cast(int) iter;
                  semi();
                } else if (token == "lighting") {
                  eq();
                  token = tokenF();
                  if (token == "true")
                    curpass.rs.lighting = true;
                  else if (token == "false")
                    curpass.rs.lighting = false;
                  else
                    fail();
                  semi();
                } else if (token == "lightmodeltwoside") {
                  eq();
                  token = tokenF();
                  if (token == "true")
                    curpass.rs.lightmodeltwoside = true;
                  else if (token == "false")
                    curpass.rs.lightmodeltwoside = false;
                  else
                    fail();
                  semi();
                } else {
                  detail = "invalid render state";
                  fail();
                }
              }
              // (unreachable: the loop above only exits through fail(), as in the original)
            } else
              fail();
          }
          // (unreachable for the same reason)
        } else
          fail();
      }
    } catch (FxParseFailure) {
      unload();
      throw MakePException(name ~ ": error at line " ~ PUtil.formatInt(linec) ~ " : " ~ detail);
    }
  }

  int getNumTechniques() { return cast(int) tech.length; }

  bool validateTechnique(int technique)
  {
    // todo: determine real validity
    if (technique >= 0 && technique < cast(int) tech.length) {
      tech[technique].validated = true;
      return tech[technique].validated;
    } else {
      return false;
    }
  }

  string getTechniqueName(int technique)
  {
    if (technique >= 0 && technique < cast(int) tech.length)
      return tech[technique].name;
    return "[invalid technique index]";
  }

  bool findTechnique(string techname, out int technique)
  {
    foreach (i, ref t; tech) {
      if (t.name == techname) {
        technique = cast(int) i;
        return true;
      }
    }
    return false;
  }

  bool setCurrentTechnique(int technique)
  {
    cur_tech = -1;
    if (technique >= 0 && technique < cast(int) tech.length) {
      if (tech[technique].validated || validateTechnique(technique)) {
        cur_tech = technique;
        return true;
      }
      return false;
    }
    return false;
  }

  int getCurrentTechnique() { return cur_tech; }

  bool setFirstValidTechnique()
  {
    for (int i = 0; i < getNumTechniques(); i++) {
      if (validateTechnique(i)) {
        setCurrentTechnique(i);
        return true;
      }
    }
    return false;
  }

  bool renderBegin(out int numPasses, PSSTexture sstex)
  {
    if (cur_tech == -1) return false;

    fx_technique_s* curtech = &tech[cur_tech];

    if (!curtech.textures_ready) {
      foreach (ref p; curtech.pass) {
        int texindex = p.rs.texunit[0].texindex;
        if (texindex != -1 && tex[texindex].texobject is null)
          tex[texindex].texobject = sstex.loadTexture(tex[texindex].filename);
      }
      curtech.textures_ready = true;
    }

    numPasses = cast(int) curtech.pass.length;

    return true;
  }

  // utility func to set GL state
  private void migrateRenderState(ref const fx_renderstate_s rs_old, ref const fx_renderstate_s rs_new)
  {
    if (rs_old.depthtest != rs_new.depthtest) {
      if (rs_new.depthtest) glEnable(GL_DEPTH_TEST);
      else glDisable(GL_DEPTH_TEST);
    }

    if (rs_old.lighting != rs_new.lighting) {
      if (rs_new.lighting) glEnable(GL_LIGHTING);
      else glDisable(GL_LIGHTING);
    }

    if (rs_old.lightmodeltwoside != rs_new.lightmodeltwoside) {
      glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, rs_new.lightmodeltwoside ? GL_TRUE : GL_FALSE);
    }

    if (rs_old.alphatest.func != rs_new.alphatest.func ||
        (rs_new.alphatest.func != GL_ALWAYS &&
         rs_old.alphatest.ref_ != rs_new.alphatest.ref_)) {
      if (rs_old.alphatest.func == GL_ALWAYS) {
        // enabling alpha test
        glEnable(GL_ALPHA_TEST);
        glAlphaFunc(rs_new.alphatest.func, rs_new.alphatest.ref_);
      } else if (rs_new.alphatest.func == GL_ALWAYS) {
        // disabling alpha test
        glDisable(GL_ALPHA_TEST);
      } else {
        // changing alpha test
        glAlphaFunc(rs_new.alphatest.func, rs_new.alphatest.ref_);
      }
    }

    if (rs_old.cullface != rs_new.cullface) {
      if (rs_old.cullface == CULLFACE_NONE) {
        glEnable(GL_CULL_FACE);
        glCullFace(rs_new.cullface == CULLFACE_CW ? GL_BACK : GL_FRONT);
      } else if (rs_new.cullface == CULLFACE_NONE) {
        glDisable(GL_CULL_FACE);
      } else {
        glCullFace(rs_new.cullface == CULLFACE_CW ? GL_BACK : GL_FRONT);
      }
    }

    if (rs_old.blendmode != rs_new.blendmode) {
      switch (rs_new.blendmode) {
        default:
          glBlendFunc(GL_ONE, GL_ZERO);
          break;
        case BLEND_ADD:
          glBlendFunc(GL_ONE, GL_ONE);
          break;
        case BLEND_MULTIPLY:
          glBlendFunc(GL_DST_COLOR, GL_SRC_COLOR);
          break;
        case BLEND_ALPHA:
          glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
          break;
        case BLEND_PREMULTALPHA:
          glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
          break;
      }
    }

    int texindex = rs_new.texunit[0].texindex;
    if (texindex != -1 && tex[texindex].texobject !is null)
      tex[texindex].texobject.bind();
    else
      PTexture.unbind();
  }

  void renderPass(int pass)
  {
    // assume pass is valid
    if (pass == 0)
      migrateRenderState(def_rs, tech[cur_tech].pass[0].rs);
    else
      migrateRenderState(tech[cur_tech].pass[pass - 1].rs, tech[cur_tech].pass[pass].rs);
  }

  void renderEnd()
  {
    migrateRenderState(tech[cur_tech].pass[$ - 1].rs, def_rs);
  }
}
