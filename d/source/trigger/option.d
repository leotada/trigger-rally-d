// Copyright (C) 2021 Martin Scherer
// Based on the original Trigger Rally source; see the NOTICE file for all credits.
// License: GNU General Public License, version 2 or later (see COPYING.txt)
// option [trigger]
//
// Options menu.
module trigger.option;

import std.math : pow, round;

import bindings.gl : GLfloat;
import pengine.config;
import pengine.render;
import pengine.vmath;
import trigger.menu;

final class POption
{
  private enum OptionId {
    OptionPlayerName,
    OptionEngineVolume,
    OptionSfxVolume,
    OptionCodriverVolume,
    OptionCodriverVoice,
    OptionCodriverSigns,
    OptionTextureQuality,
    OptionSnowflakes,
    OptionSpeedUnits,
    OptionGhostCars,
    OptionDisplayFps,
    OptionFoliage,
    OptionRoadsigns,
    OptionDirtEffect,
    OptionTransmission,
    OptionMaxSize
  }

  private struct Option {
    OptionId id;
    string text;
    string[] values;
    uint select;
  }

  private Gui parent;
  private PConfig cfg;
  private uint pos;
  private Option[] options;

  this(Gui parent, PConfig config)
  {
    this.parent = parent;
    cfg = config;
    pos = 0;

    string[] vol = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10"];
    options ~= Option(OptionId.OptionEngineVolume, "Engine volume", vol.dup, 0);
    options ~= Option(OptionId.OptionSfxVolume, "SFX volume", vol.dup, 0);
    options ~= Option(OptionId.OptionCodriverVolume, "Codriver volume", vol.dup, 0);
    options ~= Option(OptionId.OptionCodriverVoice, "Codriver voice", ["off", "ab", "paula", "tim"], 0);
    options ~= Option(OptionId.OptionCodriverSigns, "Codriver signs", ["off", "abon", "glossy", "plain", "white"], 0);
    options ~= Option(OptionId.OptionTextureQuality, "Texture quality", ["off", "1", "2", "4", "8", "16", "32"], 0);
    options ~= Option(OptionId.OptionSnowflakes, "Snowflakes", ["off", "point", "square", "textured"], 0);
    options ~= Option(OptionId.OptionSpeedUnits, "Speed units", ["kmh", "mph"], 0);
    options ~= Option(OptionId.OptionGhostCars, "Ghost cars", ["off", "on"], 0);
    options ~= Option(OptionId.OptionDisplayFps, "Display FPS", ["off", "on"], 0);
    options ~= Option(OptionId.OptionFoliage, "Foliage", ["off", "on"], 0);
    options ~= Option(OptionId.OptionRoadsigns, "Roadsigns", ["off", "on"], 0);
    options ~= Option(OptionId.OptionDirtEffect, "Dirt effect", ["off", "on"], 0);
    options ~= Option(OptionId.OptionTransmission, "Transmission", ["manual", "automatic"], 0);
  }

  void render()
  {
    pos = 0;

    parent.makeClickable(
      parent.addLabel(10.0f, 10.0f, "back", PTEXT_HZA_LEFT | PTEXT_VTA_BOTTOM, 40.0f),
      AA_RELOAD_ALL, 0);
    parent.addLabel(80.0f, 520.0f, "Options", PTEXT_HZA_LEFT | PTEXT_VTA_CENTER, 30.0f, LabelStyle.Header);

    foreach (ref option; options)
      addOption(option);
  }

  /// index: lower word holds row, higher word holds index
  void select(int index)
  {
    uint row = index & 0xFFFF;
    uint column = (index >> 16) & 0xFFFF;

    options[row].select = column;

    switch (options[row].id) {
      case OptionId.OptionEngineVolume:
        cfg.setVolumeEngine(column * 0.1f);
        break;
      case OptionId.OptionSfxVolume:
        cfg.setVolumeSfx(column * 0.1f);
        break;
      case OptionId.OptionCodriverVolume:
        cfg.setVolumeCodriver(column * 0.1f);
        break;
      case OptionId.OptionCodriverVoice:
        if (!column)
          cfg.setCodrivername("mime");
        else
          cfg.setCodrivername(options[row].values[column]);
        break;
      case OptionId.OptionCodriverSigns:
        if (column) {
          cfg.setEnableCodriversigns(true);
          cfg.setCodriversigns(options[row].values[column]);
        } else {
          cfg.setEnableCodriversigns(false);
        }
        break;
      case OptionId.OptionTextureQuality:
        if (column)
          cfg.setAnisotropy(cast(float) pow(2.0, cast(double)(column - 1)));
        else
          cfg.setAnisotropy(0.0f);
        break;
      case OptionId.OptionSnowflakes:
        if (column) {
          cfg.setWeather(true);
          cfg.setSnowflaketype(cast(PConfig.SnowFlakeType)(column - 1));
        } else
          cfg.setWeather(false);
        break;
      case OptionId.OptionSpeedUnits:
        if (!column)
          cfg.setSpeedUnit(PConfig.Speedunit.kph);
        else
          cfg.setSpeedUnit(PConfig.Speedunit.mph);
        break;
      case OptionId.OptionGhostCars:
        cfg.setEnableGhost(column != 0);
        break;
      case OptionId.OptionDisplayFps:
        cfg.setEnableFps(column != 0);
        break;
      case OptionId.OptionFoliage:
        cfg.setFoliage(column != 0);
        break;
      case OptionId.OptionRoadsigns:
        cfg.setRoadsigns(column != 0);
        break;
      case OptionId.OptionDirtEffect:
        cfg.setDirteffect(column != 0);
        break;
      case OptionId.OptionTransmission:
        cfg.setAutomaticTransmission(column != 0);
        break;
      default:
        break;
    }
  }

  private void addOption(ref Option option)
  {
    uint cursor = 0;

    updateSelect(option);

    parent.addLabel(80.0f, 490.0f - cast(float) pos * 30.0f,
                    option.text, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 22.0f, LabelStyle.Regular);

    foreach (i, val; option.values) {
      bool sel = (i == option.select);

      parent.makeSelectable(
        parent.addLabel(340.0f + cast(float) cursor * 44.0f / 3.0f, 490.0f - cast(float) pos * 30.0f,
                        val, PTEXT_HZA_LEFT | PTEXT_VTA_TOP, 22.0f, LabelStyle.Weak),
        AA_PICK_OPT, cast(int)(pos | (cast(uint) i << 16)), sel);
      cursor += cast(uint) val.length + 1;
    }

    ++pos;
  }

  private void updateSelect(ref Option option)
  {
    switch (option.id) {
      case OptionId.OptionEngineVolume:
        option.select = cast(uint) round(cfg.getVolumeEngine() * 10.0f);
        break;
      case OptionId.OptionSfxVolume:
        option.select = cast(uint) round(cfg.getVolumeSfx() * 10.0f);
        break;
      case OptionId.OptionCodriverVolume:
        option.select = cast(uint) round(cfg.getVolumeCodriver() * 10.0f);
        break;
      case OptionId.OptionCodriverVoice:
        if (cfg.getCodrivername() == "mime")
          option.select = 0;
        else
          option.select = findStringPos(cfg.getCodrivername(), option.values);
        break;
      case OptionId.OptionCodriverSigns:
        if (cfg.getEnableCodriversigns())
          option.select = findStringPos(cfg.getCodriversigns(), option.values);
        else
          option.select = 0;
        break;
      case OptionId.OptionTextureQuality: {
        GLfloat anisotropy = cfg.getAnisotropy();
        if (anisotropy == 1.0f)
          option.select = 1;
        else if (anisotropy == 2.0f)
          option.select = 2;
        else if (anisotropy == 4.0f)
          option.select = 3;
        else if (anisotropy == 8.0f)
          option.select = 4;
        else if (anisotropy == 16.0f)
          option.select = 5;
        else if (anisotropy == 32.0f)
          option.select = 6;
        else
          option.select = 0;
        break;
      }
      case OptionId.OptionSnowflakes:
        if (cfg.getWeather())
          option.select = cast(uint) cfg.getSnowflaketype() + 1;
        else
          option.select = 0;
        break;
      case OptionId.OptionSpeedUnits:
        option.select = cfg.getSpeedUnit() == PConfig.Speedunit.mph ? 1 : 0;
        break;
      case OptionId.OptionGhostCars:
        option.select = cfg.getEnableGhost() ? 1 : 0;
        break;
      case OptionId.OptionDisplayFps:
        option.select = cfg.getEnableFps() ? 1 : 0;
        break;
      case OptionId.OptionFoliage:
        option.select = cfg.getFoliage() ? 1 : 0;
        break;
      case OptionId.OptionRoadsigns:
        option.select = cfg.getRoadsigns() ? 1 : 0;
        break;
      case OptionId.OptionDirtEffect:
        option.select = cfg.getDirteffect() ? 1 : 0;
        break;
      case OptionId.OptionTransmission:
        option.select = cfg.getAutomaticTransmission() ? 1 : 0;
        break;
      default:
        break;
    }
  }

  private uint findStringPos(string str, string[] vec)
  {
    foreach (i, v; vec)
      if (v == str) return cast(uint) i;
    return 0;
  }
}
