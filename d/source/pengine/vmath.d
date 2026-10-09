// vmath [pengine]
//
// Copyright 2004-2006 Jasmine Langridge, jas@jareiko.net
// License: GPL version 2 (see included gpl.txt)
//
// D port of vmath.h / vmath.cpp.
module pengine.vmath;

import core.stdc.stdlib : rand, RAND_MAX;
import std.math : sqrt, sin, cos, fabs;

enum double PI = 3.1415926535897932384626433832795;

double RADIANS(double a) { return a * PI / 180.0; }
double DEGREES(double a) { return a * 180.0 / PI; }

float rand01() { return cast(float) rand() / cast(float) RAND_MAX; }
float randm11() { return 2.0f * cast(float) rand() / cast(float) RAND_MAX - 1.0f; }

T MAX(T)(T a, T b) { return (a >= b) ? a : b; }
T MIN(T)(T a, T b) { return (a <= b) ? a : b; }

/// `v = MIN(v, max)`
void CLAMP_UPPER(T, U)(ref T v, U max) { v = MIN(v, cast(T) max); }
/// `v = MAX(v, min)`
void CLAMP_LOWER(T, U)(ref T v, U min) { v = MAX(v, cast(T) min); }
/// `v = MAX(MIN(v, max), min)`
void CLAMP(T, U, V)(ref T v, U min, V max) { v = MAX(MIN(v, cast(T) max), cast(T) min); }

auto INTERP(A, B, F)(A a, B b, F f) { return a + (b - a) * f; }

auto SQUARED(T)(T x) { return x * x; }

/// `val = target + (val - target) / (1.0 + delta)`
void PULLTOWARD(T, U, D)(ref T val, U target, D delta)
{
  val = target + (val - target) / (1.0 + delta);
}

void DEADZONE(T, Z)(ref T val, Z zone)
{
  val = (val > zone) ? ((val - zone) / (1.0 - zone)) :
        ((val < -zone) ? ((val + zone) / (1.0 - zone)) : 0.0);
}

/// `val = ((val - premin) * (postmax - postmin) / (premax - premin) + postmin)`
void RANGEADJUST(T)(ref T val, double premin, double premax, double postmin, double postmax)
{
  val = (val - premin) * (postmax - postmin) / (premax - premin) + postmin;
}

alias int8 = byte;
alias uint8 = ubyte;
alias int16 = short;
alias uint16 = ushort;
alias int32 = int;
alias uint32 = uint;

struct vec2(T)
{
  T x = 0, y = 0;

  this(T _x, T _y) { x = _x; y = _y; }

  ref T opIndex(size_t i) return { return (&x)[i]; }
  T opIndex(size_t i) const { return (&x)[i]; }

  vec2 opBinary(string op : "+")(in vec2 v) const { return vec2(x + v.x, y + v.y); }
  vec2 opBinary(string op : "-")(in vec2 v) const { return vec2(x - v.x, y - v.y); }
  vec2 opBinary(string op : "*")(T f) const { return vec2(x * f, y * f); }
  vec2 opBinary(string op : "/")(T f) const { return vec2(x / f, y / f); }
  T opBinary(string op : "*")(in vec2 v) const { return dot(v); }
  vec2 opUnary(string op : "-")() const { return vec2(-x, -y); }

  ref vec2 opOpAssign(string op : "+")(in vec2 v) { x += v.x; y += v.y; return this; }
  ref vec2 opOpAssign(string op : "-")(in vec2 v) { x -= v.x; y -= v.y; return this; }
  ref vec2 opOpAssign(string op : "*")(T f) { x *= f; y *= f; return this; }
  ref vec2 opOpAssign(string op : "/")(T f) { x /= f; y /= f; return this; }

  T dot(in vec2 v) const { return x * v.x + y * v.y; }

  T lengthsq() const { return x * x + y * y; }
  T length() const { return cast(T) sqrt(cast(double) lengthsq()); }

  void normalize()
  {
    T len = length();
    if (len) {
      x /= len;
      y /= len;
    } else {
      this = vec2(cast(T) 1, cast(T) 0);
    }
  }

  static vec2 zero() { return vec2(0, 0); }

  static vec2 rand()
  {
    vec2 ret;
    do {
      ret = vec2(cast(T) 2 * cast(T) .rand() / cast(T) RAND_MAX - cast(T) 1,
                 cast(T) 2 * cast(T) .rand() / cast(T) RAND_MAX - cast(T) 1);
    } while (ret.lengthsq() > cast(T) 1);
    return ret;
  }
}

struct vec3(T)
{
  T x = 0, y = 0, z = 0;

  this(T _x, T _y, T _z) { x = _x; y = _y; z = _z; }
  this(const(T)* vecptr) { x = vecptr[0]; y = vecptr[1]; z = vecptr[2]; }

  ref T opIndex(size_t i) return { return (&x)[i]; }
  T opIndex(size_t i) const { return (&x)[i]; }

  vec3 opBinary(string op : "+")(in vec3 v) const { return vec3(x + v.x, y + v.y, z + v.z); }
  vec3 opBinary(string op : "-")(in vec3 v) const { return vec3(x - v.x, y - v.y, z - v.z); }
  vec3 opBinary(string op : "*")(T f) const { return vec3(x * f, y * f, z * f); }
  vec3 opBinary(string op : "/")(T divisor) const
  {
    // the original uses `float` for the factor regardless of T
    float factor = divisor != cast(T) 0 ? cast(T) 1 / divisor : cast(T) 0;
    return vec3(x * factor, y * factor, z * factor);
  }
  T opBinary(string op : "*")(in vec3 v) const { return dot(v); }
  vec3 opBinary(string op : "^")(in vec3 v) const { return cross(v); }
  vec3 opBinaryRight(string op : "*")(T f) const { return this * f; }
  vec3 opUnary(string op : "-")() const { return vec3(-x, -y, -z); }

  ref vec3 opOpAssign(string op : "+")(in vec3 v) { this = this + v; return this; }
  ref vec3 opOpAssign(string op : "-")(in vec3 v) { this = this - v; return this; }
  ref vec3 opOpAssign(string op : "*")(T f) { this = this * f; return this; }
  ref vec3 opOpAssign(string op : "/")(T f) { this = this / f; return this; }

  T dot(in vec3 v) const { return x * v.x + y * v.y + z * v.z; }

  vec3 cross(in vec3 v) const { return vec3(y * v.z - z * v.y, z * v.x - x * v.z, x * v.y - y * v.x); }

  vec3 modulate(in vec3 v) const { return vec3(x * v.x, y * v.y, z * v.z); }

  T lengthsq() const { return x * x + y * y + z * z; }
  T length() const { return cast(T) sqrt(cast(double) lengthsq()); }

  void normalize()
  {
    T len = length();
    if (len) {
      len = cast(T) 1 / len;
      x *= len;
      y *= len;
      z *= len;
    } else {
      this = vec3(cast(T) 0, cast(T) 0, cast(T) 1);
    }
  }

  void copyTo(T* dest) const { dest[0] = x; dest[1] = y; dest[2] = z; }
  void copyFrom(const(T)* src) { x = src[0]; y = src[1]; z = src[2]; }

  static vec3 zero() { return vec3(0, 0, 0); }

  static vec3 rand()
  {
    vec3 ret;
    do {
      ret = vec3(cast(T) 2 * cast(T) .rand() / cast(T) RAND_MAX - cast(T) 1,
                 cast(T) 2 * cast(T) .rand() / cast(T) RAND_MAX - cast(T) 1,
                 cast(T) 2 * cast(T) .rand() / cast(T) RAND_MAX - cast(T) 1);
    } while (ret.lengthsq() > cast(T) 1);
    return ret;
  }
}

struct vec4(T)
{
  T x = 0, y = 0, z = 0, w = 0;

  this(T _x, T _y, T _z, T _w) { x = _x; y = _y; z = _z; w = _w; }
  this(in vec3!T v) { x = v.x; y = v.y; z = v.z; w = 0; }
  this(in vec3!T v, T _w) { x = v.x; y = v.y; z = v.z; w = _w; }

  ref T opIndex(size_t i) return { return (&x)[i]; }
  T opIndex(size_t i) const { return (&x)[i]; }

  vec4 opBinary(string op : "+")(in vec4 v) const { return vec4(x + v.x, y + v.y, z + v.z, w + v.w); }
  vec4 opBinary(string op : "-")(in vec4 v) const { return vec4(x - v.x, y - v.y, z - v.z, w - v.w); }
  vec4 opBinary(string op : "*")(T f) const { return vec4(x * f, y * f, z * f, w * f); }
  T opBinary(string op : "*")(in vec4 v) const { return dot(v); }

  ref vec4 opOpAssign(string op : "+")(in vec4 v) { this = this + v; return this; }
  ref vec4 opOpAssign(string op : "-")(in vec4 v) { this = this - v; return this; }
  ref vec4 opOpAssign(string op : "*")(T f) { this = this * f; return this; }

  T dot(in vec4 v) const { return x * v.x + y * v.y + z * v.z + w * v.w; }

  T lengthsq() const { return x * x + y * y + z * z + w * w; }
  T length() const { return cast(T) sqrt(cast(double) lengthsq()); }

  void normalize3a()
  {
    T len = cast(T) sqrt(cast(double)(x * x + y * y + z * z));
    if (len) {
      len = cast(T) 1 / len;
      x *= len;
      y *= len;
      z *= len;
      w *= len;
    } else {
      this = vec4(cast(T) 0, cast(T) 0, cast(T) 1, cast(T) 0);
    }
  }

  void normalize3b()
  {
    if (w) {
      T len = cast(T) 1 / w;
      x *= len;
      y *= len;
      z *= len;
      w = cast(T) 1;
    } else {
      this = vec4(cast(T) 0, cast(T) 0, cast(T) 0, cast(T) 1);
    }
  }

  void normalize3c()
  {
    T len = cast(T) sqrt(cast(double)(x * x + y * y + z * z));
    if (len) {
      len = cast(T) 1 / len;
      x *= len;
      y *= len;
      z *= len;
    } else {
      x = cast(T) 0;
      y = cast(T) 0;
      z = cast(T) 1;
    }
  }

  void normalize4()
  {
    T len = length();
    if (len) {
      len = cast(T) 1 / len;
      x *= len;
      y *= len;
      z *= len;
      w *= len;
    } else {
      this = vec4(cast(T) 0, cast(T) 0, cast(T) 0, cast(T) 1);
    }
  }

  void copyTo(T* dest) const { dest[0] = x; dest[1] = y; dest[2] = z; dest[3] = w; }
  void copyFrom(const(T)* src) { x = src[0]; y = src[1]; z = src[2]; w = src[3]; }
}

struct ray(T)
{
  vec3!T start;
  vec3!T direction;

  this(in vec3!T _start, in vec3!T _direction) { start = _start; direction = _direction; }

  void fromTwoPoints(in vec3!T _start, in vec3!T _pt)
  {
    start = _start;
    direction = _pt - _start;
  }

  vec3!T getPt(T lambda) const { return start + direction * lambda; }

  bool getSphereIntersection(in vec3!T center, T radius, ref T outLambda) const
  {
    vec3!T temp = start - center;

    T a = direction.lengthsq(),
      b = 2.0 * (direction * temp),
      c = temp.lengthsq() - radius * radius,
      determinant = b * b - cast(T) 4 * a * c;

    if (determinant < cast(T) 0) return false;

    T rootdet = cast(T) sqrt(cast(double) determinant),
      t = (-b - rootdet) / (cast(T) 2 * a);

    outLambda = t;
    return true;
  }
}

/// A plane of form (x,y,z) . normal + offset = 0
struct plane(T)
{
  vec3!T normal;
  T offset = 0;

  this(in vec3!T _normal, T _offset) { normal = _normal; offset = _offset; }
  this(T _a, T _b, T _c, T _d) { normal = vec3!T(_a, _b, _c); offset = _d; }

  void normalize()
  {
    T len = normal.length();
    if (len) {
      len = cast(T) 1 / len;
      normal *= len;
      offset *= len;
    }
  }
}

struct mat44(T)
{
  vec4!T[4] row = [vec4!T(1, 0, 0, 0), vec4!T(0, 1, 0, 0), vec4!T(0, 0, 1, 0), vec4!T(0, 0, 0, 1)];

  ref T opIndex(size_t i) return { return row[0][i]; }
  T opIndex(size_t i) const { return row[0][i]; }

  ref mat44 assemble(in vec4!T r0, in vec4!T r1, in vec4!T r2, in vec4!T r3)
  {
    row[0] = r0; row[1] = r1; row[2] = r2; row[3] = r3;
    return this;
  }

  ref mat44 assemble(in vec3!T r0, in vec3!T r1, in vec3!T r2)
  {
    row[0] = vec4!T(r0.x, r0.y, r0.z, cast(T) 0);
    row[1] = vec4!T(r1.x, r1.y, r1.z, cast(T) 0);
    row[2] = vec4!T(r2.x, r2.y, r2.z, cast(T) 0);
    row[3] = vec4!T(cast(T) 0, cast(T) 0, cast(T) 0, cast(T) 1);
    return this;
  }

  mat44 concatenate(in mat44 mat) const
  {
    mat44 ret;
    foreach (i; 0 .. 4)
      foreach (j; 0 .. 4) {
        ret.row[i][j] = row[i][0] * mat.row[0][j] + row[i][1] * mat.row[1][j] +
                        row[i][2] * mat.row[2][j] + row[i][3] * mat.row[3][j];
      }
    return ret;
  }

  mat44 concatenateReverse(in mat44 mat) const { return mat.concatenate(this); }

  mat44 transpose() const
  {
    mat44 ret;
    ret.row[0] = vec4!T(row[0].x, row[1].x, row[2].x, row[3].x);
    ret.row[1] = vec4!T(row[0].y, row[1].y, row[2].y, row[3].y);
    ret.row[2] = vec4!T(row[0].z, row[1].z, row[2].z, row[3].z);
    ret.row[3] = vec4!T(row[0].w, row[1].w, row[2].w, row[3].w);
    return ret;
  }

  ref mat44 translate(in vec3!T vec)
  {
    row[0].w += vec.x;
    row[1].w += vec.y;
    row[2].w += vec.z;
    return this;
  }

  vec3!T transform1(in vec3!T vec) const
  {
    return vec3!T(
      row[0].x * vec.x + row[0].y * vec.y + row[0].z * vec.z + row[0].w,
      row[1].x * vec.x + row[1].y * vec.y + row[1].z * vec.z + row[1].w,
      row[2].x * vec.x + row[2].y * vec.y + row[2].z * vec.z + row[2].w
    );
  }

  vec4!T transform1(in vec4!T vec) const
  {
    return vec4!T(
      row[0].x * vec.x + row[0].y * vec.y + row[0].z * vec.z + row[0].w * vec.w,
      row[1].x * vec.x + row[1].y * vec.y + row[1].z * vec.z + row[1].w * vec.w,
      row[2].x * vec.x + row[2].y * vec.y + row[2].z * vec.z + row[2].w * vec.w,
      row[3].x * vec.x + row[3].y * vec.y + row[3].z * vec.z + row[3].w * vec.w
    );
  }

  vec3!T transform2(in vec3!T vec) const
  {
    return vec3!T(
      row[0].x * vec.x + row[1].x * vec.y + row[2].x * vec.z + row[3].x,
      row[0].y * vec.x + row[1].y * vec.y + row[2].y * vec.z + row[3].y,
      row[0].z * vec.x + row[1].z * vec.y + row[2].z * vec.z + row[3].z
    );
  }

  vec4!T transform2(in vec4!T vec) const
  {
    return vec4!T(
      row[0].x * vec.x + row[1].x * vec.y + row[2].x * vec.z + row[3].x * vec.w,
      row[0].y * vec.x + row[1].y * vec.y + row[2].y * vec.z + row[3].y * vec.w,
      row[0].z * vec.x + row[1].z * vec.y + row[2].z * vec.z + row[3].z * vec.w,
      row[0].w * vec.x + row[1].w * vec.y + row[2].w * vec.z + row[3].w * vec.w
    );
  }

  vec3!T transformNormal(in vec3!T vec) const
  {
    return vec3!T(
      row[0].x * vec.x + row[0].y * vec.y + row[0].z * vec.z,
      row[1].x * vec.x + row[1].y * vec.y + row[1].z * vec.z,
      row[2].x * vec.x + row[2].y * vec.y + row[2].z * vec.z
    );
  }

  static mat44 identity() { return mat44.init; }
}

struct quat(T)
{
  T x = 0, y = 0, z = 0, w = 0;

  this(T _x, T _y, T _z, T _w) { x = _x; y = _y; z = _z; w = _w; }

  quat opBinary(string op : "+")(in quat q) const { return quat(x + q.x, y + q.y, z + q.z, w + q.w); }
  quat opBinary(string op : "-")(in quat q) const { return quat(x - q.x, y - q.y, z - q.z, w - q.w); }
  quat opBinary(string op : "*")(T val) const { return quat(x * val, y * val, z * val, w * val); }
  quat opBinary(string op : "/")(T val) const
  {
    T mult = cast(T) 1 / val;
    return quat(x * mult, y * mult, z * mult, w * mult);
  }

  quat opBinary(string op : "*")(in quat q) const
  {
    return quat(
      w * q.x + x * q.w + y * q.z - z * q.y,
      w * q.y - x * q.z + y * q.w + z * q.x,
      w * q.z + x * q.y - y * q.x + z * q.w,
      w * q.w - x * q.x - y * q.y - z * q.z);
  }

  ref quat opOpAssign(string op : "+")(in quat q)
  {
    this = this + q;
    return this;
  }

  float dot(in quat q) const
  {
    return x * q.x + y * q.y + z * q.z + w * q.w;
  }

  void fromAxisAngle(in vec3!T axis, T angle)
  {
    T len = axis.length();
    if (len > cast(T) 0) {
      T sinA = cast(T) sin(cast(double)(angle / cast(T) 2)) / len;
      x = sinA * axis.x;
      y = sinA * axis.y;
      z = sinA * axis.z;
      w = cast(T) cos(cast(double)(angle / cast(T) 2));
    } else {
      this = identity();
    }
  }

  void fromXAngle(T angle)
  {
    x = cast(T) sin(cast(double)(angle / cast(T) 2));
    y = z = cast(T) 0;
    w = cast(T) cos(cast(double)(angle / cast(T) 2));
  }

  void fromYAngle(T angle)
  {
    y = cast(T) sin(cast(double)(angle / cast(T) 2));
    x = z = cast(T) 0;
    w = cast(T) cos(cast(double)(angle / cast(T) 2));
  }

  void fromZAngle(T angle)
  {
    z = cast(T) sin(cast(double)(angle / cast(T) 2));
    x = y = cast(T) 0;
    w = cast(T) cos(cast(double)(angle / cast(T) 2));
  }

  void fromThreeAxisAngle(in vec3!T vec)
  {
    quat temp;
    fromXAngle(vec.x);
    temp.fromYAngle(vec.y);
    this = this * temp;
    temp.fromZAngle(vec.z);
    this = this * temp;
  }

  void normalize()
  {
    T len = x * x + y * y + z * z + w * w;
    if (len > cast(T) 0) {
      len = cast(T) 1 / cast(T) sqrt(cast(double) len);
      x *= len;
      y *= len;
      z *= len;
      w *= len;
    } else {
      this = identity();
    }
  }

  mat44!T getMatrix() const
  {
    T norm = x * x + y * y + z * z + w * w,
      s = (norm > cast(T) 0) ? cast(T) 2 / norm : cast(T) 0,

      xx = x * x * s,
      yy = y * y * s,
      zz = z * z * s,
      xy = x * y * s,
      xz = x * z * s,
      yz = y * z * s,
      wx = w * x * s,
      wy = w * y * s,
      wz = w * z * s;

    mat44!T m;
    m.assemble(
      vec3!T(cast(T) 1 - (yy + zz), xy + wz, xz - wy),
      vec3!T(xy - wz, cast(T) 1 - (xx + zz), yz + wx),
      vec3!T(xz + wy, yz - wx, cast(T) 1 - (xx + yy)));

    return m;
  }

  static quat identity() { return quat(0, 0, 0, 1); }

  static quat rand()
  {
    quat ret;
    float lengthsq;
    do {
      ret = quat(cast(T) 2 * cast(T) .rand() / cast(T) RAND_MAX - cast(T) 1,
                 cast(T) 2 * cast(T) .rand() / cast(T) RAND_MAX - cast(T) 1,
                 cast(T) 2 * cast(T) .rand() / cast(T) RAND_MAX - cast(T) 1,
                 cast(T) 2 * cast(T) .rand() / cast(T) RAND_MAX - cast(T) 1);
      lengthsq = ret.x * ret.x + ret.y * ret.y + ret.z * ret.z + ret.w * ret.w;
    } while (lengthsq > cast(T) 1 || lengthsq <= cast(T) 0);
    float mult = cast(T) 1 / cast(T) sqrt(cast(double) lengthsq);
    ret.x *= mult; ret.y *= mult; ret.z *= mult; ret.w *= mult;
    return ret;
  }
}

struct frustum(T)
{
  enum {
    SideRight,
    SideLeft,
    SideTop,
    SideBottom,
    SideNear,
    SideFar,
    SideCount
  }

  plane!T[SideCount] side;

  this(in mat44!T mat) { construct(mat); }

  ref frustum construct(in mat44!T mat)
  {
    side[SideRight] = plane!T(
      mat.row[0][3] - mat.row[0][0],
      mat.row[1][3] - mat.row[1][0],
      mat.row[2][3] - mat.row[2][0],
      mat.row[3][3] - mat.row[3][0]);
    side[SideRight].normalize();

    side[SideLeft] = plane!T(
      mat.row[0][3] + mat.row[0][0],
      mat.row[1][3] + mat.row[1][0],
      mat.row[2][3] + mat.row[2][0],
      mat.row[3][3] + mat.row[3][0]);
    side[SideLeft].normalize();

    side[SideTop] = plane!T(
      mat.row[0][3] - mat.row[0][1],
      mat.row[1][3] - mat.row[1][1],
      mat.row[2][3] - mat.row[2][1],
      mat.row[3][3] - mat.row[3][1]);
    side[SideTop].normalize();

    side[SideBottom] = plane!T(
      mat.row[0][3] + mat.row[0][1],
      mat.row[1][3] + mat.row[1][1],
      mat.row[2][3] + mat.row[2][1],
      mat.row[3][3] + mat.row[3][1]);
    side[SideBottom].normalize();

    side[SideNear] = plane!T(
      mat.row[0][3] - mat.row[0][2],
      mat.row[1][3] - mat.row[1][2],
      mat.row[2][3] - mat.row[2][2],
      mat.row[3][3] - mat.row[3][2]);
    side[SideNear].normalize();

    side[SideFar] = plane!T(
      mat.row[0][3] + mat.row[0][2],
      mat.row[1][3] + mat.row[1][2],
      mat.row[2][3] + mat.row[2][2],
      mat.row[3][3] + mat.row[3][2]);
    side[SideFar].normalize();

    return this;
  }

  bool isAABBOutside(in vec3!T mins, in vec3!T maxs) const
  {
    vec3!T[8] pts = [
      vec3!T(mins.x, mins.y, mins.z),
      vec3!T(maxs.x, mins.y, mins.z),
      vec3!T(mins.x, maxs.y, mins.z),
      vec3!T(maxs.x, maxs.y, mins.z),
      vec3!T(mins.x, mins.y, maxs.z),
      vec3!T(maxs.x, mins.y, maxs.z),
      vec3!T(mins.x, maxs.y, maxs.z),
      vec3!T(maxs.x, maxs.y, maxs.z)
    ];
    for (int s = 0; s < 1; ++s) {
      bool outside = true;
      for (int p = 0; p < 8; ++p) {
        if (side[s].normal * pts[p] >= 0.0) {
          outside = false;
          break;
        }
      }
      if (outside) return true;
    }

    return false;
  }
}

alias vec2f = vec2!float;
alias vec2d = vec2!double;
alias vec2i = vec2!int;

alias vec3f = vec3!float;
alias vec3d = vec3!double;
alias vec3i = vec3!int;

alias vec4f = vec4!float;
alias vec4d = vec4!double;
alias vec4i = vec4!int;

alias quatf = quat!float;
alias quatd = quat!double;

alias rayf = ray!float;
alias rayd = ray!double;

alias planef = plane!float;
alias planed = plane!double;

alias mat44f = mat44!float;
alias mat44d = mat44!double;

alias frustumf = frustum!float;
alias frustumd = frustum!double;

vec2f makevec2f(V)(in V v) { return vec2f(v.x, v.y); }
vec3f makevec3f(V)(in V v) { return vec3f(v.x, v.y, v.z); }
vec4f makevec4f(V)(in V v) { return vec4f(v.x, v.y, v.z, v.w); }
vec4d makevec4d(V)(in V v) { return vec4d(v.x, v.y, v.z, v.w); }

T intersect_plane_ray(T)(in plane!T pln, in vec3!T linept, in vec3!T linedir)
{
  T denom = pln.normal * linedir;
  if (denom) {
    return -(pln.normal * linept + pln.offset) / denom;
  } else {
    return cast(T) 0;
  }
}
