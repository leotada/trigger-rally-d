// vbuffer [pengine]
//
// Copyright 2004-2006 Jasmine Langridge, jas@jareiko.net
// License: GPL version 2 (see included gpl.txt)
module pengine.vbuffer;

import core.stdc.string : memset;

import bindings.gl;
import pengine.util;
import pengine.vmath;

/// Wraps an OpenGL vertex/index buffer, with a client-memory fallback when VBOs are unavailable.
final class PVBuffer
{
  enum contenttype { VertexContent, IndexContent }
  enum usagemode { StreamUsage, StaticUsage, DynamicUsage }

  alias VertexContent = contenttype.VertexContent;
  alias IndexContent = contenttype.IndexContent;
  alias StreamUsage = usagemode.StreamUsage;
  alias StaticUsage = usagemode.StaticUsage;
  alias DynamicUsage = usagemode.DynamicUsage;

  private GLuint buffid;
  private GLenum target;
  private contenttype pr_type;

  // emulation:
  private ubyte[] buffer;

  void unload()
  {
    if (hasVBO()) {
      if (buffid) glDeleteBuffersARB(1, &buffid);
      buffid = 0;
    } else {
      buffer = null;
    }
  }

  bool create(size_t buffsize, contenttype type, usagemode usage, const(void)* data = null)
  {
    unload();

    pr_type = type;

    if (hasVBO()) {
      final switch (type) {
        case contenttype.VertexContent:
          target = GL_ARRAY_BUFFER_ARB;
          break;
        case contenttype.IndexContent:
          target = GL_ELEMENT_ARRAY_BUFFER_ARB;
          break;
      }

      glGenBuffersARB(1, &buffid);
      bind();

      GLenum gl_usage;
      final switch (usage) {
        case usagemode.StreamUsage:
          gl_usage = GL_STREAM_DRAW_ARB;
          break;
        case usagemode.StaticUsage:
          gl_usage = GL_STATIC_DRAW_ARB;
          break;
        case usagemode.DynamicUsage:
          gl_usage = GL_DYNAMIC_DRAW_ARB;
          break;
      }

      glGetError();

      glBufferDataARB(target, buffsize, data, gl_usage);

      unbind();

      int err = glGetError();
      if (err != GL_NO_ERROR) {
        string reason;
        switch (err) {
          case GL_INVALID_OPERATION: reason = "invalid operation"; break;
          case GL_INVALID_ENUM: reason = "invalid enum"; break;
          case GL_OUT_OF_MEMORY: reason = "out of memory"; break;
          default: reason = "GL error code " ~ PUtil.formatInt(err); break;
        }
        PUtil.outLog(buffsize, " byte buffer creation failed, ", reason);
        unload();
        buffid = 0;
        return false;
      }
    } else {
      buffer = new ubyte[buffsize];
      if (data !is null)
        buffer[] = (cast(const(ubyte)*) data)[0 .. buffsize];
    }

    return true;
  }

  void update(size_t offset, size_t buffsize, const(void)* data)
  {
    if (hasVBO()) {
      bind();
      glBufferSubDataARB(target, offset, buffsize, data);
      unbind();
    } else {
      buffer[offset .. offset + buffsize] = (cast(const(ubyte)*) data)[0 .. buffsize];
    }
  }

  /// With VBOs this is just the offset; without them, a pointer into client memory.
  const(void)* getPointer(size_t offset)
  {
    if (hasVBO())
      return cast(const(void)*) offset;
    else
      return buffer.ptr + offset;
  }

  void bind()
  {
    if (hasVBO())
      glBindBufferARB(target, buffid);
  }

  static void unbind()
  {
    if (hasVBO()) {
      glBindBufferARB(GL_ARRAY_BUFFER_ARB, 0);
      glBindBufferARB(GL_ELEMENT_ARRAY_BUFFER_ARB, 0);
    }
  }
}

/// A growable in-memory file used to build vertex/index data.
final class PRamFile
{
  private ubyte[] buffer;
  private size_t cursor;

  void write(const(void)* data, size_t datasize)
  {
    const newextent = cursor + datasize;
    const buffsize = buffer.length;
    if (newextent > buffsize) {
      buffer.length = newextent;
      if (cursor > buffsize)
        memset(&buffer[buffsize], 0, cursor - buffsize);
    }

    buffer[cursor .. cursor + datasize] = (cast(const(ubyte)*) data)[0 .. datasize];
    cursor += datasize;
  }

  void write(T)(in T value) if (!is(T : const(void)*))
  {
    write(&value, T.sizeof);
  }

  void seek_cur(ptrdiff_t pos) { seek_set(pos + cast(ptrdiff_t) cursor); }
  void seek_end(ptrdiff_t pos) { seek_set(pos + cast(ptrdiff_t) buffer.length); }
  void seek_set(ptrdiff_t pos) { cursor = (pos >= 0) ? cast(size_t) pos : 0; }
  size_t tell() { return cursor; }

  void clear()
  {
    buffer.length = 0;
    cursor = 0;
  }

  const(void)* getData() { return buffer.ptr; }
  size_t getSize() { return buffer.length; }
}
