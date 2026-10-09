// texture [pengine]
//
// Copyright 2004-2006 Jasmine Langridge, jas@jareiko.net
// License: GPL version 2 (see included gpl.txt)
module pengine.texture;

import bindings.gl;
import bindings.sdl2 : SDL_GL_ExtensionSupported;
import pengine.app : PApp;
import pengine.image;
import pengine.subsys;
import pengine.util;
import pengine.vmath;

final class PSSTexture : PSubsystem
{
  private PResourceList!PTexture texlist;

  this(PApp parentApp)
  {
    super(parentApp);
    PUtil.outLog("Initialising texture subsystem [native PNG/JPEG decoders]");
  }

  override void shutdown()
  {
    PUtil.outLog("Shutting down texture subsystem");
    texlist.clear();
  }

  PTexture loadTexture(string name, bool genMipmaps = true, bool clamp = false)
  {
    PTexture tex = texlist.find(name);
    if (tex is null) {
      try {
        GLfloat cfgAnisotropy = app.getAnisotropy();
        tex = new PTexture(name, cfgAnisotropy, genMipmaps, clamp);
      } catch (PException e) {
        if (PUtil.isDebugLevel(DEBUGLEVEL_ENDUSER))
          PUtil.outLog("Failed to load ", name, ": ", e.msg);
        return null;
      }
      texlist.add(tex);
    }
    return tex;
  }
}

private void pickFormat(int cc, bool alphaOnly, out GLuint fmt, out GLuint fmt2)
{
  if (alphaOnly) {
    switch (cc) {
      case 1:
        fmt = GL_ALPHA; fmt2 = GL_ALPHA; break;
      case 2:
        fmt = GL_LUMINANCE_ALPHA; fmt2 = GL_LUMINANCE_ALPHA;
        PUtil.outLog("Warning: loadAlpha() has been used for image with 2 channels");
        break;
      case 3:
        fmt = GL_RGB; fmt2 = GL_RGB;
        PUtil.outLog("Warning: loadAlpha() has been used for RGB image");
        break;
      case 4:
        fmt = GL_RGBA; fmt2 = GL_RGBA;
        PUtil.outLog("Warning: loadAlpha() has been used for RGBA image");
        break;
      default:
        throw MakePException("loading texture failed, unknown image format");
    }
    return;
  }

  switch (cc) {
    case 1:
      fmt = GL_LUMINANCE; fmt2 = GL_LUMINANCE; break;
    case 2:
      fmt = GL_LUMINANCE_ALPHA; fmt2 = GL_LUMINANCE_ALPHA; break;
    case 3:
      fmt = GL_RGB; fmt2 = GL_RGB; break;
    case 4:
      fmt = GL_RGBA; fmt2 = GL_RGBA; break;
    default:
      throw MakePException("loading texture failed, unknown image format");
  }
}

private void powerOfTwoSize(int cx, int cy, out int newcx, out int newcy)
{
  newcx = 1;
  newcy = 1;
  int max;
  while (newcx < cx) newcx *= 2;
  while (newcy < cy) newcy *= 2;
  glGetIntegerv(GL_MAX_TEXTURE_SIZE, max);
  if (newcx > max) newcx = max;
  if (newcy > max) newcy = max;
}

/// Scales an image with nearest-neighbour sampling (replacement for SDL_BlitScaled).
private void scaleImage(int channels, int width_in, int height_in, const(ubyte)[] data_in,
                        int width_out, int height_out, ubyte[] data_out)
{
  if (channels < 1 || channels > 4)
    throw MakePException("Scaling failed, unknown image format");

  for (int y = 0; y < height_out; y++) {
    const sy = cast(int)(cast(long) y * height_in / height_out);
    for (int x = 0; x < width_out; x++) {
      const sx = cast(int)(cast(long) x * width_in / width_out);
      const so = (cast(size_t) sy * width_in + sx) * channels;
      const d = (cast(size_t) y * width_out + x) * channels;
      data_out[d .. d + channels] = data_in[so .. so + channels];
    }
  }
}

final class PTexture : PResource
{
  private GLuint texid;
  private GLenum textarget;

  this() { }

  this(string filename, GLfloat cfgAnisotropy, bool genMipmaps, bool clamp)
  {
    load(filename, cfgAnisotropy, genMipmaps, clamp);
  }

  this(ref PImage img, GLfloat cfgAnisotropy, bool genMipmaps, bool clamp)
  {
    load(img, cfgAnisotropy, genMipmaps, clamp);
  }

  void unload()
  {
    if (texid) {
      glDeleteTextures(1, &texid);
      texid = 0;
    }
  }

  void load(string filename, GLfloat cfgAnisotropy, bool genMipmaps, bool clamp)
  {
    auto image = PImage(filename);
    load(image, cfgAnisotropy, genMipmaps, clamp);
    name = filename;
  }

  /// Uploads a software generated mipmap chain, averaging 2x2 blocks in place.
  private void uploadMipmaps(GLenum target, GLuint fmt, GLuint fmt2, int newcx, int newcy, ubyte[] imd, int cc)
  {
    int level = 0;
    while (true) {
      glTexImage2D(target, level, fmt2, newcx, newcy, 0, fmt, GL_UNSIGNED_BYTE, imd.ptr);

      if (newcx <= 1 && newcy <= 1) break;

      if (newcx > 1) newcx /= 2;
      if (newcy > 1) newcy /= 2;
      level++;

      for (int y = 0; y < newcy; y++) {
        for (int x = 0; x < newcx; x++) {
          for (int z = 0; z < cc; z++) {
            imd[(y * newcx + x) * cc + z] = cast(ubyte)((cast(int)
                                                         imd[(y * newcx * 4 + x * 2 + 0) * cc + z] +
                                                         imd[(y * newcx * 4 + x * 2 + 1) * cc + z] +
                                                         imd[(y * newcx * 4 + x * 2 + 0 + newcx * 2) * cc + z] +
                                                         imd[(y * newcx * 4 + x * 2 + 1 + newcx * 2) * cc + z]) / 4);
          }
        }
      }
    }
  }

  private void setCommonParams(bool genMipmaps, bool clamp)
  {
    glTexParameteri(textarget, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    if (genMipmaps)
      glTexParameteri(textarget, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    else
      glTexParameteri(textarget, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

    if (clamp) {
      glTexParameteri(textarget, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri(textarget, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    } else {
      glTexParameteri(textarget, GL_TEXTURE_WRAP_S, GL_REPEAT);
      glTexParameteri(textarget, GL_TEXTURE_WRAP_T, GL_REPEAT);
    }
  }

  void load(ref PImage img, GLfloat cfgAnisotropy, bool genMipmaps = true, bool clamp = false)
  {
    unload();

    textarget = GL_TEXTURE_2D;

    GLuint fmt, fmt2;
    pickFormat(img.getcc(), false, fmt, fmt2);

    int cx = img.getcx(), cy = img.getcy();
    int newcx, newcy;
    powerOfTwoSize(cx, cy, newcx, newcy);

    if (newcx != cx || newcy != cy) {
      auto newimage = PImage(newcx, newcy, img.getcc());

      scaleImage(img.getcc(), cx, cy, img.getData(), newcx, newcy, newimage.getData());

      img.swap(newimage);
    }

    glGenTextures(1, &texid);
    bind();

    if (SDL_GL_ExtensionSupported("GL_EXT_texture_filter_anisotropic"))
      glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, cfgAnisotropy);
    else
      PUtil.outLog("Warning: anisotropic filtering is not supported.");

    setCommonParams(genMipmaps, clamp);

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    if (genMipmaps) {
      uploadMipmaps(GL_TEXTURE_2D, fmt, fmt2, newcx, newcy, img.getData(), img.getcc());
    } else {
      glTexImage2D(GL_TEXTURE_2D, 0, fmt2, newcx, newcy, 0, fmt, GL_UNSIGNED_BYTE, img.getData().ptr);
    }
  }

  void loadPiece(ref PImage img, int offx, int offy, int sizex, int sizey, bool genMipmaps = true, bool clamp = false)
  {
    unload();

    textarget = GL_TEXTURE_2D;

    // mipmaps are not generated for pieces (USE_GEN_MIPMAPS is not defined in the original)
    genMipmaps = false;

    GLuint fmt, fmt2;
    pickFormat(img.getcc(), false, fmt, fmt2);

    int cx = sizex, cy = sizey;
    int newcx, newcy;
    powerOfTwoSize(cx, cy, newcx, newcy);

    int cc = img.getcc();

    const offsetdata = img.getData()[(cast(size_t) offy * img.getcx() + offx) * cc .. $];

    ubyte[] buffer = new ubyte[cast(size_t) sizex * sizey * cc];

    for (int i = 0; i < sizey; i++) {
      // note: the original copies `sizey * cc` bytes per row
      buffer[cast(size_t) i * sizex * cc .. cast(size_t) i * sizex * cc + sizey * cc] =
        offsetdata[cast(size_t) i * img.getcx() * cc .. cast(size_t) i * img.getcx() * cc + sizey * cc];
    }

    if (newcx != cx || newcy != cy) {
      auto newimage = PImage(newcx, newcy, img.getcc());

      scaleImage(cc, cx, cy, buffer, newcx, newcy, newimage.getData());

      img.swap(newimage);

      buffer = new ubyte[cast(size_t) newcx * newcy * cc];
      buffer[] = img.getData()[0 .. buffer.length];
    }

    glGenTextures(1, &texid);
    bind();

    setCommonParams(genMipmaps, clamp);

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    glTexImage2D(GL_TEXTURE_2D, 0, fmt2, newcx, newcy, 0, fmt, GL_UNSIGNED_BYTE, buffer.ptr);
  }

  void loadAlpha(string filename, bool genMipmaps = true, bool clamp = false)
  {
    auto image = PImage(filename);
    loadAlpha(image, genMipmaps, clamp);
    name = filename;
  }

  void loadAlpha(ref PImage img, bool genMipmaps = true, bool clamp = false)
  {
    unload();

    textarget = GL_TEXTURE_2D;

    GLuint fmt, fmt2;
    pickFormat(img.getcc(), true, fmt, fmt2);

    int cx = img.getcx(), cy = img.getcy();
    int newcx, newcy;
    powerOfTwoSize(cx, cy, newcx, newcy);

    if (newcx != cx || newcy != cy) {
      auto newimage = PImage(newcx, newcy, img.getcc());

      scaleImage(img.getcc(), cx, cy, img.getData(), newcx, newcy, newimage.getData());

      img.swap(newimage);
    }

    glGenTextures(1, &texid);
    bind();

    setCommonParams(genMipmaps, clamp);

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    if (genMipmaps) {
      uploadMipmaps(GL_TEXTURE_2D, fmt, fmt2, newcx, newcy, img.getData(), img.getcc());
    } else {
      glTexImage2D(GL_TEXTURE_2D, 0, fmt2, newcx, newcy, 0, fmt, GL_UNSIGNED_BYTE, img.getData().ptr);
    }
  }

  void loadCubeMap(string filenamePrefix, string filenameSuffix, bool genMipmaps = true)
  {
    PUtil.outLog("loading \"", filenamePrefix, "*", filenameSuffix, "\" (cube map)");
    unload();

    textarget = GL_TEXTURE_CUBE_MAP;

    PImage img;

    glGenTextures(1, &texid);
    bind();

    static immutable string[6] middlename = ["px", "nx", "py", "ny", "pz", "nz"];

    foreach (side; 0 .. 6) {
      string filename = filenamePrefix ~ middlename[side] ~ filenameSuffix;

      img.load(filename);

      GLuint fmt, fmt2;
      try {
        pickFormat(img.getcc(), false, fmt, fmt2);
      } catch (PException) {
        throw MakePException(filename ~ " load failed, unknown image format");
      }

      int cx = img.getcx(), cy = img.getcy();
      int newcx, newcy;
      powerOfTwoSize(cx, cy, newcx, newcy);

      if (newcx != cx || newcy != cy) {
        auto newimage = PImage(newcx, newcy, img.getcc());

        scaleImage(img.getcc(), cx, cy, img.getData(), newcx, newcy, newimage.getData());

        img.swap(newimage);
      }

      glTexParameteri(textarget, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      if (genMipmaps)
        glTexParameteri(textarget, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
      else
        glTexParameteri(textarget, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

      glTexParameteri(textarget, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri(textarget, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

      glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

      if (genMipmaps) {
        // as in the original, the software mipmap path uploads to GL_TEXTURE_2D
        uploadMipmaps(GL_TEXTURE_2D, fmt, fmt2, newcx, newcy, img.getData(), img.getcc());
      } else {
        glTexImage2D(GL_TEXTURE_2D, 0, fmt2, newcx, newcy, 0, fmt, GL_UNSIGNED_BYTE, img.getData().ptr);
      }

      img.unload();
    }

    name = filenamePrefix;
  }

  void bind() const
  {
    glBindTexture(textarget, texid);
  }

  static void unbind()
  {
    // clear both used texture targets
    glBindTexture(GL_TEXTURE_2D, 0);
    glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
  }
}
