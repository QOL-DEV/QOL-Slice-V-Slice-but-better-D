package funkin.qol.ui;

import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import openfl.display.BitmapData;
import openfl.display.Shape;
import openfl.geom.Matrix;

/**
 * Shared colors, fonts and pre-rendered shapes for QOL Slice's own game-styled screens.
 *
 * Every shape is drawn once and cached in Flixel's bitmap cache (as a persistent graphic),
 * so opening a menu again doesn't redraw anything.
 */
class QOLTheme
{
  public static final BG_DARK:FlxColor = 0xFF16171B;
  public static final PANEL:FlxColor = 0xF0201A33;
  public static final PANEL_LIGHT:FlxColor = 0xFF3B3355;
  public static final BORDER:FlxColor = 0xFF5A4F80;
  public static final TEXT:FlxColor = 0xFFFFFFFF;
  public static final TEXT_DIM:FlxColor = 0xFFC9C2E6;
  public static final ACCENT:FlxColor = 0xFF5CE1FF;
  public static final ACCENT_PINK:FlxColor = 0xFFFF5C9D;
  public static final ACCENT_YELLOW:FlxColor = 0xFFFFD84A;
  public static final GOOD:FlxColor = 0xFF7CE38B;
  public static final BAD:FlxColor = 0xFFFF6B6B;

  public static var FONT_TITLE(get, never):String;

  static function get_FONT_TITLE():String
    return Paths.font('Quantico-Bold.ttf');

  public static var FONT_BODY(get, never):String;

  static function get_FONT_BODY():String
    return Paths.font('Quantico-Regular.ttf');

  public static var FONT_MONO(get, never):String;

  static function get_FONT_MONO():String
    return Paths.font('Inconsolata-Medium.ttf');

  public static function text(x:Float, y:Float, width:Float, content:String, size:Int = 16, ?font:String, ?color:FlxColor):FlxText
  {
    var t = new FlxText(x, y, width, content, size);
    t.font = font ?? FONT_BODY;
    t.color = color ?? TEXT;
    t.antialiasing = true;
    return t;
  }

  /**
   * FNF-style text: white with a thick dark outline.
   */
  public static function outlinedText(x:Float, y:Float, width:Float, content:String, size:Int = 16, ?color:FlxColor, outline:Float = 2):FlxText
  {
    var t = text(x, y, width, content, size, FONT_TITLE, color);
    t.setBorderStyle(OUTLINE, 0xFF1A1030, outline);
    return t;
  }

  //
  // Cached graphics
  //

  /**
   * Get a cached graphic by key, or build it with `make` the first time.
   */
  public static function cached(key:String, make:Void->BitmapData):FlxGraphic
  {
    var existing = FlxG.bitmap.get(key);
    if (existing != null && existing.bitmap != null) return existing;
    var graphic = FlxGraphic.fromBitmapData(make(), false, key);
    graphic.persist = true;
    graphic.destroyOnNoUse = false;
    return graphic;
  }

  static function spriteFrom(graphic:FlxGraphic):FlxSprite
  {
    var spr = new FlxSprite().loadGraphic(graphic);
    spr.antialiasing = true;
    return spr;
  }

  static inline function hex(c:FlxColor):String
    return StringTools.hex(c, 8);

  /**
   * Draws a rounded rectangle into a new bitmap.
   */
  static function drawRound(width:Int, height:Int, color:FlxColor, radius:Float, ?borderColor:FlxColor, borderThickness:Float = 2):BitmapData
  {
    var shape = new Shape();
    var g = shape.graphics;
    if (borderColor != null)
    {
      g.beginFill(borderColor.rgb, borderColor.alphaFloat);
      g.drawRoundRect(0, 0, width, height, radius * 2, radius * 2);
      g.endFill();
      g.beginFill(color.rgb, color.alphaFloat);
      g.drawRoundRect(borderThickness, borderThickness, width - borderThickness * 2, height - borderThickness * 2, (radius - borderThickness) * 2,
        (radius - borderThickness) * 2);
      g.endFill();
    }
    else
    {
      g.beginFill(color.rgb, color.alphaFloat);
      g.drawRoundRect(0, 0, width, height, radius * 2, radius * 2);
      g.endFill();
    }
    var bmp = new BitmapData(width, height, true, 0);
    bmp.draw(shape, null, null, null, null, true);
    return bmp;
  }

  /**
   * A rounded rectangle sprite (optionally with a border).
   */
  public static function roundRect(width:Int, height:Int, color:FlxColor, radius:Float = 12, ?borderColor:FlxColor, borderThickness:Float = 2):FlxSprite
  {
    var key = 'qol-rr-$width-$height-${hex(color)}-$radius-${borderColor == null ? 'none' : hex(borderColor)}-$borderThickness';
    return spriteFrom(cached(key, () -> drawRound(width, height, color, radius, borderColor, borderThickness)));
  }

  /**
   * A rounded rectangle filled with a linear gradient (angle in radians, 0 = left to right, PI/2 = top to bottom).
   */
  public static function gradientRoundRect(width:Int, height:Int, colorA:FlxColor, colorB:FlxColor, radius:Float = 16, angleRadians:Float = 0):FlxSprite
  {
    var key = 'qol-grr-$width-$height-${hex(colorA)}-${hex(colorB)}-$radius-$angleRadians';
    return spriteFrom(cached(key, () -> {
      var shape = new Shape();
      var m = new Matrix();
      m.createGradientBox(width, height, angleRadians);
      shape.graphics.beginGradientFill(LINEAR, [colorA.rgb, colorB.rgb], [colorA.alphaFloat, colorB.alphaFloat], [0, 255], m);
      shape.graphics.drawRoundRect(0, 0, width, height, radius * 2, radius * 2);
      shape.graphics.endFill();
      var bmp = new BitmapData(width, height, true, 0);
      bmp.draw(shape, null, null, null, null, true);
      return bmp;
    }));
  }

  /**
   * A chunky "3D" button/tile: a darker lip along the bottom, a glossy top and an outline.
   * `lit` renders the highlighted version (brighter, with a white outline).
   */
  public static function buttonGraphic(width:Int, height:Int, color:FlxColor, lit:Bool, radius:Float = 14, lip:Int = 6):FlxSprite
  {
    var key = 'qol-btn-$width-$height-${hex(color)}-$lit-$radius-$lip';
    return spriteFrom(cached(key, () -> {
      var shape = new Shape();
      var g = shape.graphics;
      var outline:FlxColor = lit ? 0xFFFFFFFF : 0xFF1A1030;
      var ot = lit ? 4.0 : 3.0;
      var top:FlxColor = lit ? color.getLightened(0.12) : color;
      var bottom:FlxColor = color.getDarkened(0.28);
      var lipColor:FlxColor = color.getDarkened(0.5);

      // Outline (whole shape).
      g.beginFill(outline.rgb, 1);
      g.drawRoundRect(0, 0, width, height, radius * 2, radius * 2);
      g.endFill();
      // Lip.
      g.beginFill(lipColor.rgb, 1);
      g.drawRoundRect(ot, ot, width - ot * 2, height - ot * 2, (radius - ot) * 2, (radius - ot) * 2);
      g.endFill();
      // Face (gradient top -> bottom).
      var m = new Matrix();
      m.createGradientBox(width, height - lip, Math.PI / 2);
      g.beginGradientFill(LINEAR, [top.rgb, bottom.rgb], [1, 1], [0, 255], m);
      g.drawRoundRect(ot, ot, width - ot * 2, height - ot * 2 - lip, (radius - ot) * 2, (radius - ot) * 2);
      g.endFill();
      // Gloss.
      g.beginFill(0xFFFFFF, lit ? 0.22 : 0.14);
      g.drawRoundRect(ot + 4, ot + 3, width - ot * 2 - 8, (height - lip) * 0.38, (radius - ot) * 2, (radius - ot) * 2);
      g.endFill();

      var bmp = new BitmapData(width, height, true, 0);
      bmp.draw(shape, null, null, null, null, true);
      return bmp;
    }));
  }

  /**
   * A little grid that scrolls diagonally across a button's face (`buttonGraphic` with the same size).
   * All `cell` steps of the scroll are baked once into one cached strip, so playing it costs no more than an animated icon.
   * @param alpha How visible the grid lines are (0-255 at the top of the face; they fade toward the bottom).
   */
  public static function scrollGrid(width:Int, height:Int, ?lip:Int = 6, ?radius:Float = 14, ?cell:Int = 16, ?alpha:Int = 40):FlxSprite
  {
    var key = 'qol-grid-$width-$height-$lip-$radius-$cell-$alpha';
    var graphic = cached(key, () -> {
      var inset = 4;
      var fx = inset;
      var fy = inset;
      var fw = width - inset * 2;
      var fh = height - inset * 2 - lip;
      var r = Math.max(0, radius - inset);
      var bytes = new openfl.utils.ByteArray(width * cell * height * 4);
      for (py in 0...height)
      {
        for (k in 0...cell)
        {
          for (px in 0...width)
          {
            var a = 0;
            if (insideRounded(px + 0.5, py + 0.5, fx, fy, fw, fh, r))
            {
              var gx = (px - k) % cell;
              if (gx < 0) gx += cell;
              var gy = (py - k) % cell;
              if (gy < 0) gy += cell;
              if (gx == 0 || gy == 0)
              {
                var fade = 1 - 0.55 * Math.max(0, Math.min(1, (py - fy) / fh));
                a = Std.int((gx == 0 && gy == 0 ? alpha * 2.4 : alpha) * fade);
                if (a > 255) a = 255;
              }
            }
            bytes.writeUnsignedInt((a << 24) | 0xFFFFFF);
          }
        }
      }
      bytes.position = 0;
      var bmp = new BitmapData(width * cell, height, true, 0);
      bmp.setPixels(new openfl.geom.Rectangle(0, 0, width * cell, height), bytes);
      return bmp;
    });
    var spr = new FlxSprite();
    spr.loadGraphic(graphic, true, width, height);
    spr.animation.add('scroll', [for (i in 0...cell) i], 18, true);
    spr.animation.play('scroll');
    if (!QOLConfig.fancyMenus) spr.animation.pause();
    spr.antialiasing = false;
    return spr;
  }

  static function insideRounded(x:Float, y:Float, fx:Float, fy:Float, fw:Float, fh:Float, r:Float):Bool
  {
    if (x < fx || y < fy || x >= fx + fw || y >= fy + fh) return false;
    var cx = Math.max(fx + r, Math.min(x, fx + fw - r));
    var cy = Math.max(fy + r, Math.min(y, fy + fh - r));
    var dx = x - cx;
    var dy = y - cy;
    return dx * dx + dy * dy <= r * r;
  }

  /**
   * A soft drop shadow to put under tiles/panels.
   */
  public static function shadow(width:Int, height:Int, radius:Float = 14, alpha:Float = 0.45):FlxSprite
  {
    var spr = roundRect(width, height, FlxColor.fromRGBFloat(0.04, 0.02, 0.1, alpha), radius);
    return spr;
  }

  /**
   * An outline-only rounded rectangle (used for selection glows).
   */
  public static function outline(width:Int, height:Int, color:FlxColor, radius:Float = 16, thickness:Float = 4):FlxSprite
  {
    var key = 'qol-ol-$width-$height-${hex(color)}-$radius-$thickness';
    return spriteFrom(cached(key, () -> {
      var shape = new Shape();
      shape.graphics.lineStyle(thickness, color.rgb, color.alphaFloat);
      shape.graphics.drawRoundRect(thickness / 2, thickness / 2, width - thickness, height - thickness, radius * 2, radius * 2);
      var bmp = new BitmapData(width, height, true, 0);
      bmp.draw(shape, null, null, null, null, true);
      return bmp;
    }));
  }

  /**
   * A circle sprite.
   */
  public static function circle(radius:Int, color:FlxColor):FlxSprite
  {
    var key = 'qol-circle-$radius-${hex(color)}';
    return spriteFrom(cached(key, () -> {
      var shape = new Shape();
      shape.graphics.beginFill(color.rgb, color.alphaFloat);
      shape.graphics.drawCircle(radius, radius, radius);
      shape.graphics.endFill();
      var bmp = new BitmapData(radius * 2, radius * 2, true, 0);
      bmp.draw(shape, null, null, null, null, true);
      return bmp;
    }));
  }

  /**
   * A diamond (keyframe marker) sprite.
   */
  public static function diamond(size:Int, color:FlxColor, ?borderColor:FlxColor):FlxSprite
  {
    var key = 'qol-diamond-$size-${hex(color)}-${borderColor == null ? 'none' : hex(borderColor)}';
    return spriteFrom(cached(key, () -> {
      var shape = new Shape();
      var h = size / 2;
      if (borderColor != null) shape.graphics.lineStyle(1.5, borderColor.rgb, 1);
      shape.graphics.beginFill(color.rgb, color.alphaFloat);
      shape.graphics.moveTo(h, 1);
      shape.graphics.lineTo(size - 1, h);
      shape.graphics.lineTo(h, size - 1);
      shape.graphics.lineTo(1, h);
      shape.graphics.lineTo(h, 1);
      shape.graphics.endFill();
      var bmp = new BitmapData(size, size, true, 0);
      bmp.draw(shape, null, null, null, null, true);
      return bmp;
    }));
  }

  /**
   * A tileable diagonal-stripe pattern (for scrolling backdrops). Tiny, so it's basically free to draw.
   */
  public static function stripeTile(size:Int, color:FlxColor):FlxGraphic
  {
    var key = 'qol-stripes-$size-${hex(color)}';
    return cached(key, () -> {
      var shape = new Shape();
      shape.graphics.beginFill(color.rgb, color.alphaFloat);
      var w = size / 4;
      // Two parallel diagonal bands that wrap seamlessly.
      for (offset in [-size, 0, size])
      {
        shape.graphics.moveTo(offset, size);
        shape.graphics.lineTo(offset + w, size);
        shape.graphics.lineTo(offset + w + size, 0);
        shape.graphics.lineTo(offset + size, 0);
        shape.graphics.lineTo(offset, size);
      }
      shape.graphics.endFill();
      var bmp = new BitmapData(size, size, true, 0);
      bmp.draw(shape, null, null, null, null, true);
      return bmp;
    });
  }

  /**
   * A checkerboard tile (two squares).
   */
  public static function checkerTile(cell:Int, colorA:FlxColor, colorB:FlxColor):FlxGraphic
  {
    var key = 'qol-checker-$cell-${hex(colorA)}-${hex(colorB)}';
    return cached(key, () -> {
      var bmp = new BitmapData(cell * 2, cell * 2, true, colorA);
      bmp.fillRect(new openfl.geom.Rectangle(cell, 0, cell, cell), colorB);
      bmp.fillRect(new openfl.geom.Rectangle(0, cell, cell, cell), colorB);
      return bmp;
    });
  }

  /**
   * Scales an AtlasText (the bold FNF alphabet) around its top-left corner.
   */
  public static function scaleAtlasText(t:funkin.ui.AtlasText, scale:Float):Void
  {
    for (member in t.members)
    {
      if (member == null) continue;
      member.scale.set(scale, scale);
      member.updateHitbox();
      member.x = t.x + (member.x - t.x) * scale;
      member.y = t.y + (member.y - t.y) * scale;
    }
  }

  /**
   * Loads a health icon (any size: 300x150 two-frame, 150x150 single, 64x32 pixel) and shows its first frame.
   */
  public static function loadIcon(spr:FlxSprite, key:String, size:Int):FlxSprite
  {
    try
    {
      var graphic = FlxG.bitmap.add(Paths.image(key));
      if (graphic != null)
      {
        var fs = graphic.height;
        spr.loadGraphic(graphic, true, fs, fs);
        spr.animation.add('idle', [0], 0, false);
        spr.animation.play('idle');
        spr.antialiasing = fs > 48;
      }
    }
    catch (e) {}
    spr.setGraphicSize(size, size);
    spr.updateHitbox();
    return spr;
  }

  /**
   * A character's health icon (configured from the character's data), fitted into a `size` square.
   * Returns null if the character can't be found.
   */
  public static function healthIcon(charId:String, size:Int, faceRight:Bool = false):Null<funkin.play.components.HealthIcon>
  {
    try
    {
      var data = funkin.data.character.CharacterData.CharacterDataParser.fetchCharacterData(charId);
      var icon = new funkin.play.components.HealthIcon(data?.healthIcon?.id ?? charId, 0);
      @:privateAccess icon.autoUpdate = false;
      icon.configure(data?.healthIcon);
      icon.playAnimation('idle', 'idle');
      if (faceRight) icon.flipX = !icon.flipX;
      icon.bopTween?.cancel();
      icon.setGraphicSize(size, size);
      icon.updateHitbox();
      return icon;
    }
    catch (e)
    {
      trace('[QOL] Health icon failed for $charId: $e');
      return null;
    }
  }
}
