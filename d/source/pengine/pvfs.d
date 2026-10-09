// pvfs [pengine]
//
// A small virtual file system that replaces PhysFS: a search path made of real
// directories and ZIP archives mounted at the root, plus a single write directory.
//
// License: GPL version 2 (see included gpl.txt)
module pengine.pvfs;

import std.algorithm : canFind, endsWith, sort, startsWith;
import std.array : appender, array, split;
import std.file;
import std.path : buildPath, dirName;
import std.process : environment;
import std.string : lastIndexOf, strip;
import std.zip;

/// A file opened through the virtual file system. Reads are fully buffered in memory;
/// writes are buffered and flushed to disk on `close()`.
final class PFile
{
  ubyte[] data;
  size_t pos;
  bool writable;
  string realPath;

  this(ubyte[] data) { this.data = data; }

  bool eof() const { return pos >= data.length; }
  long length() const { return cast(long) data.length; }
  long tell() const { return cast(long) pos; }

  bool seek(long p)
  {
    if (p < 0 || p > cast(long) data.length) return false;
    pos = cast(size_t) p;
    return true;
  }

  /// Reads up to `buf.length` bytes. Returns the number of bytes read.
  long read(ubyte[] buf)
  {
    const avail = data.length - pos;
    const n = buf.length < avail ? buf.length : avail;
    buf[0 .. n] = data[pos .. pos + n];
    pos += n;
    return cast(long) n;
  }

  /// Reads the remaining contents of the file.
  ubyte[] readAll()
  {
    auto r = data[pos .. $];
    pos = data.length;
    return r;
  }

  long write(const(void)[] b)
  {
    data ~= cast(const(ubyte)[]) b;
    pos = data.length;
    return cast(long) b.length;
  }

  bool close()
  {
    if (writable) {
      try {
        std.file.write(realPath, data);
      } catch (Exception e) {
        PVfs.lastError = e.msg;
        return false;
      }
    }
    return true;
  }
}

private abstract class Mount
{
  string source; ///< The path used to mount, as given.

  abstract bool exists(string vpath);
  abstract bool isDir(string vpath);
  abstract ubyte[] readFile(string vpath, out bool ok);
  abstract void list(string vdir, ref bool[string] names);
}

private final class DirMount : Mount
{
  string root;

  this(string src, string root) { source = src; this.root = root; }

  private string rpath(string vpath) { return vpath.length ? buildPath(root, vpath) : root; }

  override bool exists(string vpath) { return std.file.exists(rpath(vpath)); }
  override bool isDir(string vpath) { auto p = rpath(vpath); return std.file.exists(p) && std.file.isDir(p); }

  override ubyte[] readFile(string vpath, out bool ok)
  {
    auto p = rpath(vpath);
    ok = false;
    if (!std.file.exists(p) || std.file.isDir(p)) return null;
    try {
      auto d = cast(ubyte[]) std.file.read(p);
      ok = true;
      return d;
    } catch (Exception) {
      return null;
    }
  }

  override void list(string vdir, ref bool[string] names)
  {
    auto p = rpath(vdir);
    if (!std.file.exists(p) || !std.file.isDir(p)) return;
    try {
      foreach (e; dirEntries(p, SpanMode.shallow))
        names[e.name[e.name.lastIndexOf('/') + 1 .. $]] = true;
    } catch (Exception) {
    }
  }
}

private final class ZipMount : Mount
{
  ZipArchive za;
  bool[string] files;
  bool[string] dirs;

  this(string src, ubyte[] bytes)
  {
    source = src;
    za = new ZipArchive(bytes);
    dirs[""] = true;
    foreach (name, member; za.directory) {
      string n = name;
      bool isDirEntry = n.endsWith("/");
      while (n.endsWith("/")) n = n[0 .. $ - 1];
      if (n.length == 0) continue;
      if (!isDirEntry)
        files[n] = true;
      else
        dirs[n] = true;
      // register parents
      auto idx = n.lastIndexOf('/');
      while (idx > 0) {
        n = n[0 .. idx];
        dirs[n] = true;
        idx = n.lastIndexOf('/');
      }
    }
  }

  override bool exists(string vpath) { return (vpath in files) !is null || (vpath in dirs) !is null; }
  override bool isDir(string vpath) { return (vpath in dirs) !is null; }

  override ubyte[] readFile(string vpath, out bool ok)
  {
    ok = false;
    if ((vpath in files) is null) return null;
    auto m = vpath in za.directory;
    if (m is null) return null;
    ok = true;
    return za.expand(*m);
  }

  override void list(string vdir, ref bool[string] names)
  {
    const prefix = vdir.length ? vdir ~ "/" : "";
    void scan(ref bool[string] set)
    {
      foreach (n; set.byKey) {
        if (n.length <= prefix.length || !n.startsWith(prefix)) continue;
        auto rest = n[prefix.length .. $];
        if (rest.canFind('/')) continue;
        names[rest] = true;
      }
    }
    scan(files);
    scan(dirs);
  }
}

/// Static facade of the virtual file system, mirroring the subset of PhysFS the game uses.
struct PVfs
{
  static string lastError;

  private static __gshared Mount[] mounts;
  private static __gshared string writeDir;
  private static __gshared bool inited;

  /// Normalizes a virtual path: strips leading/trailing slashes and rejects `..`.
  /// Returns false when the path is insecure.
  static bool normalize(string vpath, out string result)
  {
    string[] parts;
    foreach (p; vpath.split('/')) {
      if (p.length == 0 || p == ".") continue;
      if (p == "..") return false;
      parts ~= p;
    }
    string r;
    foreach (i, p; parts) {
      if (i) r ~= "/";
      r ~= p;
    }
    result = r;
    return true;
  }

  static bool init() { inited = true; mounts = null; writeDir = null; return true; }
  static bool deinit() { inited = false; mounts = null; return true; }
  static bool isInit() { return inited; }

  /// Directory the executable lives in, with a trailing separator.
  static string getBaseDir()
  {
    import std.file : thisExePath;
    return thisExePath().dirName() ~ "/";
  }

  /// Per-user writable directory, e.g. `~/.local/share/<org>/<app>/`.
  static string getPrefDir(string org, string app)
  {
    string base = environment.get("XDG_DATA_HOME", "");
    if (base.length == 0) {
      string home = environment.get("HOME", "");
      base = home.length ? buildPath(home, ".local", "share") : ".";
    }
    auto dir = buildPath(base, org, app) ~ "/";
    try {
      mkdirRecurse(dir);
    } catch (Exception e) {
      lastError = e.msg;
    }
    return dir;
  }

  static bool setWriteDir(string dir)
  {
    if (!exists_(dir)) {
      lastError = "no such directory";
      return false;
    }
    writeDir = dir;
    return true;
  }

  private static bool exists_(string p) { return std.file.exists(p) && std.file.isDir(p); }

  /// Appends a directory or ZIP archive to the search path (mounted at the root).
  static bool mount(string path, bool appendToPath = true)
  {
    try {
      Mount m;
      if (std.file.exists(path) && std.file.isDir(path)) {
        m = new DirMount(path, path);
      } else if (std.file.exists(path) && std.file.isFile(path)) {
        m = new ZipMount(path, cast(ubyte[]) std.file.read(path));
      } else {
        lastError = "not found";
        return false;
      }
      if (appendToPath)
        mounts ~= m;
      else
        mounts = m ~ mounts;
      return true;
    } catch (Exception e) {
      lastError = e.msg;
      return false;
    }
  }

  static bool exists(string vpath)
  {
    string p;
    if (!normalize(vpath, p)) return false;
    foreach (m; mounts)
      if (m.exists(p)) return true;
    return false;
  }

  static bool isDirectory(string vpath)
  {
    string p;
    if (!normalize(vpath, p)) return false;
    foreach (m; mounts)
      if (m.isDir(p)) return true;
    return false;
  }

  /// The mount source (as given to `mount()`) that provides `vpath`, or null.
  static string getRealDir(string vpath)
  {
    string p;
    if (!normalize(vpath, p)) return null;
    foreach (m; mounts)
      if (m.exists(p)) return m.source;
    return null;
  }

  static PFile openRead(string vpath)
  {
    string p;
    if (!normalize(vpath, p)) {
      lastError = "insecure path";
      return null;
    }
    foreach (m; mounts) {
      bool ok;
      auto d = m.readFile(p, ok);
      if (ok) return new PFile(d);
    }
    lastError = "not found";
    return null;
  }

  static PFile openWrite(string vpath)
  {
    string p;
    if (!normalize(vpath, p) || writeDir.length == 0) {
      lastError = writeDir.length == 0 ? "no write dir has been specified" : "insecure path";
      return null;
    }
    auto realp = buildPath(writeDir, p);
    try {
      mkdirRecurse(dirName(realp));
    } catch (Exception) {
    }
    auto f = new PFile(null);
    f.writable = true;
    f.realPath = realp;
    return f;
  }

  static bool mkdir(string vpath)
  {
    string p;
    if (!normalize(vpath, p) || writeDir.length == 0) {
      lastError = "no write dir has been specified";
      return false;
    }
    try {
      auto realp = buildPath(writeDir, p);
      if (std.file.exists(realp)) {
        lastError = "File exists";
        return false;
      }
      mkdirRecurse(realp);
      return true;
    } catch (Exception e) {
      lastError = e.msg;
      return false;
    }
  }

  /// Lists the entries (files and directories) in a virtual directory, over all mounts.
  static string[] enumerateFiles(string vdir)
  {
    string p;
    if (!normalize(vdir, p)) return null;
    bool[string] names;
    foreach (m; mounts)
      m.list(p, names);
    auto r = names.keys;
    r.sort();
    return r;
  }
}
