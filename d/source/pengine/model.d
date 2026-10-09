// model [pengine]
//
// Copyright 2004-2006 Jasmine Langridge, jas@jareiko.net
// License: GPL version 2 (see included gpl.txt)
//
// Model subsystem and the OBJ / ASE model loaders.
module pengine.model;

import std.algorithm : canFind;
import std.string : indexOf, strip;
import std.typecons : Tuple, tuple;

import pengine.app : PApp;
import pengine.cutil;
import pengine.fxman : PEffect;
import pengine.pvfs;
import pengine.subsys;
import pengine.util;
import pengine.vmath;

final class PSSModel : PSubsystem
{
  private PResourceList!PModel modlist;

  this(PApp parentApp)
  {
    super(parentApp);
    PUtil.outLog("Initialising model subsystem");
  }

  override void shutdown()
  {
    PUtil.outLog("Shutting down model subsystem");
    modlist.clear();
  }

  PModel loadModel(string name)
  {
    PModel mdl = modlist.find(name);
    if (mdl is null) {
      try {
        mdl = new PModel(name);
      } catch (PException e) {
        if (PUtil.isDebugLevel(DEBUGLEVEL_ENDUSER))
          PUtil.outLog("Failed to load ", name, ": ", e.msg);
        return null;
      }
      modlist.add(mdl);
    }
    return mdl;
  }
}

struct PFace
{
  vec3f facenormal;
  uint32[3] vt;
  uint32[3] tc;
  uint32[3] nr;
}

final class PMesh
{
  vec3f[] vert;
  vec2f[] texco;
  vec3f[] norm;
  PFace[] face;

  string fxname;
  PEffect effect;
}

/// Splits a line into whitespace separated tokens; a token starting with `"` extends to the closing quote.
private string[] strtok2(string input)
{
  string[] toks;
  size_t i = 0;
  const n = input.length;
  static bool ws(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }

  while (true) {
    while (i < n && ws(input[i])) i++;
    if (i >= n) break;
    if (input[i] == '"') {
      i++;
      size_t s = i;
      while (i < n && input[i] != '"') i++;
      toks ~= input[s .. i];
      if (i < n) i++;
    } else {
      size_t s = i;
      while (i < n && !ws(input[i])) i++;
      toks ~= input[s .. i];
    }
  }
  return toks;
}

final class PModel : PResource
{
  PMesh[] mesh;

  this(string filename, float globalScale = 1.0f)
  {
    /* Let's check each model type will load (ASE or OBJ) */
    if (filename.indexOf(".ase") >= 0) {
      loadASE(filename, globalScale);
    } else {
      loadOBJ(filename, globalScale);
    }
  }

  Tuple!(vec3f, vec3f) getExtents() const
  {
    vec3f v_min = vec3f(1000000000.0, 1000000000.0, 1000000000.0),
          v_max = vec3f(-1000000000.0, -1000000000.0, -1000000000.0);

    foreach (m; mesh) {
      foreach (v; m.vert) {
        if (v_min.x > v.x)
          v_min.x = v.x;
        else if (v_max.x < v.x)
          v_max.x = v.x;
        if (v_min.y > v.y)
          v_min.y = v.y;
        else if (v_max.y < v.y)
          v_max.y = v.y;
        if (v_min.z > v.z)
          v_min.z = v.z;
        else if (v_max.z < v.z)
          v_max.z = v.z;
      }
    }

    return tuple(v_min, v_max);
  }

  /// Load an .obj model from file to the pengine structures.
  /// All model faces must be triangles; the model must have only a single material.
  private void loadOBJ(string filename, float globalScale)
  {
    enum OBJ_BUFFER_SIZE = 65552;

    string tok;
    string value;
    uint curFace = uint.max;
    int objNumber = 0;

    if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
      PUtil.outLog("Loading OBJ model \"", filename, "\"");

    PFile pfile = PVfs.openRead(filename);
    if (pfile is null)
      throw MakePException(filename ~ ", PhysFS: " ~ PVfs.lastError);

    /* Create the single mesh (.obj isn't a multimesh file) */
    PMesh curMesh = new PMesh();
    mesh ~= curMesh;

    string line;
    while ((line = PUtil.fgets2(pfile, OBJ_BUFFER_SIZE)) !is null) {
      if (PUtil.getToken(line, tok, value)) {
        if (tok == "f") {
          /* Face (triangle) declaration */
          int[3] v, uv, vn;

          curFace++;

          curMesh.face.length = curFace + 1;
          if (sscanf(value, "%d/%d/%d %d/%d/%d %d/%d/%d",
                     &v[0], &uv[0], &vn[0],
                     &v[1], &uv[1], &vn[1],
                     &v[2], &uv[2], &vn[2]) == 9) {
            /* NOTE: all index are dec by 1, as .obj range is
             * [1,total] and pengine vector is [0,total) */
            foreach (k; 0 .. 3) {
              curMesh.face[curFace].vt[k] = v[k] - 1;
              curMesh.face[curFace].tc[k] = uv[k] - 1;
              curMesh.face[curFace].nr[k] = vn[k] - 1;
            }
          }
        } else if (tok == "vt") {
          /* Vertex st texture coordinate */
          vec2f v2;
          if (sscanf(value, "%f %f", &v2.x, &v2.y) == 2)
            curMesh.texco ~= v2;
        } else if (tok == "v") {
          /* Vertex declaration */
          vec3f v3;
          if (sscanf(value, "%f %f %f", &v3.x, &v3.y, &v3.z) == 3)
            curMesh.vert ~= v3 * globalScale;
        } else if (tok == "vn") {
          /* Vertex Normal declaraction */
          vec3f v3;
          if (sscanf(value, "%f %f %f", &v3.x, &v3.y, &v3.z) == 3) {
            v3.normalize();
            curMesh.norm ~= v3;
          }
        } else if (tok == "mtllib") {
          /* Material Library declaration (mtllib) */
          curMesh.fxname = PUtil.assemblePath(value, filename);
        } else if (tok == "o") {
          /* Object name. Just ignore. */
          objNumber++;
          if (objNumber > 1) {
            PUtil.outLog("Warning: Object file \"", filename, "\" has more than one object defined!");
          }
        } else if (tok.length && tok[0] == '#') {
          /* Comment. Just ignore. */
        } else if (tok == "usemtl") {
          /* Face material usage. Ignored: the pengine renderer uses a single "fx" per mesh. */
        } else if (tok == "s") {
          /* Smooth toggle. Ignoring. */
        } else {
          PUtil.outLog("Warning: unknown token \"", tok, "\" in file \"", filename, "\"");
        }
      }
    }

    /* Verify if normals were defined */
    if (curMesh.norm.length == 0) {
      PUtil.outLog("Warning: Object file \"", filename, "\" had no normals defined!");
    }

    /* Finally, close file and done. */
    pfile.close();
    name = filename;
  }

  private void loadASE(string filename, float globalScale)
  {
    if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
      PUtil.outLog("Loading ASE model \"", filename, "\"");

    PFile pfile = PVfs.openRead(filename);
    if (pfile is null)
      throw MakePException(filename ~ ", PhysFS: " ~ PVfs.lastError);

    string[] matlist; // material file names

    int unknowndepth = 0;

    enum Step { eof, skip, process }

    // reads the next line, tokenizes it and applies the "unknown block" skipping logic
    Step step(out string buff, out string[] tok)
    {
      buff = PUtil.fgets2(pfile, 1000);
      if (buff is null) return Step.eof;
      tok = strtok2(buff);
      if (tok.length == 0) return Step.skip;
      if (unknowndepth > 0) {
        if (tok[0] == "}")
          unknowndepth--;
        return Step.skip;
      }
      return Step.process;
    }

    string buff;
    string[] tok;
    while (true) {
      auto st = step(buff, tok);
      if (st == Step.eof) break;
      if (st == Step.skip) continue;

      if (tok.length == 2 && tok[1] == "{") {
        if (tok[0] == "*MATERIAL_LIST") {
          while (true) {
            st = step(buff, tok);
            if (st == Step.eof) break;
            if (st == Step.skip) continue;
            if (tok[0] == "}") break;
            uint matind;
            char[1000] buff3;
            if (sscanf(buff, " *MATERIAL %u \"%[^\"]\"", &matind, buff3.ptr) == 2) {
              if (matind >= matlist.length) matlist.length = matind + 1;
              import std.string : fromStringz;
              matlist[matind] = PUtil.assemblePath(fromStringz(buff3.ptr).idup, filename);
            }
          }
        } else if (tok[0] == "*GEOMOBJECT") {
          vec3f[4] tm;
          int tempi;
          PMesh curmesh = null;
          tm[0] = vec3f(1, 0, 0);
          tm[1] = vec3f(0, 1, 0);
          tm[2] = vec3f(0, 0, 1);
          tm[3] = vec3f.zero();
          vec3f DO_TM2(vec3f v) { return vec3f(v * tm[0], v * tm[1], v * tm[2]); }

          while (true) {
            st = step(buff, tok);
            if (st == Step.eof) break;
            if (st == Step.skip) continue;
            if (tok[0] == "}") break;
            if (tok.length == 2 && tok[1] == "{") {
              if (tok[0] == "*MESH") {
                curmesh = new PMesh();
                mesh ~= curmesh;
                curmesh.effect = null;
                while (true) {
                  st = step(buff, tok);
                  if (st == Step.eof) break;
                  if (st == Step.skip) continue;
                  if (tok[0] == "}") break;
                  if (tok.length == 2 && tok[1] == "{") {
                    if (tok[0] == "*MESH_VERTEX_LIST") {
                      uint vnum;
                      vec3f vpos;
                      while (true) {
                        st = step(buff, tok);
                        if (st == Step.eof) break;
                        if (st == Step.skip) continue;
                        if (tok[0] == "}") break;
                        if (sscanf(buff, " *MESH_VERTEX %u %f %f %f", &vnum, &vpos.x, &vpos.y, &vpos.z) == 4) {
                          if (vnum < curmesh.vert.length)
                            curmesh.vert[vnum] = vpos * globalScale;
                        }
                      }
                    } else if (tok[0] == "*MESH_TVERTLIST") {
                      uint vnum;
                      vec2f vco;
                      while (true) {
                        st = step(buff, tok);
                        if (st == Step.eof) break;
                        if (st == Step.skip) continue;
                        if (tok[0] == "}") break;
                        if (sscanf(buff, " *MESH_TVERT %u %f %f", &vnum, &vco.x, &vco.y) == 3) {
                          if (vnum < curmesh.texco.length)
                            curmesh.texco[vnum] = vco;
                        }
                      }
                    } else if (tok[0] == "*MESH_FACE_LIST") {
                      uint fnum;
                      int[3] fvt;
                      while (true) {
                        st = step(buff, tok);
                        if (st == Step.eof) break;
                        if (st == Step.skip) continue;
                        if (tok[0] == "}") break;
                        if (sscanf(buff, " *MESH_FACE %u: A: %i B: %i C: %i", &fnum, &fvt[0], &fvt[1], &fvt[2]) == 4) {
                          if (fnum < curmesh.face.length) {
                            curmesh.face[fnum].vt[0] = fvt[0];
                            curmesh.face[fnum].vt[1] = fvt[1];
                            curmesh.face[fnum].vt[2] = fvt[2];
                          }
                        }
                      }
                    } else if (tok[0] == "*MESH_TFACELIST") {
                      uint fnum;
                      int[3] fvt;
                      while (true) {
                        st = step(buff, tok);
                        if (st == Step.eof) break;
                        if (st == Step.skip) continue;
                        if (tok[0] == "}") break;
                        if (sscanf(buff, " *MESH_TFACE %u %i %i %i", &fnum, &fvt[0], &fvt[1], &fvt[2]) == 4) {
                          if (fnum < curmesh.face.length) {
                            curmesh.face[fnum].tc[0] = fvt[0];
                            curmesh.face[fnum].tc[1] = fvt[1];
                            curmesh.face[fnum].tc[2] = fvt[2];
                          }
                        }
                      }
                    } else if (tok[0] == "*MESH_NORMALS") {
                      uint fnum, vnum;
                      vec3f nrm;
                      while (true) {
                        st = step(buff, tok);
                        if (st == Step.eof) break;
                        if (st == Step.skip) continue;
                        if (tok[0] == "}") break;
                        if (sscanf(buff, " *MESH_FACENORMAL %u %f %f %f", &fnum, &nrm.x, &nrm.y, &nrm.z) == 4) {
                          if (fnum < curmesh.face.length) {
                            curmesh.face[fnum].facenormal = DO_TM2(nrm);
                            curmesh.face[fnum].facenormal.normalize();
                            curmesh.face[fnum].nr[0] = fnum * 3 + 0;
                            curmesh.face[fnum].nr[1] = fnum * 3 + 1;
                            curmesh.face[fnum].nr[2] = fnum * 3 + 2;
                          }
                        } else if (sscanf(buff, " *MESH_VERTEXNORMAL %u %f %f %f", &vnum, &nrm.x, &nrm.y, &nrm.z) == 4) {
                          if (vnum == curmesh.face[fnum].vt[0]) {
                            curmesh.norm[fnum * 3 + 0] = DO_TM2(nrm);
                            curmesh.norm[fnum * 3 + 0].normalize();
                          } else if (vnum == curmesh.face[fnum].vt[1]) {
                            curmesh.norm[fnum * 3 + 1] = DO_TM2(nrm);
                            curmesh.norm[fnum * 3 + 1].normalize();
                          } else if (vnum == curmesh.face[fnum].vt[2]) {
                            curmesh.norm[fnum * 3 + 2] = DO_TM2(nrm);
                            curmesh.norm[fnum * 3 + 2].normalize();
                          }
                        }
                      }
                    } else {
                      unknowndepth++;
                    }
                  } else if (tok[0] == "*MESH_NUMVERTEX") {
                    curmesh.vert.length = atoi(tok[1]);
                  } else if (tok[0] == "*MESH_NUMFACES") {
                    curmesh.face.length = atoi(tok[1]);
                    curmesh.norm.length = atoi(tok[1]) * 3; // 3 normals per face
                  } else if (tok[0] == "*MESH_NUMTVERTEX") {
                    curmesh.texco.length = atoi(tok[1]);
                  }
                }
              } else if (tok[0] == "*NODE_TM") {
                while (true) {
                  st = step(buff, tok);
                  if (st == Step.eof) break;
                  if (st == Step.skip) continue;
                  if (tok[0] == "}") {
                    // end of NODE_TM, do some processing
                    vec3f[3] sttm = [tm[0], tm[1], tm[2]];
                    tm[0] = vec3f(sttm[0].x, sttm[1].x, sttm[2].x);
                    tm[1] = vec3f(sttm[0].y, sttm[1].y, sttm[2].y);
                    tm[2] = vec3f(sttm[0].z, sttm[1].z, sttm[2].z);
                    break;
                  }
                  if (sscanf(buff, " *TM_ROW0 %f %f %f", &tm[0].x, &tm[0].y, &tm[0].z) == 3) {
                    // do nothing!
                  } else if (sscanf(buff, " *TM_ROW1 %f %f %f", &tm[1].x, &tm[1].y, &tm[1].z) == 3) {
                    // do nothing!
                  } else if (sscanf(buff, " *TM_ROW2 %f %f %f", &tm[2].x, &tm[2].y, &tm[2].z) == 3) {
                    // do nothing!
                  } else if (sscanf(buff, " *TM_ROW3 %f %f %f", &tm[3].x, &tm[3].y, &tm[3].z) == 3) {
                    // do nothing!
                  }
                }
              } else {
                unknowndepth++;
              }
            } else if (sscanf(buff, " *MATERIAL_REF %i", &tempi) == 1) {
              if (curmesh is null) {
                PUtil.outLog("warning: material ref before mesh in \"", filename, "\"");
                continue;
              }
              if (0 <= tempi && tempi < cast(int) matlist.length) {
                curmesh.fxname = matlist[tempi];
              }
            }
          }
        } else {
          unknowndepth++;
        }
      }
    }

    pfile.close();

    name = filename;
  }
}
