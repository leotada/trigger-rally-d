// Copyright (C) 2004-2006 Jasmine Langridge and contributors (see the NOTICE file)
// Part of the D port of Trigger Rally.
// License: GNU General Public License, version 2 or later (see COPYING.txt)
/// Minimal hand-written legacy OpenGL bindings (functions resolved through SDL_GL_GetProcAddress).
module bindings.gl;

import std.string : toStringz;
import std.traits : ReturnType, Parameters;
import bindings.sdl2 : SDL_GL_GetProcAddress;
import pengine.vmath;

alias GLenum = uint;
alias GLboolean = ubyte;
alias GLbitfield = uint;
alias GLbyte = byte;
alias GLshort = short;
alias GLint = int;
alias GLsizei = int;
alias GLubyte = ubyte;
alias GLushort = ushort;
alias GLuint = uint;
alias GLfloat = float;
alias GLclampf = float;
alias GLdouble = double;
alias GLclampd = double;
alias GLvoid = void;
alias GLsizeiptr = ptrdiff_t;
alias GLintptr = ptrdiff_t;

enum : GLenum {
  GL_FALSE = 0,
  GL_TRUE = 1,
  GL_DEPTH_BUFFER_BIT = 0x00000100,
  GL_COLOR_BUFFER_BIT = 0x00004000,
  GL_POINTS = 0x0000,
  GL_LINES = 0x0001,
  GL_TRIANGLES = 0x0004,
  GL_TRIANGLE_STRIP = 0x0005,
  GL_TRIANGLE_FAN = 0x0006,
  GL_QUADS = 0x0007,
  GL_ZERO = 0,
  GL_ONE = 1,
  GL_SRC_COLOR = 0x0300,
  GL_DST_COLOR = 0x0306,
  GL_SRC_ALPHA = 0x0302,
  GL_ONE_MINUS_SRC_ALPHA = 0x0303,
  GL_FRONT = 0x0404,
  GL_BACK = 0x0405,
  GL_BACK_LEFT = 0x0402,
  GL_BACK_RIGHT = 0x0403,
  GL_FRONT_AND_BACK = 0x0408,
  GL_CULL_FACE = 0x0B44,
  GL_LIGHTING = 0x0B50,
  GL_FOG = 0x0B60,
  GL_DEPTH_TEST = 0x0B71,
  GL_ALPHA_TEST = 0x0BC0,
  GL_BLEND = 0x0BE2,
  GL_NORMALIZE = 0x0BA1,
  GL_TEXTURE_2D = 0x0DE1,
  GL_TEXTURE_3D = 0x806F,
  GL_TEXTURE_CUBE_MAP = 0x8513,
  GL_TEXTURE_CUBE_MAP_POSITIVE_X = 0x8515,
  GL_TEXTURE_CUBE_MAP_NEGATIVE_X = 0x8516,
  GL_TEXTURE_CUBE_MAP_POSITIVE_Y = 0x8517,
  GL_TEXTURE_CUBE_MAP_NEGATIVE_Y = 0x8518,
  GL_TEXTURE_CUBE_MAP_POSITIVE_Z = 0x8519,
  GL_TEXTURE_CUBE_MAP_NEGATIVE_Z = 0x851A,
  GL_LIGHT0 = 0x4000,
  GL_TEXTURE_GEN_S = 0x0C60,
  GL_TEXTURE_GEN_T = 0x0C61,
  GL_VERTEX_ARRAY = 0x8074,
  GL_TEXTURE_COORD_ARRAY = 0x8078,
  GL_MODELVIEW = 0x1700,
  GL_PROJECTION = 0x1701,
  GL_TEXTURE = 0x1702,
  GL_MODELVIEW_MATRIX = 0x0BA6,
  GL_PROJECTION_MATRIX = 0x0BA7,
  GL_CURRENT_COLOR = 0x0B00,
  GL_POINT_SIZE = 0x0B11,
  GL_MAX_TEXTURE_SIZE = 0x0D33,
  GL_UNPACK_ALIGNMENT = 0x0CF5,
  GL_FLOAT = 0x1406,
  GL_UNSIGNED_BYTE = 0x1401,
  GL_UNSIGNED_SHORT = 0x1403,
  GL_UNSIGNED_INT = 0x1405,
  GL_ALPHA = 0x1906,
  GL_RGB = 0x1907,
  GL_RGBA = 0x1908,
  GL_LUMINANCE = 0x1909,
  GL_LUMINANCE_ALPHA = 0x190A,
  GL_LESS = 0x0201,
  GL_EQUAL = 0x0202,
  GL_LEQUAL = 0x0203,
  GL_GREATER = 0x0204,
  GL_NOTEQUAL = 0x0205,
  GL_GEQUAL = 0x0206,
  GL_ALWAYS = 0x0207,
  GL_EXP = 0x0800,
  GL_FOG_DENSITY = 0x0B62,
  GL_FOG_MODE = 0x0B65,
  GL_FOG_COLOR = 0x0B66,
  GL_LIGHT_MODEL_AMBIENT = 0x0B53,
  GL_LIGHT_MODEL_TWO_SIDE = 0x0B52,
  GL_AMBIENT_AND_DIFFUSE = 0x1602,
  GL_DIFFUSE = 0x1201,
  GL_SPECULAR = 0x1202,
  GL_POSITION = 0x1203,
  GL_SHININESS = 0x1601,
  GL_TEXTURE_ENV = 0x2300,
  GL_TEXTURE_ENV_MODE = 0x2200,
  GL_MODULATE = 0x2100,
  GL_COMBINE = 0x8570,
  GL_COMBINE_RGB = 0x8571,
  GL_COMBINE_ALPHA = 0x8572,
  GL_ADD_SIGNED = 0x8574,
  GL_TEXTURE_GEN_MODE = 0x2500,
  GL_OBJECT_PLANE = 0x2501,
  GL_OBJECT_LINEAR = 0x2401,
  GL_S = 0x2000,
  GL_T = 0x2001,
  GL_TEXTURE_MAG_FILTER = 0x2800,
  GL_TEXTURE_MIN_FILTER = 0x2801,
  GL_TEXTURE_WRAP_S = 0x2802,
  GL_TEXTURE_WRAP_T = 0x2803,
  GL_LINEAR = 0x2601,
  GL_LINEAR_MIPMAP_LINEAR = 0x2703,
  GL_REPEAT = 0x2901,
  GL_CLAMP_TO_EDGE = 0x812F,
  GL_TEXTURE_MAX_ANISOTROPY_EXT = 0x84FE,
  GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT = 0x84FF,
  GL_MAX_TEXTURE_UNITS = 0x84E2,
  GL_TEXTURE0_ARB = 0x84C0,
  GL_TEXTURE1_ARB = 0x84C1,
  GL_ARRAY_BUFFER_ARB = 0x8892,
  GL_ELEMENT_ARRAY_BUFFER_ARB = 0x8893,
  GL_STREAM_DRAW_ARB = 0x88E0,
  GL_STATIC_DRAW_ARB = 0x88E4,
  GL_DYNAMIC_DRAW_ARB = 0x88E8,
  GL_VENDOR = 0x1F00,
  GL_RENDERER = 0x1F01,
  GL_VERSION = 0x1F02,
  GL_NO_ERROR = 0,
  GL_INVALID_ENUM = 0x0500,
  GL_INVALID_OPERATION = 0x0502,
  GL_OUT_OF_MEMORY = 0x0505,
  GL_VERTEX_PROGRAM_POINT_SIZE = 0x8642,
}

private struct GLProcs {
  extern (System) nothrow {
    void function(GLbitfield) glClear;
    void function(GLclampf, GLclampf, GLclampf, GLclampf) glClearColor;
    void function(GLclampd) glClearDepth;
    void function(GLenum) glEnable;
    void function(GLenum) glDisable;
    void function(GLenum) glEnableClientState;
    void function(GLenum) glDisableClientState;
    void function(GLenum, GLenum) glBlendFunc;
    void function(GLenum) glDepthFunc;
    void function(GLboolean) glDepthMask;
    void function(GLclampd, GLclampd) glDepthRange;
    void function(GLenum) glCullFace;
    void function(GLenum, GLclampf) glAlphaFunc;
    void function(GLboolean, GLboolean, GLboolean, GLboolean) glColorMask;
    void function(GLenum) glDrawBuffer;
    void function(GLenum) glReadBuffer;
    void function(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void*) glReadPixels;
    void function() glFinish;
    void function() glFlush;
    GLenum function() glGetError;
    const(GLubyte)* function(GLenum) glGetString;
    void function(GLenum, GLfloat*) glGetFloatv;
    void function(GLenum, GLint*) glGetIntegerv;
    void function(GLenum, GLfloat) glFogf;
    void function(GLenum, const(GLfloat)*) glFogfv;
    void function(GLenum, GLint) glFogi;
    void function(GLdouble, GLdouble, GLdouble, GLdouble, GLdouble, GLdouble) glFrustum;
    void function(GLdouble, GLdouble, GLdouble, GLdouble, GLdouble, GLdouble) glOrtho;
    void function(GLenum, GLenum, const(GLfloat)*) glLightfv;
    void function(GLenum, const(GLfloat)*) glLightModelfv;
    void function(GLenum, GLint) glLightModeli;
    void function(GLenum, GLenum, GLfloat) glMaterialf;
    void function(GLenum, GLenum, const(GLfloat)*) glMaterialfv;
    void function(GLenum) glMatrixMode;
    void function() glLoadIdentity;
    void function() glPushMatrix;
    void function() glPopMatrix;
    void function(const(GLfloat)*) glMultMatrixf;
    void function(GLfloat, GLfloat, GLfloat, GLfloat) glRotatef;
    void function(GLfloat, GLfloat, GLfloat) glScalef;
    void function(GLfloat, GLfloat, GLfloat) glTranslatef;
    void function(GLenum) glBegin;
    void function() glEnd;
    void function(GLfloat, GLfloat, GLfloat) glColor3f;
    void function(GLubyte, GLubyte, GLubyte) glColor3ub;
    void function(GLfloat, GLfloat, GLfloat, GLfloat) glColor4f;
    void function(const(GLfloat)*) glColor4fv;
    void function(const(GLfloat)*) glNormal3fv;
    void function(GLfloat, GLfloat) glTexCoord2f;
    void function(const(GLfloat)*) glTexCoord2fv;
    void function(GLint, GLint) glTexCoord2i;
    void function(GLfloat, GLfloat) glVertex2f;
    void function(GLfloat, GLfloat, GLfloat) glVertex3f;
    void function(const(GLfloat)*) glVertex3fv;
    void function(GLfloat) glPointSize;
    void function(GLint, GLint, GLsizei, GLsizei) glViewport;
    void function(GLenum, GLuint) glBindTexture;
    void function(GLsizei, const(GLuint)*) glDeleteTextures;
    void function(GLsizei, GLuint*) glGenTextures;
    void function(GLenum, GLint) glPixelStorei;
    void function(GLenum, GLenum, GLfloat) glTexParameterf;
    void function(GLenum, GLenum, GLint) glTexParameteri;
    void function(GLenum, GLenum, GLint) glTexEnvi;
    void function(GLenum, GLenum, const(GLfloat)*) glTexGenfv;
    void function(GLenum, GLenum, GLint) glTexGeni;
    void function(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const(void)*) glTexImage2D;
    void function(GLint, GLenum, GLsizei, const(void)*) glVertexPointer;
    void function(GLint, GLenum, GLsizei, const(void)*) glTexCoordPointer;
    void function(GLenum, GLuint, GLuint, GLsizei, GLenum, const(void)*) glDrawRangeElements;
    // ARB extensions
    void function(GLenum) glActiveTextureARB;
    void function(GLenum, GLuint) glBindBufferARB;
    void function(GLsizei, const(GLuint)*) glDeleteBuffersARB;
    void function(GLsizei, GLuint*) glGenBuffersARB;
    void function(GLenum, GLsizeiptr, const(void)*, GLenum) glBufferDataARB;
    void function(GLenum, GLintptr, GLsizeiptr, const(void)*) glBufferSubDataARB;
  }
}

private __gshared GLProcs procs;

/// Resolves all OpenGL entry points. Must be called after a GL context has been made current.
/// Returns the names of core entry points that could not be found.
string[] loadGL()
{
  string[] missing;

  static foreach (m; __traits(allMembers, GLProcs)) {
    {
      auto p = SDL_GL_GetProcAddress(m.toStringz);
      __traits(getMember, procs, m) = cast(typeof(__traits(getMember, procs, m))) p;
      if (p is null)
        missing ~= m;
    }
  }
  return missing;
}

/// True when the ARB vertex buffer object entry points are available.
bool hasVBO()
{
  return procs.glGenBuffersARB !is null && procs.glBindBufferARB !is null &&
         procs.glBufferDataARB !is null && procs.glBufferSubDataARB !is null &&
         procs.glDeleteBuffersARB !is null;
}

// Forwarding D functions with the same names as the C API.
static foreach (m; __traits(allMembers, GLProcs)) {
  mixin("pragma(inline, true) ReturnType!(typeof(GLProcs." ~ m ~ ")) " ~ m ~ "(Parameters!(typeof(GLProcs." ~ m ~ ")) args) { return procs." ~ m ~ "(args); }");
}

// Convenience overloads accepting the math types instead of raw float pointers.
void glVertex3fv(in vec3f v) { procs.glVertex3fv(&v.x); }
void glNormal3fv(in vec3f v) { procs.glNormal3fv(&v.x); }
void glTexCoord2fv(in vec2f v) { procs.glTexCoord2fv(&v.x); }
void glColor4fv(in vec4f v) { procs.glColor4fv(&v.x); }
void glLightfv(GLenum light, GLenum pname, in vec4f v) { procs.glLightfv(light, pname, &v.x); }
void glFogfv(GLenum pname, in vec4f v) { procs.glFogfv(pname, &v.x); }
void glMultMatrixf(in mat44f m) { procs.glMultMatrixf(&m.row[0].x); }
void glGetFloatv(GLenum pname, ref mat44f m) { procs.glGetFloatv(pname, &m.row[0].x); }
void glGetFloatv(GLenum pname, ref float f) { procs.glGetFloatv(pname, &f); }
void glGetIntegerv(GLenum pname, ref int i) { procs.glGetIntegerv(pname, &i); }
void glGetFloatv(GLenum pname, ref float[4] f) { procs.glGetFloatv(pname, f.ptr); }
void glLightModelfv(GLenum pname, in float[4] f) { procs.glLightModelfv(pname, f.ptr); }
void glLightfv(GLenum light, GLenum pname, in float[4] f) { procs.glLightfv(light, pname, f.ptr); }
void glMaterialfv(GLenum face, GLenum pname, in float[4] f) { procs.glMaterialfv(face, pname, f.ptr); }
void glTexGenfv(GLenum coord, GLenum pname, in float[4] f) { procs.glTexGenfv(coord, pname, f.ptr); }
