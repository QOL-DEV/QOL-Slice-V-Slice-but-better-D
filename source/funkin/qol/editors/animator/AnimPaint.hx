package funkin.qol.editors.animator;

import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.display.Shape;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.utils.ByteArray;

/**
 * Painting on bitmap layers: soft and hard brushes, the eraser, pixel pencil and a paint bucket with a tolerance.
 */
class AnimPaint
{
  static var stamp:Shape = new Shape();
  static var stampMatrix:Matrix = new Matrix();
  static var stampColor:ColorTransform = new ColorTransform();
  static var lastSize:Float = -1;
  static var lastHardness:Float = -1;

  static function prepareStamp(size:Float, hardness:Float):Void
  {
    if (size == lastSize && hardness == lastHardness) return;
    lastSize = size;
    lastHardness = hardness;
    var g = stamp.graphics;
    g.clear();
    var r = Math.max(0.5, size / 2);
    if (hardness >= 0.99 || r < 2)
    {
      g.beginFill(0xFFFFFF, 1);
      g.drawCircle(0, 0, r);
      g.endFill();
    }
    else
    {
      // Soft edge: a few rings getting fainter towards the outside.
      var rings = 6;
      for (i in 0...rings)
      {
        var t = i / rings;
        var rr = r * (1 - t * (1 - hardness));
        g.beginFill(0xFFFFFF, 1 / rings + (t * 0.05));
        g.drawCircle(0, 0, rr);
        g.endFill();
      }
    }
  }

  /**
   * Paint a line of brush dabs from (x0, y0) to (x1, y1) (canvas pixels).
   */
  public static function strokeLine(bmp:BitmapData, x0:Float, y0:Float, x1:Float, y1:Float, size:Float, color:Int, opacity:Float, hardness:Float,
      erase:Bool, ?skipFirst:Bool = false):Void
  {
    prepareStamp(size, hardness);
    stampColor.redMultiplier = stampColor.greenMultiplier = stampColor.blueMultiplier = 0;
    stampColor.redOffset = (color >> 16) & 0xFF;
    stampColor.greenOffset = (color >> 8) & 0xFF;
    stampColor.blueOffset = color & 0xFF;
    stampColor.alphaMultiplier = opacity;
    var dx = x1 - x0, dy = y1 - y0;
    var dist = Math.sqrt(dx * dx + dy * dy);
    var spacing = Math.max(0.5, size * 0.18);
    var steps = Std.int(Math.max(1, Math.ceil(dist / spacing)));
    var blend = erase ? BlendMode.ERASE : BlendMode.NORMAL;
    for (s in (skipFirst ? 1 : 0)...steps + 1)
    {
      var t = s / steps;
      stampMatrix.identity();
      stampMatrix.translate(x0 + dx * t, y0 + dy * t);
      bmp.draw(stamp, stampMatrix, stampColor, blend, null, true);
    }
  }

  /**
   * Hard square pixels (pixel-art pencil). Size 1 = single pixels.
   */
  public static function pixelLine(bmp:BitmapData, x0:Float, y0:Float, x1:Float, y1:Float, size:Int, color:Int, erase:Bool):Void
  {
    var ix0 = Math.floor(x0), iy0 = Math.floor(y0), ix1 = Math.floor(x1), iy1 = Math.floor(y1);
    var dx = Std.int(Math.abs(ix1 - ix0)), dy = -Std.int(Math.abs(iy1 - iy0));
    var sx = ix0 < ix1 ? 1 : -1, sy = iy0 < iy1 ? 1 : -1;
    var err = dx + dy;
    var x = ix0, y = iy0;
    var half = Std.int(size / 2);
    var rect = new Rectangle();
    var argb = erase ? 0 : (0xFF000000 | (color & 0xFFFFFF));
    bmp.lock();
    var guard = 0;
    while (guard++ < 100000)
    {
      rect.setTo(x - half, y - half, size, size);
      bmp.fillRect(rect, argb);
      if (x == ix1 && y == iy1) break;
      var e2 = 2 * err;
      if (e2 >= dy)
      {
        err += dy;
        x += sx;
      }
      if (e2 <= dx)
      {
        err += dx;
        y += sy;
      }
    }
    bmp.unlock();
  }

  /**
   * Draw a vector shape (from the shape tools) into a bitmap.
   */
  public static function drawShape(bmp:BitmapData, shape:openfl.display.DisplayObject, erase:Bool = false):Void
  {
    bmp.draw(shape, null, null, erase ? BlendMode.ERASE : BlendMode.NORMAL, null, true);
  }

  /**
   * Paint bucket with a color tolerance (0-255). Fills pixels connected to (x, y) that look like the clicked one.
   * `gap` grows the fill a little under anti-aliased edges.
   */
  public static function floodFill(bmp:BitmapData, x:Int, y:Int, color:Int, tolerance:Int, gap:Int = 1):Bool
  {
    var w = bmp.width, h = bmp.height;
    if (x < 0 || y < 0 || x >= w || y >= h) return false;
    var mask = fillMask(bmp, x, y, tolerance);
    if (mask == null) return false;
    if (gap > 0) mask = grow(mask, w, h, gap);
    var argb = 0xFF000000 | (color & 0xFFFFFF);
    var alpha = (color >>> 24) & 0xFF;
    if (alpha > 0 && alpha < 255) argb = (alpha << 24) | (color & 0xFFFFFF);
    bmp.lock();
    var pixels = bmp.getPixels(new Rectangle(0, 0, w, h));
    pixels.position = 0;
    for (i in 0...w * h)
    {
      if (mask.get(i) == 0) continue;
      var p = i * 4;
      // ARGB bytes; blend over what's there (so anti-aliased lines stay smooth).
      var srcA = (argb >>> 24) & 0xFF;
      var dstA = pixels[p];
      var outA = srcA + dstA * (255 - srcA) / 255;
      if (outA <= 0) continue;
      for (ch in 0...3)
      {
        var s = (argb >> (16 - ch * 8)) & 0xFF;
        var d = pixels[p + 1 + ch];
        pixels[p + 1 + ch] = Std.int((s * srcA + d * dstA * (255 - srcA) / 255) / outA);
      }
      pixels[p] = Std.int(outA);
    }
    pixels.position = 0;
    bmp.setPixels(new Rectangle(0, 0, w, h), pixels);
    bmp.unlock();
    return true;
  }

  /**
   * Which pixels a paint bucket click at (x, y) would fill (1 byte per pixel).
   */
  public static function fillMask(bmp:BitmapData, x:Int, y:Int, tolerance:Int):Null<haxe.io.Bytes>
  {
    var w = bmp.width, h = bmp.height;
    var pixels:ByteArray = bmp.getPixels(new Rectangle(0, 0, w, h));
    inline function px(i:Int):Int
      return (pixels[i * 4] << 24) | (pixels[i * 4 + 1] << 16) | (pixels[i * 4 + 2] << 8) | pixels[i * 4 + 3];
    var target = px(y * w + x);
    var ta = (target >>> 24) & 0xFF, tr = (target >> 16) & 0xFF, tg = (target >> 8) & 0xFF, tb = target & 0xFF;
    inline function similar(c:Int):Bool
    {
      var a = (c >>> 24) & 0xFF;
      // Two transparent pixels match whatever their (invisible) color is.
      if (a < 8 && ta < 8) return true;
      return Math.abs(a - ta) <= tolerance && Math.abs(((c >> 16) & 0xFF) - tr) <= tolerance && Math.abs(((c >> 8) & 0xFF) - tg) <= tolerance
        && Math.abs((c & 0xFF) - tb) <= tolerance;
    }
    var mask = haxe.io.Bytes.alloc(w * h);
    var stack:Array<Int> = [y * w + x];
    var count = 0;
    while (stack.length > 0)
    {
      var i = stack.pop();
      if (mask.get(i) != 0) continue;
      var cy = Std.int(i / w);
      var cx = i - cy * w;
      // Scanline: go left then right.
      var lx = cx;
      while (lx > 0 && mask.get(cy * w + lx - 1) == 0 && similar(px(cy * w + lx - 1)))
        lx--;
      var rx = cx;
      while (rx < w - 1 && mask.get(cy * w + rx + 1) == 0 && similar(px(cy * w + rx + 1)))
        rx++;
      if (!similar(px(i)) && mask.get(i) == 0 && count > 0) continue;
      for (xx in lx...rx + 1)
      {
        mask.set(cy * w + xx, 1);
        count++;
        if (cy > 0)
        {
          var up = (cy - 1) * w + xx;
          if (mask.get(up) == 0 && similar(px(up))) stack.push(up);
        }
        if (cy < h - 1)
        {
          var dn = (cy + 1) * w + xx;
          if (mask.get(dn) == 0 && similar(px(dn))) stack.push(dn);
        }
      }
    }
    return count > 0 ? mask : null;
  }

  /**
   * Grow a mask by `r` pixels.
   */
  public static function grow(mask:haxe.io.Bytes, w:Int, h:Int, r:Int):haxe.io.Bytes
  {
    var cur = mask;
    for (_ in 0...r)
    {
      var next = haxe.io.Bytes.alloc(w * h);
      for (y in 0...h)
      {
        for (x in 0...w)
        {
          var i = y * w + x;
          if (cur.get(i) != 0 || (x > 0 && cur.get(i - 1) != 0) || (x < w - 1 && cur.get(i + 1) != 0) || (y > 0 && cur.get(i - w) != 0)
            || (y < h - 1 && cur.get(i + w) != 0)) next.set(i, 1);
        }
      }
      cur = next;
    }
    return cur;
  }

  /**
   * Color under a point (ARGB).
   */
  public static function pick(bmp:BitmapData, x:Int, y:Int):Int
  {
    if (x < 0 || y < 0 || x >= bmp.width || y >= bmp.height) return 0;
    return bmp.getPixel32(x, y);
  }

  /**
   * Bounds of the non-transparent pixels (null if empty).
   */
  public static function opaqueBounds(bmp:BitmapData):Null<Rectangle>
  {
    var r = bmp.getColorBoundsRect(0xFF000000, 0x00000000, false);
    return (r.width <= 0 || r.height <= 0) ? null : r;
  }
}
