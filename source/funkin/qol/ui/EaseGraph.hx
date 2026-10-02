package funkin.qol.ui;

import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxFrame;
import flixel.graphics.frames.FlxImageFrame;
import openfl.display.BitmapData;
import openfl.display.Shape;
import funkin.qol.util.QOLEase;

/**
 * Draws little ease-curve thumbnails (used by the Ease Picker and every ease field).
 * Curves are drawn once and cached, so showing all of them costs nothing per frame.
 */
class EaseGraph
{
  static var cache:Map<String, FlxFrame> = new Map<String, FlxFrame>();

  public static var CURVE_COLOR:Int = 0x5CC8FF;
  public static var GRID_COLOR:Int = 0x3A3F47;

  /**
   * Render an ease curve. The graph leaves headroom for eases that overshoot (back / elastic).
   */
  public static function render(ease:String, width:Int, height:Int, ?curveColor:Int, bg:Int = 0x00000000, thickness:Float = 2):BitmapData
  {
    var bmp = new BitmapData(width, height, true, bg);
    var shape = new Shape();
    var g = shape.graphics;

    var padX = 2.0;
    var padTop = height * 0.18;
    var padBottom = height * 0.18;
    var w = width - padX * 2;
    var h = height - padTop - padBottom;

    // Baseline + target line.
    g.lineStyle(1, GRID_COLOR, 1);
    g.moveTo(padX, padTop + h);
    g.lineTo(padX + w, padTop + h);
    g.moveTo(padX, padTop);
    g.lineTo(padX + w, padTop);

    g.lineStyle(thickness, curveColor ?? CURVE_COLOR, 1);
    var steps = Std.int(Math.max(24, width));
    var fn = QOLEase.get(ease);
    for (i in 0...steps + 1)
    {
      var t = i / steps;
      var v = ease == 'INSTANT' ? (t > 0 ? 1.0 : 0.0) : fn(t);
      var px = padX + t * w;
      var py = padTop + h - v * h;
      py = Math.max(1, Math.min(height - 1, py));
      if (i == 0) g.moveTo(px, py);
      else
        g.lineTo(px, py);
    }
    bmp.draw(shape, null, null, null, null, true);
    return bmp;
  }

  /**
   * Get a cached FlxFrame of an ease curve, usable as a HaxeUI image/icon resource.
   */
  public static function frame(ease:String, width:Int, height:Int, ?curveColor:Int):FlxFrame
  {
    var key = '$ease:$width:$height:${curveColor ?? CURVE_COLOR}';
    var existing = cache.get(key);
    if (existing != null && existing.parent != null && existing.parent.bitmap != null) return existing;
    var graphic = FlxGraphic.fromBitmapData(render(ease, width, height, curveColor), false, 'qol-ease-$key');
    graphic.persist = true;
    graphic.destroyOnNoUse = false;
    var f = FlxImageFrame.fromImage(graphic).frame;
    cache.set(key, f);
    return f;
  }
}
