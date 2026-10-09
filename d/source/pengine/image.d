// image [pengine]
//
// Image loading (PNG and JPEG) replacing SDL_image. Pixel data is stored
// bottom-up, tightly packed, with 1, 3 or 4 channels, as the original
// `PImage::load` produced it.
//
// License: GPL version 2 (see included gpl.txt)
module pengine.image;

import std.algorithm : endsWith, min;
import std.zlib : uncompress;
import std.string : toLower;

import arsd.jpeg : readJpegFromMemory;
import arsd.color : MemoryImage, TrueColorImage;

import pengine.pvfs;
import pengine.util;

/// A decoded image, rows ordered top to bottom.
struct DecodedImage
{
  int w, h, cc;
  ubyte[] pixels;
}

private uint be32(const(ubyte)[] d, size_t o)
{
  return (cast(uint) d[o] << 24) | (cast(uint) d[o + 1] << 16) | (cast(uint) d[o + 2] << 8) | d[o + 3];
}

private int paeth(int a, int b, int c)
{
  int p = a + b - c;
  int pa = p > a ? p - a : a - p;
  int pb = p > b ? p - b : b - p;
  int pc = p > c ? p - c : c - p;
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

/// Decodes a PNG file (all bit depths, color types and Adam7 interlacing).
DecodedImage decodePNG(const(ubyte)[] bytes)
{
  static immutable ubyte[8] sig = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 8 || bytes[0 .. 8] != sig[])
    throw MakePException("not a PNG file");

  int width, height, depth, ctype, interlace;
  ubyte[] idat;
  ubyte[] plte;
  ubyte[] trns;
  bool haveHeader;

  size_t pos = 8;
  while (pos + 12 <= bytes.length) {
    uint len = be32(bytes, pos);
    string type = cast(string) bytes[pos + 4 .. pos + 8].idup;
    if (pos + 12 + len > bytes.length) break;
    auto data = bytes[pos + 8 .. pos + 8 + len];
    if (type == "IHDR") {
      width = cast(int) be32(data, 0);
      height = cast(int) be32(data, 4);
      depth = data[8];
      ctype = data[9];
      interlace = data[12];
      haveHeader = true;
    } else if (type == "PLTE") {
      plte = data.dup;
    } else if (type == "tRNS") {
      trns = data.dup;
    } else if (type == "IDAT") {
      idat ~= data;
    } else if (type == "IEND") {
      break;
    }
    pos += 12 + len;
  }

  if (!haveHeader || width <= 0 || height <= 0)
    throw MakePException("invalid PNG header");

  int samples;
  switch (ctype) {
    case 0: samples = 1; break;
    case 2: samples = 3; break;
    case 3: samples = 1; break;
    case 4: samples = 2; break;
    case 6: samples = 4; break;
    default: throw MakePException("unsupported PNG color type");
  }

  const bpp = samples * depth;
  const bytesPerPixel = bpp >= 8 ? bpp / 8 : 1;

  // output channels
  int cc;
  switch (ctype) {
    case 0: cc = 1; break;
    case 2: cc = 3; break;
    case 3: cc = trns.length ? 4 : 3; break;
    case 4: cc = 4; break;
    default: cc = 4; break;
  }

  auto raw = cast(ubyte[]) uncompress(idat);

  DecodedImage img;
  img.w = width;
  img.h = height;
  img.cc = cc;
  img.pixels = new ubyte[cast(size_t) width * height * cc];

  // reads one sample (scaled to 8 bits) of a pixel from an unfiltered scanline
  int sample(const(ubyte)[] row, int px, int s)
  {
    if (depth == 8) return row[px * samples + s];
    if (depth == 16) return row[(px * samples + s) * 2];
    const bitIndex = (px * samples + s) * depth;
    const byteVal = row[bitIndex >> 3];
    const shift = 8 - depth - (bitIndex & 7);
    const maxv = (1 << depth) - 1;
    const v = (byteVal >> shift) & maxv;
    return v * 255 / maxv;
  }

  int rawIndex(const(ubyte)[] row, int px, int s)
  {
    // raw (non scaled) value, used for palette indices
    if (depth == 8) return row[px * samples + s];
    const bitIndex = (px * samples + s) * depth;
    const byteVal = row[bitIndex >> 3];
    const shift = 8 - depth - (bitIndex & 7);
    return (byteVal >> shift) & ((1 << depth) - 1);
  }

  void putPixel(const(ubyte)[] row, int px, int x, int y)
  {
    auto o = (cast(size_t) y * width + x) * cc;
    final switch (ctype) {
      case 0:
        img.pixels[o] = cast(ubyte) sample(row, px, 0);
        break;
      case 2:
        img.pixels[o] = cast(ubyte) sample(row, px, 0);
        img.pixels[o + 1] = cast(ubyte) sample(row, px, 1);
        img.pixels[o + 2] = cast(ubyte) sample(row, px, 2);
        break;
      case 3: {
        int idx = rawIndex(row, px, 0);
        if (idx * 3 + 2 < plte.length) {
          img.pixels[o] = plte[idx * 3];
          img.pixels[o + 1] = plte[idx * 3 + 1];
          img.pixels[o + 2] = plte[idx * 3 + 2];
        }
        if (cc == 4)
          img.pixels[o + 3] = idx < trns.length ? trns[idx] : 255;
        break;
      }
      case 4: {
        ubyte g = cast(ubyte) sample(row, px, 0);
        img.pixels[o] = g;
        img.pixels[o + 1] = g;
        img.pixels[o + 2] = g;
        img.pixels[o + 3] = cast(ubyte) sample(row, px, 1);
        break;
      }
      case 6:
        img.pixels[o] = cast(ubyte) sample(row, px, 0);
        img.pixels[o + 1] = cast(ubyte) sample(row, px, 1);
        img.pixels[o + 2] = cast(ubyte) sample(row, px, 2);
        img.pixels[o + 3] = cast(ubyte) sample(row, px, 3);
        break;
      case 1: case 5: case 7:
        break;
    }
  }

  size_t rpos = 0;

  // unfilters and stores one (sub)image
  void decodePass(int pw, int ph, int xs, int ys, int dx, int dy)
  {
    if (pw <= 0 || ph <= 0) return;
    const rowBytes = (pw * bpp + 7) / 8;
    ubyte[] prev = new ubyte[rowBytes];
    ubyte[] cur = new ubyte[rowBytes];
    for (int y = 0; y < ph; y++) {
      if (rpos + 1 + rowBytes > raw.length)
        throw MakePException("truncated PNG data");
      const ft = raw[rpos++];
      cur[] = raw[rpos .. rpos + rowBytes];
      rpos += rowBytes;
      switch (ft) {
        case 0: break;
        case 1:
          for (int i = bytesPerPixel; i < rowBytes; i++)
            cur[i] = cast(ubyte)(cur[i] + cur[i - bytesPerPixel]);
          break;
        case 2:
          for (int i = 0; i < rowBytes; i++)
            cur[i] = cast(ubyte)(cur[i] + prev[i]);
          break;
        case 3:
          for (int i = 0; i < rowBytes; i++) {
            int left = i >= bytesPerPixel ? cur[i - bytesPerPixel] : 0;
            cur[i] = cast(ubyte)(cur[i] + ((left + prev[i]) >> 1));
          }
          break;
        case 4:
          for (int i = 0; i < rowBytes; i++) {
            int left = i >= bytesPerPixel ? cur[i - bytesPerPixel] : 0;
            int upleft = i >= bytesPerPixel ? prev[i - bytesPerPixel] : 0;
            cur[i] = cast(ubyte)(cur[i] + paeth(left, prev[i], upleft));
          }
          break;
        default:
          throw MakePException("bad PNG filter type");
      }
      for (int x = 0; x < pw; x++)
        putPixel(cur, x, xs + x * dx, ys + y * dy);
      auto t = prev;
      prev = cur;
      cur = t;
    }
  }

  if (interlace == 0) {
    decodePass(width, height, 0, 0, 1, 1);
  } else {
    static immutable int[7] sx = [0, 4, 0, 2, 0, 1, 0];
    static immutable int[7] sy = [0, 0, 4, 0, 2, 0, 1];
    static immutable int[7] ddx = [8, 8, 4, 4, 2, 2, 1];
    static immutable int[7] ddy = [8, 8, 8, 4, 4, 2, 2];
    foreach (p; 0 .. 7) {
      int pw = (width - sx[p] + ddx[p] - 1) / ddx[p];
      int ph = (height - sy[p] + ddy[p] - 1) / ddy[p];
      if (width <= sx[p]) pw = 0;
      if (height <= sy[p]) ph = 0;
      decodePass(pw, ph, sx[p], sy[p], ddx[p], ddy[p]);
    }
  }

  return img;
}

/// Number of color components declared in a JPEG file (1 = grayscale).
private int jpegComponents(const(ubyte)[] d)
{
  size_t p = 2;
  while (p + 4 < d.length) {
    if (d[p] != 0xFF) {
      p++;
      continue;
    }
    const m = d[p + 1];
    if (m == 0xFF) {
      p++;
      continue;
    }
    if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
      if (p + 9 < d.length) return d[p + 9];
      return 3;
    }
    if (m == 0xD8 || (m >= 0xD0 && m <= 0xD7) || m == 0x01) {
      p += 2;
      continue;
    }
    const len = (cast(int) d[p + 2] << 8) | d[p + 3];
    p += 2 + len;
  }
  return 3;
}

DecodedImage decodeJPEG(const(ubyte)[] bytes)
{
  MemoryImage mi = readJpegFromMemory(bytes);
  if (mi is null) throw MakePException("JPEG decoding failed");
  TrueColorImage tc = mi.getAsTrueColorImage();
  const int comps = jpegComponents(bytes);

  DecodedImage img;
  img.w = tc.width;
  img.h = tc.height;
  img.cc = comps == 1 ? 1 : 3;
  img.pixels = new ubyte[cast(size_t) img.w * img.h * img.cc];

  // copy right away: the arsd image frees its buffer when collected
  const src = tc.imageData.bytes;
  const count = cast(size_t) img.w * img.h;
  for (size_t i = 0; i < count; i++) {
    if (img.cc == 1) {
      img.pixels[i] = src[i * 4];
    } else {
      img.pixels[i * 3] = src[i * 4];
      img.pixels[i * 3 + 1] = src[i * 4 + 1];
      img.pixels[i * 3 + 2] = src[i * 4 + 2];
    }
  }
  return img;
}

/// An image in main memory (the equivalent of the original `PImage`).
struct PImage
{
  ubyte[] data;
  int cx, cy, cc;

  this(string filename) { load(filename); }
  this(int _cx, int _cy, int _cc) { load(_cx, _cy, _cc); }

  void load(string filename)
  {
    data = null;

    if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
      PUtil.outLog("Loading image \"", filename, "\"");

    PFile pfile = PVfs.openRead(filename);

    if (pfile is null)
      throw MakePException(filename ~ ", PhysFS: " ~ PVfs.lastError);

    auto bytes = pfile.readAll();
    pfile.close();

    DecodedImage dec;
    const lower = filename.toLower();
    try {
      if (lower.endsWith(".png"))
        dec = decodePNG(bytes);
      else if (lower.endsWith(".jpg") || lower.endsWith(".jpeg"))
        dec = decodeJPEG(bytes);
      else if (bytes.length > 8 && bytes[1 .. 4] == cast(const(ubyte)[]) "PNG")
        dec = decodePNG(bytes);
      else if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8)
        dec = decodeJPEG(bytes);
      else
        throw MakePException("unsupported image format");
    } catch (PException e) {
      throw MakePException(filename ~ ", image: " ~ e.msg);
    } catch (Exception e) {
      throw MakePException(filename ~ ", image: " ~ e.msg);
    }

    cx = dec.w;
    cy = dec.h;
    cc = dec.cc;
    data = new ubyte[cast(size_t) cx * cy * cc];

    // the image is stored upside down (first row is the bottom one), as OpenGL expects
    const rowSize = cast(size_t) cx * cc;
    for (int y = 0; y < cy; y++)
      data[cast(size_t) y * rowSize .. cast(size_t)(y + 1) * rowSize] =
        dec.pixels[cast(size_t)(cy - y - 1) * rowSize .. cast(size_t)(cy - y) * rowSize];
  }

  void load(int _cx, int _cy, int _cc)
  {
    cx = _cx;
    cy = _cy;
    cc = _cc;

    data = new ubyte[cast(size_t) cx * cy * cc];
  }

  void unload() { data = null; }

  int getcx() const { return cx; }
  int getcy() const { return cy; }
  int getcc() const { return cc; }
  ubyte[] getData() { return data; }
  const(ubyte)[] getData() const { return data; }
  ubyte getByte(size_t i) const { return data[i]; }

  void swap(ref PImage other)
  {
    auto t = this;
    this = other;
    other = t;
  }
}
