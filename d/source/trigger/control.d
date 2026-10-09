// control [trigger]
//
// Controls menu.
module trigger.control;

import std.ascii : isASCII, toLower;
import std.string : fromStringz;

import bindings.sdl2;
import pengine.config;
import pengine.render;
import trigger.menu;

final class PControl
{
  private struct Control {
    PConfig.Action action;
    string text;
  }

  private Gui parent;
  private PConfig cfg;
  private int pos;
  private int activepos;
  private Control[] controls;

  this(Gui parent, PConfig config)
  {
    this.parent = parent;
    cfg = config;
    pos = 0;
    activepos = -1;

    controls ~= Control(PConfig.Action.ActionForward, "forward");
    controls ~= Control(PConfig.Action.ActionBack, "back");
    controls ~= Control(PConfig.Action.ActionLeft, "left");
    controls ~= Control(PConfig.Action.ActionRight, "right");
    controls ~= Control(PConfig.Action.ActionHandbrake, "handbrake");
    controls ~= Control(PConfig.Action.ActionDownshift, "downshift");
    controls ~= Control(PConfig.Action.ActionUpshift, "upshift");
    controls ~= Control(PConfig.Action.ActionRecover, "reset car");
    controls ~= Control(PConfig.Action.ActionRecoverAtCheckpoint, "reset on road");
    controls ~= Control(PConfig.Action.ActionCamMode, "toggle camera");
    controls ~= Control(PConfig.Action.ActionCamRight, "view right");
    controls ~= Control(PConfig.Action.ActionCamLeft, "view left");
    controls ~= Control(PConfig.Action.ActionShowMap, "show map");
    controls ~= Control(PConfig.Action.ActionPauseRace, "pause race");
    controls ~= Control(PConfig.Action.ActionShowUi, "show UI");
    controls ~= Control(PConfig.Action.ActionShowCheckpoint, "show checkpoints");
  }

  void render()
  {
    pos = 0;
    parent.makeClickable(
      parent.addLabel(10.0f, 10.0f, "back", PTEXT_HZA_LEFT | PTEXT_VTA_BOTTOM, 40.0f),
      AA_RELOAD_ALL, 0);
    parent.addLabel(80.0f, 520.0f, "Controls", PTEXT_HZA_LEFT | PTEXT_VTA_CENTER, 30.0f, LabelStyle.Header);
    parent.addLabel(340.0f, 520.0f, "keyboard keys", PTEXT_HZA_LEFT | PTEXT_VTA_CENTER, 22.0f, LabelStyle.Weak);
    parent.addGraphic(330.0f, 70.0f, 380.0f, 430.0f, null, GraphicStyle.Image);

    foreach (i, ref c; controls)
      addControl(c, cast(int) i == activepos);
  }

  void select(int index)
  {
    if (activepos == index)
      activepos = -1;
    else
      activepos = index;
  }

  bool handleKey(in SDL_KeyboardEvent ke)
  {
    if (activepos >= 0 && activepos < cast(int) controls.length) {
      if (ke.keysym.sym != SDLK_ESCAPE) {
        unassignKey(ke.keysym.sym);
        cfg.getCtrl().map[controls[activepos].action].type = PConfig.UserControl.Type.TypeKey;
        cfg.getCtrl().map[controls[activepos].action].key.sym = ke.keysym.sym;
      }
      activepos = -1;
      return true;
    }
    return false;
  }

  private void addControl(ref Control control, bool active)
  {
    string keyname = "PRESS KEY";

    if (!active) {
      SDL_Keycode keycode = cfg.getCtrl().map[control.action].key.sym;

      keyname = fromStringz(SDL_GetKeyName(keycode)).idup;
      if (keycode == SDLK_UNKNOWN || keyname == "" || !isASCII(keyname[0]))
        keyname = "NOT ASSIGNED";
      else {
        char[] k = keyname.dup;
        foreach (ref ch; k) ch = cast(char) toLower(ch);
        keyname = k.idup;
      }
    }

    parent.addLabel(80.0f, 490.0f - cast(float) pos * 26.0f,
                    control.text, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 22.0f, LabelStyle.Regular);
    parent.makeClickable(
      parent.addLabel(340.0f, 490.0f - cast(float) pos * 26.0f, keyname,
                      PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 22.0f, LabelStyle.Regular),
      AA_PICK_CTRL, pos);
    ++pos;
  }

  private void unassignKey(SDL_Keycode keycode)
  {
    foreach (ref control; controls) {
      if (cfg.getCtrl().map[control.action].key.sym == keycode) {
        cfg.getCtrl().map[control.action].type = PConfig.UserControl.Type.TypeUnassigned;
        cfg.getCtrl().map[control.action].key.sym = SDLK_UNKNOWN;
      }
    }
  }
}
