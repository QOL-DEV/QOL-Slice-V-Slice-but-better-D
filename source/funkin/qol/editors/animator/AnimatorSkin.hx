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

/**
 * The Animator's look: a purple/pink theme matching the Mod Menu (scoped to the Animator's screen), hand-drawn vector
 * icons for tools and buttons, and the color palettes.
 *
 * Icons are drawn once with OpenFL vector graphics and cached as persistent graphics.
 */
class AnimatorSkin
{
  // Palette.
  public static inline final BG_TOP:Int = 0xFF241A46;
  public static inline final BG_BOTTOM:Int = 0xFF120D24;
  public static inline final PANEL:Int = 0xFF1E1838;
  public static inline final PANEL_DARK:Int = 0xFF16112B;
  public static inline final BORDER:Int = 0xFF3D3366;
  public static inline final INK:Int = 0xFF1A1030;
  public static inline final PINK:Int = 0xFFFF5C9D;
  public static inline final PURPLE:Int = 0xFF9B6BFF;
  public static inline final CYAN:Int = 0xFF5CE1FF;
  public static inline final YELLOW:Int = 0xFFFFD84A;
  public static inline final GREEN:Int = 0xFF6BE38E;
  public static inline final TEXT:Int = 0xFFEDE6FF;
  public static inline final TEXT_DIM:Int = 0xFFA99CD6;

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

  public static function loadCss():Void
  {
    if (cssLoaded) return;
    cssLoaded = true;
    var css = new StringBuf();
    css.add('
.anim-ui .label { color: #DCD3FF; }
.anim-ui .button {
  background: #3A2F6B #2A2252 vertical; color: #EDE6FF; border: 1px solid #54479A; border-radius: 7px;
}
.anim-ui .button:hover { background: #4A3C85 #352A63 vertical; border: 1px solid #FF7FB4; color: #FFFFFF; }
.anim-ui .button:down { background: #FF6FA8 #D9407E vertical; border: 1px solid #FFB3D1; color: #FFFFFF; }
.anim-ui .button:disabled { background: #2A2445 #241E3B vertical; color: #6E6497; border: 1px solid #3A3260; }
.anim-ui .dropdown { background: #2A2252 #221B45 vertical; border: 1px solid #54479A; border-radius: 7px; color: #EDE6FF; }
.anim-ui .dropdown:hover { border: 1px solid #FF7FB4; }
.anim-ui .textfield, .anim-ui .textarea {
  background-color: #15112A; color: #F4EFFF; border: 1px solid #4A3F85; border-radius: 6px; filter: none;
}
.anim-ui .textfield:active, .anim-ui .textarea:active { border: 1px solid #FF7FB4; }
.anim-ui .number-stepper { border-radius: 6px; }
.anim-ui .checkbox { color: #DCD3FF; }
.anim-ui .checkbox-value { background-color: #15112A; border: 1px solid #54479A; border-radius: 5px; filter: none; }
.anim-ui .checkbox-value:hover { border: 1px solid #FF7FB4; }
.anim-ui .checkbox-value:selected { background-color: #FF5C9D; border: 1px solid #FFB3D1; }
.anim-ui .horizontal-range { background: #15112A #1D1738 vertical; border: 1px solid #3D3366; border-radius: 5px; filter: none; }
.anim-ui .horizontal-range .range-value { background: #FF5C9D #9B6BFF horizontal; border-radius: 4px; }
.anim-ui .horizontal-slider .button { background: #FFFFFF #E3DBFF vertical; border: 1px solid #FF5C9D; border-radius: 6px; width: 12px; height: 18px; }
.anim-ui .horizontal-slider:active .button { border: 1px solid #FFFFFF; }
.anim-ui .section-header .label { color: #FF8FC0; font-bold: true; }
.anim-ui .section-header .line { background-color: #3D3366; border-color: #3D3366; }
.anim-ui .tabbar { border-bottom-color: #3D3366; }
.anim-ui .tabbar > .tabbar-contents { border-bottom-color: #3D3366; }
.anim-ui .tabbar-button {
  background: #221B42 #1C1638 vertical; color: #A99CD6; border: 1px solid #3D3366; border-radius: 0px; border-top: 2px solid #2E2558;
}
.anim-ui .tabbar-button:hover { background: #2C2354 #241D47 vertical; color: #FFFFFF; }
.anim-ui .tabbar-button-selected, .anim-ui .tabbar-button-selected:hover {
  background: #2C2354 #2C2354 vertical; color: #FFFFFF; border: 1px solid #3D3366; border-top: 2px solid #FF5C9D; border-bottom-color: #2C2354;
}
.anim-ui .tabbar-button-selected .label { color: #FFFFFF; }
.anim-ui .tabview > .tabview-content { background-color: #2C2354; border: 1px solid #3D3366; }
.anim-ui .listview { background-color: #15112A; border: 1px solid #3D3366; border-radius: 6px; }
.anim-ui .listview .even, .anim-ui .listview .odd { background-color: #15112A; }
.anim-ui .listview .even:hover, .anim-ui .listview .odd:hover { background-color: #2A2252; }
.anim-ui .listview .listview-contents > .itemrenderer:selected { background-color: #FF5C9D; }
.anim-ui .listview .listview-contents > .itemrenderer:selected .label { color: #FFFFFF; }
.anim-ui .menubar { background: #2A1F52 #1D1638 vertical; border-bottom: 1px solid #3D3366; }
.anim-ui .menubar-button { background-color: #2A1F52; color: #EDE6FF; }
.anim-ui .menubar-button:hover { background-color: #FF5C9D; color: #FFFFFF; }
.anim-ui .vertical-scroll .thumb, .anim-ui .horizontal-scroll .thumb { background-color: #54479A; border: none; border-radius: 4px; }
.anim-ui .vertical-scroll .thumb:hover, .anim-ui .horizontal-scroll .thumb:hover { background-color: #FF7FB4; }
.anim-ui .vertical-scroll, .anim-ui .horizontal-scroll { background-color: #17122E; border: none; }

.anim-ui .anim-tool { background: #2E2558 #241D47 vertical; border: 1px solid #44397A; border-radius: 9px; padding: 0px; }
.anim-ui .anim-tool:hover { background: #3C3070 #2E2558 vertical; border: 1px solid #FFFFFF; }
.anim-ui .anim-icon-button { padding: 3px 6px; }
.anim-ui .anim-play { background: #FF7FB4 #E0457F vertical; border: 1px solid #FFC2DA; border-radius: 13px; }
.anim-ui .anim-play:hover { background: #FF96C2 #EA5A8E vertical; border: 1px solid #FFFFFF; }
.anim-ui .anim-on { background: #FF6FA8 #C93B74 vertical; border: 1px solid #FFB3D1; }
.anim-ui .anim-on:hover { background: #FF85B6 #D44A80 vertical; border: 1px solid #FFFFFF; }
.anim-ui .anim-swatch { border: 2px solid #15112A; border-radius: 6px; cursor: pointer; }
.anim-ui .anim-swatch:hover { border: 2px solid #FFFFFF; }
.anim-ui .anim-note { color: #A99CD6; font-size: 11px; }

.menu.anim-popup { background-color: #1E1838; border: 1px solid #54479A; border-radius: 8px; padding: 4px; }
.anim-popup .menuitem { background-color: #1E1838; border-radius: 5px; }
.anim-popup .menuitem:hover, .anim-popup .menuitem:selected { background: #FF6FA8 #D9407E vertical; }
.anim-popup .menuitem-label, .anim-popup .menuitem .label { color: #EDE6FF; }
.anim-popup .menuitem-shortcut-label { color: #A99CD6; }
.anim-popup .menuitem .label:hover, .anim-popup .menuitem .label:selected { color: #FFFFFF; }
.anim-popup .menuseparator-line { background-color: #3D3366; }
.dialog.anim-popup { background-color: #1E1838; border: 1px solid #6A5BB8; border-radius: 12px; padding: 0px; }
.anim-popup .dialog-title { background: #FF5C9D #9B6BFF horizontal; border-top-left-radius: 11px; border-top-right-radius: 11px; }
.anim-popup .dialog-title-label { color: #FFFFFF; font-bold: true; }
.anim-popup .dialog-footer-container { background-color: #17122E; border-bottom-left-radius: 11px; border-bottom-right-radius: 11px; }
');
    // Active tool tiles take the tool's color.
    for (id => c in TOOL_COLORS)
    {
      css.add('.anim-ui .anim-tool-on-$id, .anim-ui .anim-tool-on-$id:hover { background: ${hex(lighten(c, 0.18))} ${hex(darken(c, 0.12))} vertical; '
        + 'border: 1px solid ${hex(lighten(c, 0.55))}; }\n');
    }
    // Colored action buttons.
    for (name => c in ['cyan' => CYAN, 'green' => GREEN, 'yellow' => YELLOW, 'purple' => PURPLE, 'red' => 0xFFFF6B6B, 'pink' => PINK])
    {
      css.add('.anim-ui .anim-btn-$name { border: 1px solid ${hex(darken(c, 0.25))}; }\n');
      css.add('.anim-ui .anim-btn-$name:hover { background: ${hex(lighten(c, 0.05))} ${hex(darken(c, 0.2))} vertical; border: 1px solid ${hex(lighten(c, 0.5))}; color: #1A1030; }\n');
    }
    haxe.ui.Toolkit.styleSheet.parse(css.toString(), 'qol-animator');
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
      case 'sparkle':
        poly([12, 1.5, 14, 10, 22.5, 12, 14, 14, 12, 22.5, 10, 14, 1.5, 12, 10, 10]);
      default:
        circle(12, 12, 6);
    }
  }
}
#end
