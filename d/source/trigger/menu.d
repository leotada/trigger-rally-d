// menu [trigger]
//
// Copyright 2004-2006 Jasmine Langridge, jas@jareiko.net
// License: GPL version 2 (see included gpl.txt)
//
// GUI implementation of the menus (the level progress logic lives in mainapp.d).
module trigger.menu;

import std.math : sin, fmod;

import bindings.gl;
import pengine.cutil;
import pengine.render;
import pengine.texture;
import pengine.util;
import pengine.vmath;
import pengine.xml;

// menus
enum AM_TOP = 21;
enum AM_TOP_EVT = 22;
enum AM_TOP_EVT_PREP = 23;
enum AM_TOP_EVT_ABANDON = 24;
enum AM_TOP_PRAC = 25;
enum AM_TOP_PRAC_SEL = 26;
enum AM_TOP_PRAC_SEL_PREP = 27;
enum AM_TOP_LVL = 28;
enum AM_TOP_LVL_PREP = 29;
enum AM_TOP_QUIT = 30;
enum AM_TOP_LVL_TIMES = 31;
enum AM_TOP_PRAC_TIMES = 32;
enum AM_TOP_LVL_BTIMES = 33;
enum AM_TOP_PRAC_BTIMES = 34;
enum AM_TOP_OPT = 40;
enum AM_TOP_CTRL = 41;

// actions
enum AA_INIT = 1;
enum AA_RESUME = 2;
enum AA_GO_TOP = 11;
enum AA_GO_EVT = 21;
enum AA_PICK_EVT = 22;
enum AA_START_EVT = 23;
enum AA_RESUME_EVT = 24;
enum AA_RESTART_EVT = 25;
enum AA_GO_PRAC = 31;
enum AA_PICK_PRAC = 32;
enum AA_PICK_PRAC_LVL = 33;
enum AA_START_PRAC = 34;
enum AA_GO_LVL = 41;
enum AA_PICK_LVL = 42;
enum AA_START_LVL = 43;
enum AA_GO_QUIT = 51;
enum AA_QUIT_CONFIRM = 52;
enum AA_SHOWTIMES_LVL = 61;
enum AA_SHOWTIMES_PRAC = 62;
enum AA_BSHOWTIMES_LVL = 63;
enum AA_BSHOWTIMES_PRAC = 64;
enum AA_GO_OPT = 70;
enum AA_PICK_OPT = 71;
enum AA_RELOAD_ALL = 72;
enum AA_GO_CTRL = 73;
enum AA_PICK_CTRL = 74;

// best times table actions for columns
enum AA_SORT_BY_PLAYERNAME = 1001;
enum AA_SORT_BY_CARNAME = 1002;
enum AA_SORT_BY_CARCLASS = 1003;
enum AA_SORT_BY_TOTALTIME = 1004;

enum MAX_RACES_ON_SCREEN = 12;
enum MAX_TIMES_ON_SCREEN = 13;

/// used to determine which colors to use for the GuiWidget label
enum LabelStyle { Regular, Weak, Strong, Marked, Header, List }

/// used to determine which colors to use for the GuiWidget graphic
enum GraphicStyle { Button, Image }

struct GuiWidgetColors
{
  vec4f normal = vec4f(1, 0, 0, 1);
  vec4f click = vec4f(0, 1, 0, 1);
  vec4f hover = vec4f(0, 0, 1, 1);
  vec4f listnormal = vec4f(1, 1, 0, 1);
  vec4f listclick = vec4f(1, 0, 1, 1);
  vec4f listhover = vec4f(0, 1, 1, 1);
  vec4f weak = vec4f(0.5, 0.5, 0.5, 1);
  vec4f strong = vec4f(1, 1, 1, 1);
  vec4f marked = vec4f(1, 0.5, 0.5, 1);
  vec4f header = vec4f(0.8, 0.8, 0.4, 1);
  vec4f bnormal = vec4f(1, 1, 0, 0.75);
  vec4f bclick = vec4f(0, 1, 1, 0.75);
  vec4f bhover = vec4f(1, 1, 1, 1);
}

struct LevelState
{
  int state;

  int currentevent;
  int currentlevel;
  int currentplayer; // current player in the best times list

  int livesleft;
  float totaltime;

  float[] leveltimes;
}

enum GWT_FREE = 0;
enum GWT_CONTAINER = 10;
enum GWT_FILLER = 11;
enum GWT_LABEL = 12;
enum GWT_GRAPHIC = 13;

enum GWPARENT_NONE = -1;

struct GuiWidget
{
  int type;

  bool clickable;
  bool selectable;
  bool selected;
  int d1, d2;

  string text;
  float fontsize;

  vec2f dims_min, pos;

  vec4f colnormal = vec4f(1.00f, 1.00f, 1.00f, 0.85f);
  vec4f colclick = vec4f(0.65f, 1.00f, 0.65f, 0.85f);
  vec4f colhover = vec4f(1.00f, 0.40f, 0.00f, 1.00f);

  float glow = 0.0f;

  PTexture tex;

  this(int t) { type = t; }
}

final class Gui
{
  private GuiWidgetColors colors;
  private GuiWidget[] widget;
  private PSSRender ssRender;
  private vec2f cursor;
  private int highlight = -1, defwidget = -1;
  private float defflash = 0.0f;
  private PTexture fonttex;

  GuiWidgetColors getColors() const { return colors; }

  void setSSRender(PSSRender render) { ssRender = render; }
  void setFont(PTexture tex) { fonttex = tex; }

  void clear()
  {
    widget = null;
    highlight = -1;
    defwidget = -1;
  }

  /// Loads the widget colors from the specified filename.
  bool loadColors(string filename)
  {
    if (PUtil.isDebugLevel(DEBUGLEVEL_TEST))
      PUtil.outLog("Loading GUI colors from \"", filename, "\"");

    auto xmlfile = new XMLDocument();
    XMLElement rootelem = PUtil.loadRootElement(xmlfile, filename, "menucolors");

    if (rootelem is null)
      return false;

    bool r = true;

    void rd(string attr, ref vec4f c)
    {
      string val = rootelem.Attribute(attr);
      if (val !is null)
        sscanf(val, "%f, %f, %f, %f", &c.x, &c.y, &c.z, &c.w);
      else
        r = false;
    }

    rd("normal", colors.normal);
    rd("click", colors.click);
    rd("hover", colors.hover);
    rd("listnormal", colors.listnormal);
    rd("listclick", colors.listclick);
    rd("listhover", colors.listhover);
    rd("weak", colors.weak);
    rd("strong", colors.strong);
    rd("marked", colors.marked);
    rd("header", colors.header);
    rd("bnormal", colors.bnormal);
    rd("bclick", colors.bclick);
    rd("bhover", colors.bhover);

    return r;
  }

  void tick(float delta)
  {
    float decay = delta * 3.0f;

    // gradually unglow all widgets
    foreach (ref w; widget) {
      w.glow -= decay;
      CLAMP_LOWER(w.glow, 0.0f);
    }

    // keep the highlighted widget fully glowing
    if (highlight != -1) {
      widget[highlight].glow = 1.0f;
    }

    defflash = cast(float) fmod(cast(double)(defflash + delta * 50.0f), PI * 2.0);
  }

  void setCursorPos(float x, float y)
  {
    highlight = -1;

    foreach (i, ref w; widget) {
      if (!w.clickable) continue;

      if (x >= w.pos.x &&
          y >= w.pos.y &&
          x < w.pos.x + w.dims_min.x &&
          y < w.pos.y + w.dims_min.y)
        highlight = cast(int) i;
    }
  }

  bool getClickAction(out int data1, out int data2)
  {
    if (highlight == -1) return false;

    data1 = widget[highlight].d1;
    data2 = widget[highlight].d2;

    return true;
  }

  bool getDefaultAction(out int data1, out int data2)
  {
    if (defwidget == -1) return false;

    data1 = widget[defwidget].d1;
    data2 = widget[defwidget].d2;

    return true;
  }

  void doLayout() { }

  void render()
  {
    foreach (i, ref w; widget) {
      switch (w.type) {
        case GWT_LABEL: {
          vec4f colc;
          uint32 flags = PTEXT_HZA_LEFT | PTEXT_VTA_BOTTOM;

          if (w.selectable && !w.selected) {
            colc = INTERP(w.colnormal, w.colhover, w.glow);
          } else if (w.clickable) {
            colc = INTERP(w.colclick, w.colhover, w.glow);
          } else {
            colc = w.colnormal;
          }

          if (cast(int) i == defwidget)
            colc += vec4f(0.1f, -0.1f, -0.1f, 0.0f) * cast(float) sin(cast(double) defflash);

          if (w.selectable && w.selected)
            flags |= PTEXT_HIGHLIGHT;

          glPushMatrix();

          vec2f ctr = w.pos;
          glTranslatef(ctr.x, ctr.y, 0.0f);

          glScalef(w.fontsize, w.fontsize, 1.0f);

          fonttex.bind();

          glColor4fv(colc);
          ssRender.drawText(w.text, flags);
          glPopMatrix();
          break;
        }

        case GWT_GRAPHIC: {
          vec4f colc = vec4f(1.0f, 1.0f, 1.0f, 1.0f);

          // Work-around for drawing transparent background
          if (w.tex is null) {
            colc = vec4f(0.0f, 0.0f, 0.0f, 0.25f);
          } else if (w.clickable) {
            colc = INTERP(w.colclick, w.colhover, w.glow);
          } else {
            colc = w.colnormal;
          }

          vec2f min = w.pos;
          vec2f max = w.pos + w.dims_min;

          if (w.tex !is null)
            w.tex.bind();
          else
            glDisable(GL_TEXTURE_2D);

          glColor4fv(colc);

          glBegin(GL_QUADS);
          glTexCoord2f(0.0f, 0.0f); glVertex2f(min.x, min.y);
          glTexCoord2f(1.0f, 0.0f); glVertex2f(max.x, min.y);
          glTexCoord2f(1.0f, 1.0f); glVertex2f(max.x, max.y);
          glTexCoord2f(0.0f, 1.0f); glVertex2f(min.x, max.y);
          glEnd();

          if (w.tex is null)
            glEnable(GL_TEXTURE_2D);
          break;
        }

        default:
          break;
      }
    }
  }

  private int getFreeWidget()
  {
    foreach (i, ref w; widget)
      if (w.type == GWT_FREE)
        return cast(int) i;
    widget ~= GuiWidget(GWT_FREE);
    return cast(int) widget.length - 1;
  }

  int addLabel(float x, float y, string text, uint32 flags, float fontsize, LabelStyle ls = LabelStyle.Regular)
  {
    int w = getFreeWidget();
    widget[w].type = GWT_LABEL;
    widget[w].text = text;
    widget[w].fontsize = fontsize;
    widget[w].dims_min = ssRender.getTextDims(text) * fontsize;
    widget[w].pos = vec2f(x, y);

    final switch (ls) {
      case LabelStyle.Regular:
        widget[w].colnormal = colors.normal;
        widget[w].colclick = colors.click;
        widget[w].colhover = colors.hover;
        break;
      case LabelStyle.Weak:
        widget[w].colnormal = colors.weak;
        widget[w].colclick = colors.click;
        widget[w].colhover = colors.hover;
        break;
      case LabelStyle.Strong:
        widget[w].colnormal = colors.strong;
        widget[w].colclick = colors.click;
        widget[w].colhover = colors.hover;
        break;
      case LabelStyle.Marked:
        widget[w].colnormal = colors.marked;
        widget[w].colclick = colors.click;
        widget[w].colhover = colors.hover;
        break;
      case LabelStyle.Header:
        widget[w].colnormal = colors.header;
        widget[w].colclick = colors.click;
        widget[w].colhover = colors.hover;
        break;
      case LabelStyle.List:
        widget[w].colnormal = colors.listnormal;
        widget[w].colclick = colors.listclick;
        widget[w].colhover = colors.listhover;
        break;
    }

    if (flags & PTEXT_HZA_CENTER)
      widget[w].pos.x -= widget[w].dims_min.x * 0.5f;
    else if (flags & PTEXT_HZA_RIGHT)
      widget[w].pos.x -= widget[w].dims_min.x;

    if (flags & PTEXT_VTA_CENTER)
      widget[w].pos.y -= widget[w].dims_min.y * 0.5f;
    else if (flags & PTEXT_VTA_TOP)
      widget[w].pos.y -= widget[w].dims_min.y;

    return w;
  }

  int addGraphic(float x, float y, float width, float height, PTexture tex, GraphicStyle gs = GraphicStyle.Image)
  {
    int w = getFreeWidget();
    widget[w].type = GWT_GRAPHIC;
    widget[w].dims_min = vec2f(width, height);
    widget[w].pos = vec2f(x, y);
    widget[w].tex = tex;

    if (gs == GraphicStyle.Button) {
      widget[w].colnormal = colors.bnormal;
      widget[w].colclick = colors.bclick;
      widget[w].colhover = colors.bhover;
    } else if (gs == GraphicStyle.Image) {
      widget[w].colnormal = vec4f(1.00f, 1.00f, 1.00f, 1.00f);
      widget[w].colclick = vec4f(1.00f, 1.00f, 1.00f, 1.00f);
      widget[w].colhover = vec4f(1.00f, 1.00f, 1.00f, 1.00f);
    }

    return w;
  }

  int makeClickable(int w, int data1, int data2)
  {
    widget[w].clickable = true;
    widget[w].d1 = data1;
    widget[w].d2 = data2;
    return w;
  }

  int makeUnclickable(int w)
  {
    widget[w].clickable = false;
    return w;
  }

  int makeSelectable(int w, int data1, int data2, bool select)
  {
    widget[w].selectable = true;
    widget[w].selected = select;
    return makeClickable(w, data1, data2);
  }

  void makeDefault(int w) { defwidget = w; }
}
