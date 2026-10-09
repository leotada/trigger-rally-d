// psim [psim]
// D port of psim.h, sim.cpp and rigidbody.cpp. License: GPL version 2
module psim.psim;

import pengine.model : PSSModel;
import pengine.subsys;
import pengine.terrain : PTerrain;
import pengine.util;
import pengine.vmath;
import pengine.xml;
import pengine.cutil;
import psim.vehicle;

/// Reference oriented point (stores coordinates and orientation).
class PReferenceFrame
{
  private vec3f pos;
  private quatf ori;
  private mat44f ori_mat, ori_mat_inv;

  this()
  {
    pos = vec3f.zero();
    ori = quatf.identity();
    updateMatrices();
  }

  /// Copies position, orientation and matrices from another frame (C++ value copy).
  void copyFrom(const PReferenceFrame o)
  {
    pos = o.pos;
    ori = o.ori;
    ori_mat = o.ori_mat;
    ori_mat_inv = o.ori_mat_inv;
  }

  void updateMatrices()
  {
    ori.normalize();
    ori_mat = ori.getMatrix();
    ori_mat_inv = ori_mat.transpose();
  }

  void setPosition(in vec3f _pos) { pos = _pos; }
  vec3f getPosition() const { return pos; }

  void setOrientation(in quatf _ori) { ori = _ori; }
  quatf getOrientation() const { return ori; }
  mat44f getOrientationMatrix() const { return ori_mat; }
  mat44f getInverseOrientationMatrix() const { return ori_mat_inv; }

  vec3f getLocToWorldVector(in vec3f pt) { return ori_mat.transform1(pt); }
  vec3f getWorldToLocVector(in vec3f pt) { return ori_mat.transform2(pt); }
  vec3f getLocToWorldPoint(in vec3f pt) { return pos + ori_mat.transform1(pt); }
  vec3f getWorldToLocPoint(in vec3f pt) { return ori_mat.transform2(pt - pos); }
}

/// A rigid body with mass, position, velocity, and angular mass, position, and velocity
class PRigidBody : PReferenceFrame
{
  private const(vec3f)* gravity;
  private float mass = 1.0, mass_inv = 1.0;
  private vec3f angmass, angmass_inv;
  private vec3f linvel, angvel;
  private vec3f accum_force, accum_torque;

  this(const(vec3f)* gravity_parent)
  {
    super();
    gravity = gravity_parent;
    angmass = vec3f(1.0, 1.0, 1.0);
    angmass_inv = vec3f(1.0, 1.0, 1.0);
    linvel = vec3f.zero();
    angvel = vec3f.zero();
    accum_force = vec3f.zero();
    accum_torque = vec3f.zero();
  }

  void setMassCuboid(float _mass, in vec3f rad)
  {
    if (mass <= 0.0 || rad.x <= 0.0 || rad.y <= 0.0 || rad.z <= 0.0) return;

    mass = _mass;
    mass_inv = 1.0 / mass;

    angmass = vec3f(rad.y * rad.z, rad.z * rad.x, rad.x * rad.y) * (mass * 0.4);

    angmass_inv.x = 1.0 / angmass.x;
    angmass_inv.y = 1.0 / angmass.y;
    angmass_inv.z = 1.0 / angmass.z;
  }

  void setLinearVel(in vec3f vel) { linvel = vel; }
  vec3f getLinearVel() { return linvel; }

  void setAngularVel(in vec3f vel) { angvel = vel; }
  vec3f getAngularVel() { return angvel; }

  void addForce(in vec3f frc) { accum_force += frc; }
  void addLocForce(in vec3f frc) { addForce(getLocToWorldVector(frc)); }

  void addForceAtPoint(in vec3f frc, in vec3f pt)
  {
    accum_force += frc;
    vec3f wdiff = pt - getPosition();
    accum_torque += frc ^ wdiff;
  }

  void addLocForceAtPoint(in vec3f frc, in vec3f pt) { addForceAtPoint(getLocToWorldVector(frc), pt); }
  void addForceAtLocPoint(in vec3f frc, in vec3f pt) { addForceAtPoint(frc, getLocToWorldPoint(pt)); }
  void addLocForceAtLocPoint(in vec3f frc, in vec3f pt)
  {
    addForceAtPoint(getLocToWorldVector(frc), getLocToWorldPoint(pt));
  }

  void addTorque(in vec3f trq) { accum_torque += trq; }
  void addLocTorque(in vec3f trq) { addTorque(getLocToWorldVector(trq)); }

  vec3f getLinearVelAtPoint(in vec3f pt)
  {
    vec3f usept = pt - getPosition();
    return linvel + (usept ^ angvel);
  }

  vec3f getLinearVelAtLocPoint(in vec3f pt) { return getLinearVelAtPoint(getLocToWorldPoint(pt)); }

  /// Apply forces and torque accumulated, update the body accordingly
  void tick(float delta)
  {
    linvel += (accum_force * mass_inv + *gravity) * delta;

    setPosition(getPosition() + linvel * delta);

    vec3f angmass_inv_world = angmass_inv;

    vec3f ang_accel = vec3f(
      accum_torque.x * angmass_inv_world.x,
      accum_torque.y * angmass_inv_world.y,
      accum_torque.z * angmass_inv_world.z);

    angvel += ang_accel * delta;

    quatf angdelta;
    angdelta.fromThreeAxisAngle(angvel * delta);
    setOrientation(getOrientation() * angdelta);

    accum_force = vec3f.zero();
    accum_torque = vec3f.zero();

    updateMatrices();
  }
}

private __gshared float simTimeAccum = 0;

/// Information about a physic simulation instance
class PSim
{
  private PTerrain terrain;
  private PResourceList!PVehicleType vtypelist;
  private PRigidBody[] body_;
  private PVehicle[] vehicle;
  private vec3f gravity;

  this()
  {
    terrain = null;
    gravity = vec3f.zero();
  }

  void setTerrain(PTerrain new_terrain) { terrain = new_terrain; }
  PTerrain getTerrain() { return terrain; }

  void setGravity(in vec3f new_gravity) { gravity = new_gravity; }

  PVehicleType loadVehicleType(string filename, PSSModel ssModel)
  {
    PVehicleType vtype = vtypelist.find(filename);
    if (vtype is null) {
      vtype = new PVehicleType();
      if (!vtype.load(filename, ssModel)) {
        if (PUtil.isDebugLevel(DEBUGLEVEL_ENDUSER))
          PUtil.outLog("Failed to load ", filename);
        return null;
      }
      vtypelist.add(vtype);
    }
    return vtype;
  }

  PRigidBody createRigidBody()
  {
    PRigidBody newbody = new PRigidBody(&gravity);
    body_ ~= newbody;
    return newbody;
  }

  PVehicle createVehicle(XMLElement element, string filepath, PSSModel ssModel)
  {
    string type = element.Attribute("type");
    if (type is null) {
      PUtil.outLog("Vehicle has no type");
      return null;
    }

    vec3f pos = vec3f.zero();

    string val = element.Attribute("pos");
    if (val !is null) sscanf(val, "%f , %f , %f", &pos.x, &pos.y, &pos.z);

    quatf ori = quatf.identity();

    val = element.Attribute("ori");
    if (val !is null) sscanf(val, "%f , %f , %f , %f", &ori.w, &ori.x, &ori.y, &ori.z);

    return createVehicle(type, pos, ori, filepath, ssModel);
  }

  PVehicle createVehicle(string type, in vec3f pos, in quatf ori, string filepath, PSSModel ssModel)
  {
    PVehicleType vtype = loadVehicleType(PUtil.assemblePath(type, filepath), ssModel);
    return createVehicle(vtype, pos, ori);
  }

  PVehicle createVehicle(PVehicleType type, in vec3f pos, in quatf ori)
  {
    if (type is null) return null;

    PVehicle newvehicle = new PVehicle(this, type);

    vec3f vpos = pos;
    if (terrain !is null) vpos.z += terrain.getHeight(vpos.x, vpos.y);
    newvehicle.getBody().setPosition(vpos);

    newvehicle.getBody().setOrientation(ori);
    newvehicle.getBody().updateMatrices();

    newvehicle.updateParts();

    vehicle ~= newvehicle;
    return newvehicle;
  }

  /// Clear from the simulation any rigid body, vehicle and vehicle types
  void clear()
  {
    body_ = null;
    vehicle = null;
    vtypelist.clear();
  }

  void tick(float delta)
  {
    if (delta <= 0.0) return;

    // size of a step
    const float timeslice = 0.004;

    simTimeAccum += delta;

    while (simTimeAccum >= timeslice) {
      simTimeAccum -= timeslice;

      foreach (v; vehicle)
        v.tick(timeslice);

      foreach (b; body_)
        b.tick(timeslice);

      foreach (v; vehicle)
        v.updateParts();
    }
  }
}
