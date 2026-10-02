package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxFrame;
import funkin.qol.ui.QOLTheme;
import openfl.display.BitmapData;
import openfl.display.Graphics;
import openfl.display.Shape;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;

typedef AnimTheme =
{
  var name:String;

  /**
   * Main highlight (buttons pressed, playhead, selected tab...).
   */
  var accent:Int;

  /**
   * Second color, for gradients.
   */
  var accent2:Int;

  /**
   * Background: panels take its hue (their brightness stays dark).
   */
  var base:Int;
}

/**
 * The Animator's look: a purple/pink theme matching the Mod Menu (scoped to the Animator's screen), hand-drawn vector
 * icons for tools and buttons, and the color palettes.
 *
 * Icons are drawn once with OpenFL vector graphics and cached as persistent graphics.
 */
class AnimatorSkin
{
  // Fixed colors (meaning, not theme).
  public static inline final INK:Int = 0xFF1A1030;
  public static inline final CYAN:Int = 0xFF5CE1FF;
  public static inline final YELLOW:Int = 0xFFFFD84A;
  public static inline final GREEN:Int = 0xFF6BE38E;
  public static inline final PURPLE:Int = 0xFF9B6BFF;

  /**
   * Ready-made themes. Any colors work: the panels take the background color's hue and keep their own brightness.
   */
  public static final PRESETS:Array<AnimTheme> = [
    {name: 'Bubblegum', accent: 0xFFFF5C9D, accent2: 0xFF9B6BFF, base: 0xFF1E1838},
    {name: 'Boyfriend', accent: 0xFF31B0D1, accent2: 0xFF4C8DFF, base: 0xFF142238},
    {name: 'Girlfriend', accent: 0xFFE0306E, accent2: 0xFFFF8A4C, base: 0xFF2A1420},
    {name: 'Pico', accent: 0xFFB7D855, accent2: 0xFF3CCB8F, base: 0xFF15261C},
    {name: 'Daddy Dearest', accent: 0xFFAF66CE, accent2: 0xFFE0306E, base: 0xFF22142C},
    {name: 'Spooky Month', accent: 0xFFFF8A3D, accent2: 0xFF9B6BFF, base: 0xFF1E1626},
    {name: 'Senpai', accent: 0xFFFFAA6F, accent2: 0xFFFF6FA8, base: 0xFF2A1A20},
    {name: 'Tankman', accent: 0xFFE8B04A, accent2: 0xFF9AA85A, base: 0xFF22201A},
    {name: 'Ocean', accent: 0xFF35D4BE, accent2: 0xFF4C8DFF, base: 0xFF10222A},
    {name: 'Midnight', accent: 0xFFE8E4F4, accent2: 0xFF8C88A0, base: 0xFF18181C}
  ];

  public static var theme(default, null):AnimTheme = PRESETS[0];

  // Colors worked out from the theme (see `derive`).
  public static var ACCENT:Int = 0xFFFF5C9D;
  public static var ACCENT2:Int = 0xFF9B6BFF;

  /**
   * Text on top of the accent color (white, or ink when the accent is very light).
   */
  public static var ON_ACCENT:Int = 0xFFFFFFFF;

  public static var ACCENT_TEXT:Int = 0xFFFF8FC0;
  public static var BG_TOP:Int = 0xFF241A46;
  public static var BG_BOTTOM:Int = 0xFF120D24;
  public static var PANEL:Int = 0xFF1E1838;
  public static var FIELD:Int = 0xFF15112A;
  public static var SURFACE:Int = 0xFF2C2354;
  public static var BORDER:Int = 0xFF3D3366;
  public static var BORDER_LIGHT:Int = 0xFF54479A;
  public static var BUTTON_TOP:Int = 0xFF3A2F6B;
  public static var BUTTON_BOTTOM:Int = 0xFF2A2252;
  public static var TEXT:Int = 0xFFEDE6FF;
  public static var TEXT_SOFT:Int = 0xFFDCD3FF;
  public static var TEXT_DIM:Int = 0xFFA99CD6;
  public static var TEXT_FAINT:Int = 0xFF5E5488;
  public static var TL_BG:Int = 0xFF140F26;
  public static var TL_LABELS:Int = 0xFF1B1533;
  public static var TL_RULER:Int = 0xFF221A40;
  public static var TL_ROW_A:Int = 0xFF181230;
  public static var TL_ROW_B:Int = 0xFF1C1636;

  /**
   * Bumped whenever the theme changes, so cached graphics can include it in their keys.
   */
  public static var version(default, null):Int = 0;

  /**
   * The saved theme (Animator preferences).
   */
  public static function loadSaved():Void
  {
    var saved:String = QOLConfig.getPref('animator.theme', '');
    var parts = saved.split(',');
    if (parts.length >= 3)
    {
      var t:AnimTheme = {
        name: parts.length > 3 ? parts.slice(3).join(',') : 'Custom',
        accent: parseHex(parts[0], PRESETS[0].accent),
        accent2: parseHex(parts[1], PRESETS[0].accent2),
        base: parseHex(parts[2], PRESETS[0].base)
      };
      applyTheme(t, false);
    }
    else
    {
      applyTheme(PRESETS[0], false);
    }
  }

  static function parseHex(s:String, def:Int):Int
  {
    var v = Std.parseInt('0x' + StringTools.trim(s));
    return v == null ? def : (v | 0xFF000000);
  }

  /**
   * Switch theme: works out every color, restyles the Animator's widgets, and saves it if `save`.
   */
  public static function applyTheme(t:AnimTheme, save:Bool = true):Void
  {
    theme = {
      name: t.name,
      accent: t.accent | 0xFF000000,
      accent2: t.accent2 | 0xFF000000,
      base: t.base | 0xFF000000
    };
    derive();
    version++;
    loadCss(true);
    if (save)
      QOLConfig.setPref('animator.theme', '${StringTools.hex(theme.accent & 0xFFFFFF, 6)},${StringTools.hex(theme.accent2 & 0xFFFFFF, 6)},'
        + '${StringTools.hex(theme.base & 0xFFFFFF, 6)},${theme.name}');
  }

  static function derive():Void
  {
    ACCENT = theme.accent;
    ACCENT2 = theme.accent2;
    ON_ACCENT = luminance(ACCENT) > 0.72 ? INK : 0xFFFFFFFF;
    ACCENT_TEXT = luminance(ACCENT) < 0.35 ? lighten(ACCENT, 0.45) : lighten(ACCENT, 0.2);
    var hsl = toHsl(theme.base);
    var h = hsl[0];
    var sat = Math.min(0.6, hsl[1]);
    inline function tone(l:Float, sMul:Float = 1):Int
      return fromHsl(h, Math.min(1, sat * sMul), l);
    PANEL = tone(0.157);
    FIELD = tone(0.116, 1.05);
    SURFACE = tone(0.233, 1.02);
    BG_TOP = tone(0.188, 1.15);
    BG_BOTTOM = tone(0.096, 1.17);
    BORDER = tone(0.30, 0.82);
    BORDER_LIGHT = tone(0.44, 0.92);
    BUTTON_TOP = tone(0.30, 0.97);
    BUTTON_BOTTOM = tone(0.227, 1.02);
    TEXT = tone(0.95, 2.5);
    TEXT_SOFT = tone(0.91, 2.5);
    TEXT_DIM = tone(0.73, 1.08);
    TEXT_FAINT = tone(0.43, 0.6);
    TL_BG = tone(0.104, 1.08);
    TL_LABELS = tone(0.14, 1.05);
    TL_RULER = tone(0.176, 1.05);
    TL_ROW_A = tone(0.13, 1.05);
    TL_ROW_B = tone(0.15, 1.05);
  }

  public static function luminance(c:Int):Float
    return (0.2126 * ((c >> 16) & 0xFF) + 0.7152 * ((c >> 8) & 0xFF) + 0.0722 * (c & 0xFF)) / 255;

  public static function toHsl(c:Int):Array<Float>
  {
    var r = ((c >> 16) & 0xFF) / 255, g = ((c >> 8) & 0xFF) / 255, b = (c & 0xFF) / 255;
    var max = Math.max(r, Math.max(g, b)), min = Math.min(r, Math.min(g, b));
    var l = (max + min) / 2;
    if (max == min) return [0, 0, l];
    var d = max - min;
    var s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    var hue = if (max == r) (g - b) / d + (g < b ? 6 : 0) else if (max == g) (b - r) / d + 2 else (r - g) / d + 4;
    return [hue * 60, s, l];
  }

  public static function fromHsl(h:Float, s:Float, l:Float):Int
  {
    function f(n:Float):Int
    {
      var k = (n + h / 30) % 12;
      var a = s * Math.min(l, 1 - l);
      var v = l - a * Math.max(-1, Math.min(k - 3, Math.min(9 - k, 1)));
      return Std.int(Math.max(0, Math.min(255, Math.round(v * 255))));
    }
    return 0xFF000000 | (f(0) << 16) | (f(8) << 8) | f(4);
  }

  /**
   * CSS color for a value (e.g. `#FF5C9D`).
   */
  public static function css(c:Int):String
    return '#' + StringTools.hex(c & 0xFFFFFF, 6);

  /**
   * Each tool's tile color (like the Mod Menu's tiles).
   */
  public static final TOOL_COLORS:Map<String, Int> = [
    'select' => 0xFF4C8DFF, 'brush' => 0xFFFF5C9D, 'pencil' => 0xFFFFA43D, 'eraser' => 0xFFFF6B6B, 'fill' => 0xFF3CCB8F,
    'line' => 0xFF9B6BFF, 'rect' => 0xFF2EC4E6, 'oval' => 0xFFF5C62E, 'poly' => 0xFFFF7A45, 'text' => 0xFF9AD94A,
    'picker' => 0xFFD65CFF, 'hand' => 0xFF7C93C9, 'zoom' => 0xFF35D4BE
  ];

  /**
   * Quick colors: FNF's cast first, then basics.
   */
  public static final PALETTE:Array<{color:Int, name:String}> = [
    {color: 0xFF31B0D1, name: 'Boyfriend'},
    {color: 0xFFA5004D, name: 'Girlfriend'},
    {color: 0xFFAF66CE, name: 'Daddy Dearest'},
    {color: 0xFFB7D855, name: 'Pico'},
    {color: 0xFFD8558E, name: 'Mommy Mearest'},
    {color: 0xFFF2A73B, name: 'Skid & Pump'},
    {color: 0xFFFFAA6F, name: 'Senpai'},
    {color: 0xFFE1E1E1, name: 'Tankman'},
    {color: 0xFF000000, name: 'Black'},
    {color: 0xFF5A5470, name: 'Gray'},
    {color: 0xFFFFFFFF, name: 'White'},
    {color: 0xFFFF3B3B, name: 'Red'},
    {color: 0xFFFFD84A, name: 'Yellow'},
    {color: 0xFF3CCB8F, name: 'Green'},
    {color: 0xFF3D7BFF, name: 'Blue'},
    {color: 0xFFFF5C9D, name: 'Pink'}
  ];

  //
  // Theme (CSS, scoped to `.anim-ui`)
  //

  static var cssLoaded:Bool = false;
  static var cssVersion:Int = 0;

  /**
   * Load (or with `force`, rebuild) the Animator's stylesheet from the current theme.
   */
  public static function loadCss(force:Bool = false):Void
  {
    if (cssLoaded && !force) return;
    if (!cssLoaded && !force)
    {
      // First use: the saved theme decides the colors.
      cssLoaded = true;
      loadSaved();
      return;
    }
    cssLoaded = true;
    var c = css;
    var accLight = lighten(ACCENT, 0.2), accDark = darken(ACCENT, 0.15), accPale = lighten(ACCENT, 0.55), on = css(ON_ACCENT);
    var btnHoverTop = lighten(BUTTON_TOP, 0.1), btnHoverBottom = lighten(BUTTON_BOTTOM, 0.06);
    var out = new StringBuf();
    // HaxeUI skips stylesheets it has seen before, so every version is unique.
    out.add('/* qol animator theme ${++cssVersion} */\n');
    out.add('
.anim-ui .label { color: ${c(TEXT_SOFT)}; }
.anim-ui .button {
  background: ${c(BUTTON_TOP)} ${c(BUTTON_BOTTOM)} vertical; color: ${c(TEXT)}; border: 1px solid ${c(BORDER_LIGHT)}; border-radius: 7px;
}
.anim-ui .button:hover { background: ${c(btnHoverTop)} ${c(btnHoverBottom)} vertical; border: 1px solid ${c(accLight)}; color: #FFFFFF; }
.anim-ui .button:down { background: ${c(accLight)} ${c(accDark)} vertical; border: 1px solid ${c(accPale)}; color: $on; }
.anim-ui .button:disabled { background: ${c(BUTTON_BOTTOM)} ${c(PANEL)} vertical; color: ${c(TEXT_FAINT)}; border: 1px solid ${c(BORDER)}; }
.anim-ui .dropdown { background: ${c(BUTTON_BOTTOM)} ${c(darken(BUTTON_BOTTOM, 0.12))} vertical; border: 1px solid ${c(BORDER_LIGHT)}; border-radius: 7px; color: ${c(TEXT)}; }
.anim-ui .dropdown:hover { border: 1px solid ${c(accLight)}; }
.anim-ui .textfield, .anim-ui .textarea {
  background-color: ${c(FIELD)}; color: ${c(TEXT)}; border: 1px solid ${c(BORDER_LIGHT)}; border-radius: 6px; filter: none;
}
.anim-ui .textfield:active, .anim-ui .textarea:active { border: 1px solid ${c(accLight)}; }
.anim-ui .number-stepper { border-radius: 6px; }
.anim-ui .checkbox { color: ${c(TEXT_SOFT)}; }
.anim-ui .checkbox-value { background-color: ${c(FIELD)}; border: 1px solid ${c(BORDER_LIGHT)}; border-radius: 5px; filter: none; }
.anim-ui .checkbox-value:hover { border: 1px solid ${c(accLight)}; }
.anim-ui .checkbox-value:selected { background-color: ${c(ACCENT)}; border: 1px solid ${c(accPale)}; }
.anim-ui .horizontal-range { background: ${c(FIELD)} ${c(PANEL)} vertical; border: 1px solid ${c(BORDER)}; border-radius: 5px; filter: none; }
.anim-ui .horizontal-range .range-value { background: ${c(ACCENT)} ${c(ACCENT2)} horizontal; border-radius: 4px; }
.anim-ui .horizontal-slider .button { background: #FFFFFF ${c(TEXT_SOFT)} vertical; border: 1px solid ${c(ACCENT)}; border-radius: 6px; width: 12px; height: 18px; }
.anim-ui .horizontal-slider:active .button { border: 1px solid #FFFFFF; }
.anim-ui .section-header .label { color: ${c(ACCENT_TEXT)}; font-bold: true; }
.anim-ui .section-header .line { background-color: ${c(BORDER)}; border-color: ${c(BORDER)}; }
.anim-ui .tabbar { border-bottom-color: ${c(BORDER)}; }
.anim-ui .tabbar > .tabbar-contents { border-bottom-color: ${c(BORDER)}; }
.anim-ui .tabbar-button {
  background: ${c(lighten(PANEL, 0.03))} ${c(PANEL)} vertical; color: ${c(TEXT_DIM)}; border: 1px solid ${c(BORDER)}; border-radius: 0px; border-top: 2px solid ${c(BUTTON_BOTTOM)};
}
.anim-ui .tabbar-button:hover { background: ${c(SURFACE)} ${c(lighten(PANEL, 0.05))} vertical; color: #FFFFFF; }
.anim-ui .tabbar-button-selected, .anim-ui .tabbar-button-selected:hover {
  background: ${c(SURFACE)} ${c(SURFACE)} vertical; color: #FFFFFF; border: 1px solid ${c(BORDER)}; border-top: 2px solid ${c(ACCENT)}; border-bottom-color: ${c(SURFACE)};
}
.anim-ui .tabbar-button-selected .label { color: #FFFFFF; }
.anim-ui .tabview > .tabview-content { background-color: ${c(SURFACE)}; border: 1px solid ${c(BORDER)}; }
.anim-ui .listview { background-color: ${c(FIELD)}; border: 1px solid ${c(BORDER)}; border-radius: 6px; }
.anim-ui .listview .even, .anim-ui .listview .odd { background-color: ${c(FIELD)}; }
.anim-ui .listview .even:hover, .anim-ui .listview .odd:hover { background-color: ${c(BUTTON_BOTTOM)}; }
.anim-ui .listview .listview-contents > .itemrenderer:selected { background-color: ${c(ACCENT)}; }
.anim-ui .listview .listview-contents > .itemrenderer:selected .label { color: $on; }
.anim-ui .menubar { background: ${c(lighten(BUTTON_BOTTOM, 0.02))} ${c(PANEL)} vertical; border-bottom: 1px solid ${c(BORDER)}; }
.anim-ui .menubar-button { background-color: ${c(lighten(BUTTON_BOTTOM, 0.02))}; color: ${c(TEXT)}; }
.anim-ui .menubar-button:hover { background-color: ${c(ACCENT)}; color: $on; }
.anim-ui .vertical-scroll .thumb, .anim-ui .horizontal-scroll .thumb { background-color: ${c(BORDER_LIGHT)}; border: none; border-radius: 4px; }
.anim-ui .vertical-scroll .thumb:hover, .anim-ui .horizontal-scroll .thumb:hover { background-color: ${c(accLight)}; }
.anim-ui .vertical-scroll, .anim-ui .horizontal-scroll { background-color: ${c(FIELD)}; border: none; }

.anim-ui .anim-tool { background: ${c(lighten(BUTTON_BOTTOM, 0.04))} ${c(darken(BUTTON_BOTTOM, 0.1))} vertical; border: 1px solid ${c(lighten(BORDER, 0.06))}; border-radius: 9px; padding: 0px; }
.anim-ui .anim-tool:hover { background: ${c(btnHoverTop)} ${c(BUTTON_BOTTOM)} vertical; border: 1px solid #FFFFFF; }
.anim-ui .anim-icon-button { padding: 3px 6px; }
.anim-ui .anim-play { background: ${c(accLight)} ${c(accDark)} vertical; border: 1px solid ${c(accPale)}; border-radius: 13px; }
.anim-ui .anim-play:hover { background: ${c(lighten(ACCENT, 0.3))} ${c(darken(ACCENT, 0.05))} vertical; border: 1px solid #FFFFFF; }
.anim-ui .anim-on { background: ${c(lighten(ACCENT, 0.1))} ${c(darken(ACCENT, 0.22))} vertical; border: 1px solid ${c(accPale)}; }
.anim-ui .anim-on:hover { background: ${c(accLight)} ${c(darken(ACCENT, 0.12))} vertical; border: 1px solid #FFFFFF; }
.anim-ui .anim-swatch { border: 2px solid ${c(FIELD)}; border-radius: 6px; cursor: pointer; }
.anim-ui .anim-swatch:hover { border: 2px solid #FFFFFF; }
.anim-ui .anim-note { color: ${c(TEXT_DIM)}; font-size: 11px; }
.anim-ui .anim-theme-chip { border-radius: 9px; padding: 4px 8px; }

.menu.anim-popup { background-color: ${c(PANEL)}; border: 1px solid ${c(BORDER_LIGHT)}; border-radius: 8px; padding: 4px; }
.anim-popup .menuitem { background-color: ${c(PANEL)}; border-radius: 5px; }
.anim-popup .menuitem:hover, .anim-popup .menuitem:selected { background: ${c(lighten(ACCENT, 0.1))} ${c(accDark)} vertical; }
.anim-popup .menuitem-label, .anim-popup .menuitem .label { color: ${c(TEXT)}; }
.anim-popup .menuitem-shortcut-label { color: ${c(TEXT_DIM)}; }
.anim-popup .menuitem .label:hover, .anim-popup .menuitem .label:selected { color: $on; }
.anim-popup .menuseparator-line { background-color: ${c(BORDER)}; }
.dialog.anim-popup { background-color: ${c(PANEL)}; border: 1px solid ${c(lighten(BORDER_LIGHT, 0.12))}; border-radius: 12px; padding: 0px; }
.anim-popup .dialog-title { background: ${c(ACCENT)} ${c(ACCENT2)} horizontal; border-top-left-radius: 11px; border-top-right-radius: 11px; }
.anim-popup .dialog-title-label { color: $on; font-bold: true; }
.anim-popup .dialog-footer-container { background-color: ${c(FIELD)}; border-bottom-left-radius: 11px; border-bottom-right-radius: 11px; }
');
    // Active tool tiles take the tool's color.
    for (id => tc in TOOL_COLORS)
    {
      out.add('.anim-ui .anim-tool-on-$id, .anim-ui .anim-tool-on-$id:hover { background: ${hex(lighten(tc, 0.18))} ${hex(darken(tc, 0.12))} vertical; '
        + 'border: 1px solid ${hex(lighten(tc, 0.55))}; }\n');
    }
    // Colored action buttons.
    for (name => bc in ['cyan' => CYAN, 'green' => GREEN, 'yellow' => YELLOW, 'purple' => PURPLE, 'red' => 0xFFFF6B6B, 'pink' => 0xFFFF5C9D])
    {
      out.add('.anim-ui .anim-btn-$name { border: 1px solid ${hex(darken(bc, 0.25))}; }\n');
      out.add('.anim-ui .anim-btn-$name:hover { background: ${hex(lighten(bc, 0.05))} ${hex(darken(bc, 0.2))} vertical; border: 1px solid ${hex(lighten(bc, 0.5))}; color: #1A1030; }\n');
    }
    haxe.ui.Toolkit.styleSheet.clear('qol-animator');
    haxe.ui.Toolkit.styleSheet.parse(out.toString(), 'qol-animator', true);
  }

  static function hex(c:Int):String
    return '#' + StringTools.hex(c & 0xFFFFFF, 6);

  public static function lighten(c:Int, t:Float):Int
  {
    var r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
    r = Std.int(r + (255 - r) * t);
    g = Std.int(g + (255 - g) * t);
    b = Std.int(b + (255 - b) * t);
    return (c & 0xFF000000) | (r << 16) | (g << 8) | b;
  }

  public static function darken(c:Int, t:Float):Int
  {
    var r = Std.int(((c >> 16) & 0xFF) * (1 - t));
    var g = Std.int(((c >> 8) & 0xFF) * (1 - t));
    var b = Std.int((c & 0xFF) * (1 - t));
    return (c & 0xFF000000) | (r << 16) | (g << 8) | b;
  }

  //
  // Icons
  //

  /**
   * A cached icon graphic: the glyph in `color`, with a dark outline (FNF-style) when `outlined`.
   */
  public static function iconGraphic(name:String, size:Int, color:Int, outlined:Bool = true):FlxGraphic
  {
    var key = 'qol-anim-icon-$name-$size-${StringTools.hex(color, 8)}-${outlined ? 'o' : 'f'}';
    return QOLTheme.cached(key, () -> drawIcon(name, size, color, outlined));
  }

  /**
   * An icon for HaxeUI components (`button.icon = AnimatorSkin.icon(...)`).
   */
  public static function icon(name:String, size:Int, color:Int, outlined:Bool = true):FlxFrame
    return iconGraphic(name, size, color, outlined).imageFrame.frame;

  /**
   * A little preview of a theme's colors (for the theme presets).
   */
  public static function themeSwatch(t:AnimTheme):FlxFrame
  {
    var key = 'qol-anim-theme-${StringTools.hex(t.accent, 8)}-${StringTools.hex(t.accent2, 8)}-${StringTools.hex(t.base, 8)}';
    return QOLTheme.cached(key, () -> {
      var sh = new Shape();
      var g = sh.graphics;
      var hsl = toHsl(t.base);
      g.beginFill(fromHsl(hsl[0], Math.min(0.6, hsl[1]), 0.2) & 0xFFFFFF, 1);
      g.lineStyle(1, 0xFFFFFF, 0.35);
      g.drawRoundRect(0.5, 0.5, 41, 17, 9, 9);
      g.endFill();
      g.lineStyle();
      g.beginFill(t.accent & 0xFFFFFF, 1);
      g.drawCircle(11, 9, 5.5);
      g.endFill();
      g.beginFill(t.accent2 & 0xFFFFFF, 1);
      g.drawCircle(24, 9, 5.5);
      g.endFill();
      g.beginFill(t.base & 0xFFFFFF, 1);
      g.lineStyle(1, 0xFFFFFF, 0.6);
      g.drawCircle(35, 9, 4);
      g.endFill();
      var b = new BitmapData(43, 19, true, 0);
      b.draw(sh, null, null, null, null, true);
      return b;
    }).imageFrame.frame;
  }

  public static function drawIcon(name:String, size:Int, color:Int, outlined:Bool):BitmapData
  {
    var pad = outlined ? 2 : 0;
    var full = size + pad * 2;
    var glyph = new Shape();
    var s = size / 24;
    paint(glyph.graphics, name, color, s);
    var glyphBmp = new BitmapData(full, full, true, 0);
    var m = new Matrix();
    m.translate(pad, pad);
    glyphBmp.draw(glyph, m, null, null, null, true);
    if (!outlined) return glyphBmp;
    var out = new BitmapData(full, full, true, 0);
    var ink = new ColorTransform(0, 0, 0, 1, (INK >> 16) & 0xFF, (INK >> 8) & 0xFF, INK & 0xFF, 0);
    var r = Math.max(1, size / 16);
    var dirs:Array<Array<Float>> = [[1, 0], [-1, 0], [0, 1], [0, -1], [0.7, 0.7], [-0.7, 0.7], [0.7, -0.7], [-0.7, -0.7]];
    for (d in dirs)
    {
      var om = new Matrix();
      om.translate(d[0] * r, d[1] * r);
      out.draw(glyphBmp, om, ink, null, null, true);
    }
    // A little drop below, like the Mod Menu's chunky text.
    var dm = new Matrix();
    dm.translate(0, r * 1.2);
    out.draw(glyphBmp, dm, ink, null, null, true);
    out.draw(glyphBmp, null, null, null, null, true);
    glyphBmp.dispose();
    return out;
  }

  static inline function rgb(c:Int):Int
    return c & 0xFFFFFF;

  static inline function alphaOf(c:Int):Float
    return ((c >>> 24) & 0xFF) / 255;

  /**
   * Draws an icon on a 24x24 design grid, scaled by `s`.
   */
  public static function paint(g:Graphics, name:String, color:Int, s:Float):Void
  {
    var c = rgb(color);
    var a = alphaOf(color);
    inline function poly(pts:Array<Float>, ?alpha:Float = 1)
    {
      g.beginFill(c, a * alpha);
      g.moveTo(pts[0] * s, pts[1] * s);
      var i = 2;
      while (i < pts.length)
      {
        g.lineTo(pts[i] * s, pts[i + 1] * s);
        i += 2;
      }
      g.lineTo(pts[0] * s, pts[1] * s);
      g.endFill();
    }
    inline function circle(x:Float, y:Float, r:Float, ?alpha:Float = 1)
    {
      g.beginFill(c, a * alpha);
      g.drawCircle(x * s, y * s, r * s);
      g.endFill();
    }
    inline function ring(x:Float, y:Float, r:Float, w:Float)
    {
      g.lineStyle(w * s, c, a);
      g.drawCircle(x * s, y * s, r * s);
      g.lineStyle();
    }
    inline function rect(x:Float, y:Float, w:Float, h:Float, ?r:Float = 0, ?alpha:Float = 1)
    {
      g.beginFill(c, a * alpha);
      if (r > 0) g.drawRoundRect(x * s, y * s, w * s, h * s, r * 2 * s, r * 2 * s);
      else
        g.drawRect(x * s, y * s, w * s, h * s);
      g.endFill();
    }
    inline function line(x0:Float, y0:Float, x1:Float, y1:Float, w:Float)
    {
      g.lineStyle(w * s, c, a, false, null, openfl.display.CapsStyle.ROUND, openfl.display.JointStyle.ROUND);
      g.moveTo(x0 * s, y0 * s);
      g.lineTo(x1 * s, y1 * s);
      g.lineStyle();
    }
    function arc(cx:Float, cy:Float, r:Float, from:Float, to:Float, w:Float)
    {
      g.lineStyle(w * s, c, a, false, null, openfl.display.CapsStyle.ROUND, openfl.display.JointStyle.ROUND);
      var steps = 16;
      for (i in 0...steps + 1)
      {
        var t = (from + (to - from) * i / steps) * Math.PI / 180;
        var px = (cx + Math.cos(t) * r) * s, py = (cy + Math.sin(t) * r) * s;
        if (i == 0) g.moveTo(px, py);
        else
          g.lineTo(px, py);
      }
      g.lineStyle();
    }
    inline function ink()
    {
      // Dark details drawn inside the glyph (pupils, slits).
      c = rgb(INK);
    }

    switch (name)
    {
      // Tools
      case 'select':
        poly([6, 2.5, 6, 19.5, 10.2, 15.4, 13.2, 21.5, 16, 20.2, 13, 14.2, 18.8, 14.2]);
      case 'brush':
        poly([20.6, 2.2, 22.2, 3.8, 14, 13.6, 11.8, 11.6]);
        g.beginFill(c, a);
        g.moveTo(10.6 * s, 12 * s);
        g.lineTo(13.4 * s, 14.6 * s);
        g.curveTo(13 * s, 19.6 * s, 7.4 * s, 21 * s);
        g.curveTo(4.2 * s, 21.8 * s, 2.4 * s, 21.2 * s);
        g.curveTo(4.4 * s, 19.6 * s, 4.8 * s, 17 * s);
        g.curveTo(5.6 * s, 12.6 * s, 10.6 * s, 12 * s);
        g.endFill();
      case 'pencil':
        poly([16.6, 2.8, 21.2, 7.4, 8.4, 20.2, 3.8, 15.6]);
        poly([3.8, 15.6, 8.4, 20.2, 2.4, 21.6]);
        line(14.4, 5, 19, 9.6, 1.2);
      case 'eraser':
        poly([13.4, 3, 21.8, 11.4, 12.4, 20.8, 4, 12.4], 0.55);
        poly([13.4, 3, 21.8, 11.4, 16.8, 16.4, 8.4, 8]);
        line(12.4, 21, 21.4, 21, 1.6);
      case 'fill':
        poly([3.4, 10.6, 11, 3, 18.6, 10.6, 11, 18.2]);
        arc(11, 10.6, 5.2, 200, 340, 1.8);
        circle(19.8, 17.2, 2.4);
        poly([18, 16, 19.8, 12, 21.6, 16]);
      case 'line':
        line(5, 19, 19, 5, 2.6);
        circle(5, 19, 2.8);
        circle(19, 5, 2.8);
      case 'rect':
        g.lineStyle(2.8 * s, c, a);
        g.drawRoundRect(3.8 * s, 6 * s, 16.4 * s, 12 * s, 5 * s, 5 * s);
        g.lineStyle();
      case 'oval':
        g.lineStyle(2.8 * s, c, a);
        g.drawEllipse(3.4 * s, 5.6 * s, 17.2 * s, 12.8 * s);
        g.lineStyle();
      case 'poly':
        var pts:Array<Float> = [];
        for (i in 0...10)
        {
          var ang = -Math.PI / 2 + i * Math.PI / 5;
          var r = i % 2 == 0 ? 10 : 4.4;
          pts.push(12 + Math.cos(ang) * r);
          pts.push(13 + Math.sin(ang) * r);
        }
        poly(pts);
      case 'text':
        rect(4.5, 3.5, 15, 4, 1);
        rect(9.9, 3.5, 4.2, 17, 1);
        rect(7.6, 18.2, 8.8, 2.6, 1);
      case 'picker':
        line(4.6, 19.4, 13.2, 10.8, 3.4);
        circle(17.2, 6.8, 4.2);
        line(11.4, 8.6, 15.4, 12.6, 2.6);
        circle(3.8, 20.2, 1.4);
      case 'hand':
        rect(6.5, 10.5, 12, 11, 4.5);
        rect(6.6, 5, 2.8, 9, 1.4);
        rect(9.8, 3, 2.8, 10, 1.4);
        rect(13, 3.8, 2.8, 9, 1.4);
        rect(16.2, 6.2, 2.8, 8, 1.4);
        poly([6.8, 14.6, 3, 11.6, 3.8, 10.2, 8, 12.4]);
      case 'zoom':
        ring(10, 10, 6.4, 2.8);
        line(14.6, 14.6, 20.4, 20.4, 3.6);
        rect(7, 9.1, 6, 1.8);
        rect(9.1, 7, 1.8, 6);

      // Transport & timeline buttons
      case 'first':
        rect(4.5, 5.5, 3, 13, 1);
        poly([19.5, 5.5, 19.5, 18.5, 9, 12]);
      case 'prev':
        poly([16.5, 5.5, 16.5, 18.5, 6.5, 12]);
      case 'play':
        poly([7, 4.5, 7, 19.5, 19.5, 12]);
      case 'pause':
        rect(6, 5, 4.4, 14, 1.2);
        rect(13.6, 5, 4.4, 14, 1.2);
      case 'next':
        poly([7.5, 5.5, 7.5, 18.5, 17.5, 12]);
      case 'last':
        poly([4.5, 5.5, 4.5, 18.5, 15, 12]);
        rect(16.5, 5.5, 3, 13, 1);
      case 'loop':
        arc(12, 12, 7, 200, 340, 2.6);
        poly([18.2, 5.4, 21, 10.2, 15.4, 10.2]);
        arc(12, 12, 7, 20, 160, 2.6);
        poly([5.8, 18.6, 3, 13.8, 8.6, 13.8]);
      case 'onion':
        circle(7.5, 12, 5.2, 0.35);
        circle(12, 12, 5.2, 0.6);
        circle(16.5, 12, 5.2);
      case 'layer':
        poly([2.5, 14, 11, 10, 19.5, 14, 11, 18], 0.5);
        poly([2.5, 10, 11, 6, 19.5, 10, 11, 14]);
        rect(18.6, 1.6, 2.4, 8.4, 1);
        rect(15.6, 4.6, 8.4, 2.4, 1);
      case 'bitmap':
        for (yy in 0...3)
          for (xx in 0...3)
            rect(4 + xx * 5.6, 4 + yy * 5.6, 4.6, 4.6, 0.8, (xx + yy) % 2 == 0 ? 1 : 0.45);
      case 'trash':
        rect(4.5, 5, 15, 2.6, 1);
        rect(9.5, 2.6, 5, 2.6, 1);
        poly([6.2, 8.6, 17.8, 8.6, 16.6, 21.4, 7.4, 21.4]);
      case 'frame':
        g.lineStyle(2.2 * s, c, a);
        g.drawRoundRect(5 * s, 3.5 * s, 14 * s, 17 * s, 4 * s, 4 * s);
        g.lineStyle();
        rect(10.8, 7.5, 2.4, 9, 1);
        rect(7.5, 10.8, 9, 2.4, 1);
      case 'keyframe':
        circle(12, 12, 6.6);
      case 'blank':
        ring(12, 12, 5.6, 2.6);
      case 'tween':
        circle(4.4, 12, 2.6);
        line(6, 12, 16, 12, 2.6);
        poly([14.4, 6.6, 21.4, 12, 14.4, 17.4]);
      case 'swap':
        arc(12, 12, 6.8, 190, 300, 2.4);
        poly([13.6, 2.4, 18, 5.6, 13.4, 8.4]);
        arc(12, 12, 6.8, 10, 120, 2.4);
        poly([10.4, 21.6, 6, 18.4, 10.6, 15.6]);
      case 'back':
        poly([3, 12, 11, 4.6, 11, 9, 20.5, 9, 20.5, 15, 11, 15, 11, 19.4]);
      case 'save':
        rect(4, 3.5, 16, 17, 2.4);
        ink();
        rect(7.4, 3.5, 9.2, 5.6, 0.6);
        rect(7, 12.6, 10, 6, 1);
      case 'symbol':
        g.beginFill(c, a);
        g.drawRoundRect(3.5 * s, 3.5 * s, 17 * s, 17 * s, 6 * s, 6 * s);
        g.endFill();
        ink();
        poly([12, 6.6, 17.4, 12, 12, 17.4, 6.6, 12]);

      // Timeline row icons
      case 'eye':
        g.beginFill(c, a);
        g.moveTo(1.6 * s, 12 * s);
        g.curveTo(12 * s, 1 * s, 22.4 * s, 12 * s);
        g.curveTo(12 * s, 23 * s, 1.6 * s, 12 * s);
        g.endFill();
        ink();
        circle(12, 12, 4.4);
      case 'eye-off':
        g.lineStyle(2.2 * s, c, a);
        g.moveTo(2.4 * s, 12 * s);
        g.curveTo(12 * s, 2.6 * s, 21.6 * s, 12 * s);
        g.curveTo(12 * s, 21.4 * s, 2.4 * s, 12 * s);
        g.lineStyle();
        line(4, 20, 20, 4, 2.4);
      case 'lock':
        arc(12, 10, 5, 180, 360, 2.8);
        line(7, 10, 7, 12, 2.8);
        line(17, 10, 17, 12, 2.8);
        rect(4.5, 11, 15, 10.5, 2.4);
        ink();
        rect(11, 14.4, 2, 4, 0.6);
      case 'unlock':
        arc(16, 8, 4.6, 180, 360, 2.6);
        line(20.6, 8, 20.6, 10.6, 2.6);
        rect(2.5, 11, 14, 10.5, 2.4);
      case 'outline':
        g.lineStyle(2.6 * s, c, a);
        g.drawRoundRect(4.5 * s, 4.5 * s, 15 * s, 15 * s, 4 * s, 4 * s);
        g.lineStyle();
      case 'solid':
        rect(4.5, 4.5, 15, 15, 2.4);
      case 'pen':
        poly([12, 2.4, 18.6, 12.4, 12, 21.6, 5.4, 12.4]);
        ink();
        rect(11.2, 9, 1.6, 8, 0.6);
        circle(12, 9, 1.6);
      case 'pixels':
        rect(3.5, 3.5, 8, 8, 1);
        rect(12.5, 12.5, 8, 8, 1);
        rect(12.5, 3.5, 8, 8, 1, 0.45);
        rect(3.5, 12.5, 8, 8, 1, 0.45);
      case 'guide':
        g.lineStyle(2 * s, c, a);
        for (i in 0...4)
        {
          g.moveTo((3 + i * 5) * s, 12 * s);
          g.lineTo((5.6 + i * 5) * s, 12 * s);
        }
        g.lineStyle();
        rect(10.6, 3, 2.8, 18, 1, 0.5);
      case 'zoom-in' | 'zoom-out':
        ring(10, 10, 6.4, 2.6);
        line(14.6, 14.6, 20.4, 20.4, 3.4);
        rect(6.8, 9, 6.4, 2, 0.6);
        if (name == 'zoom-in') rect(9, 6.8, 2, 6.4, 0.6);
      case 'rotate-left' | 'rotate-right':
        var left = name == 'rotate-left';
        arc(12, 13, 7, left ? 200 : -20, left ? 470 : 250, 2.6);
        if (left) poly([3.2, 6, 9.6, 6.4, 5.4, 11.6]);
        else
          poly([20.8, 6, 14.4, 6.4, 18.6, 11.6]);
      case 'flip':
        poly([10.5, 4, 10.5, 20, 2.5, 20]);
        poly([13.5, 4, 13.5, 20, 21.5, 20], 0.5);
        rect(11.2, 2, 1.6, 20, 0.6);
      case 'fit':
        g.lineStyle(2.4 * s, c, a);
        for (q in [[3.0, 8.0, 3.0, 3.0, 8.0, 3.0], [16.0, 3.0, 21.0, 3.0, 21.0, 8.0], [21.0, 16.0, 21.0, 21.0, 16.0, 21.0], [8.0, 21.0, 3.0, 21.0, 3.0, 16.0]])
        {
          g.moveTo(q[0] * s, q[1] * s);
          g.lineTo(q[2] * s, q[3] * s);
          g.lineTo(q[4] * s, q[5] * s);
        }
        g.lineStyle();
        rect(8, 8, 8, 8, 1.5);
      case 'clip':
        g.lineStyle(2 * s, c, a * 0.55);
        g.drawRect(2.5 * s, 2.5 * s, 19 * s, 19 * s);
        g.lineStyle();
        rect(6.5, 6.5, 11, 11, 1.5);
      case 'camera':
        rect(2.5, 7, 13.5, 11, 2.4);
        poly([16.5, 10.6, 21.8, 7.4, 21.8, 17.6, 16.5, 14.4]);
        circle(6.5, 4.6, 2.6);
        circle(12, 4.6, 2.6);
      case 'sound':
        poly([3, 9, 7.5, 9, 13, 4, 13, 20, 7.5, 15, 3, 15]);
        arc(13, 12, 4.5, -50, 50, 2);
        arc(13, 12, 8, -55, 55, 2);
      case 'palette':
        g.beginFill(c, a);
        g.moveTo(12 * s, 2.5 * s);
        g.curveTo(22 * s, 2.5 * s, 22 * s, 11 * s);
        g.curveTo(22 * s, 16 * s, 17 * s, 15.5 * s);
        g.curveTo(14 * s, 15.2 * s, 14.5 * s, 18 * s);
        g.curveTo(15 * s, 21.5 * s, 11 * s, 21.5 * s);
        g.curveTo(2 * s, 21.5 * s, 2 * s, 12 * s);
        g.curveTo(2 * s, 2.5 * s, 12 * s, 2.5 * s);
        g.endFill();
        var dots:Array<Array<Float>> = [[7.5, 9.5, 0xFF5C9D], [12, 6.5, 0xFFD84A], [17, 8.5, 0x5CE1FF], [7, 15, 0x6BE38E]];
        for (dot in dots)
        {
          g.beginFill(Std.int(dot[2]), 1);
          g.drawCircle(dot[0] * s, dot[1] * s, 2.1 * s);
          g.endFill();
        }
      case 'sparkle':
        poly([12, 1.5, 14, 10, 22.5, 12, 14, 14, 12, 22.5, 10, 14, 1.5, 12, 10, 10]);
      default:
        circle(12, 12, 6);
    }
  }
}
#end
