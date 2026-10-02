package funkin.qol.editors.animator;

import funkin.qol.editors.animator.AnimData;
import hxClipper.Clipper;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;

/**
 * Cutting vector shapes like Animate's drawing model: erasing part of a shape, and splitting a shape into the part
 * inside a selection area and the part outside it.
 *
 * Fills go through a polygon clipper (curves are flattened into short lines first); strokes are cut along their
 * center line.
 */
class AnimCut
{
  /**
   * Clipper works in whole numbers: coordinates are stored at 1/4 pixel.
   */
  static inline final SCALE:Float = 4;

  /**
   * Flattening tolerance (pixels).
   */
  static inline final TOLERANCE:Float = 0.35;

  /**
   * A circle-ended band from `a` to `b` (an eraser's swipe), as a polygon [x0, y0, x1, y1...].
   */
  public static function capsule(ax:Float, ay:Float, bx:Float, by:Float, r:Float):Array<Float>
  {
    var out:Array<Float> = [];
    var ang = Math.atan2(by - ay, bx - ax);
    var steps = Std.int(Math.max(8, Math.min(32, r)));
    // Half circle around b, then half circle around a.
    for (i in 0...steps + 1)
    {
      var t = ang - Math.PI / 2 + Math.PI * i / steps;
      out.push(bx + Math.cos(t) * r);
      out.push(by + Math.sin(t) * r);
    }
    for (i in 0...steps + 1)
    {
      var t = ang + Math.PI / 2 + Math.PI * i / steps;
      out.push(ax + Math.cos(t) * r);
      out.push(ay + Math.sin(t) * r);
    }
    return out;
  }

  public static function rectPoly(r:Rectangle):Array<Float>
    return [r.x, r.y, r.right, r.y, r.right, r.bottom, r.x, r.bottom];

  /**
   * A polygon given in the layer's coordinates, moved into an element's own coordinates.
   */
  public static function intoElement(poly:Array<Float>, el:AnimElement):Array<Float>
  {
    var m = AnimGeom.matrixOf(el);
    if (m.a == 1 && m.b == 0 && m.c == 0 && m.d == 1 && m.tx == 0 && m.ty == 0) return poly;
    m.invert();
    var out:Array<Float> = [];
    var i = 0;
    while (i + 1 < poly.length)
    {
      out.push(m.a * poly[i] + m.c * poly[i + 1] + m.tx);
      out.push(m.b * poly[i] + m.d * poly[i + 1] + m.ty);
      i += 2;
    }
    return out;
  }

  public static function polyBounds(poly:Array<Float>):Rectangle
  {
    var minX = Math.POSITIVE_INFINITY, minY = Math.POSITIVE_INFINITY, maxX = Math.NEGATIVE_INFINITY, maxY = Math.NEGATIVE_INFINITY;
    var i = 0;
    while (i + 1 < poly.length)
    {
      if (poly[i] < minX) minX = poly[i];
      if (poly[i] > maxX) maxX = poly[i];
      if (poly[i + 1] < minY) minY = poly[i + 1];
      if (poly[i + 1] > maxY) maxY = poly[i + 1];
      i += 2;
    }
    return new Rectangle(minX, minY, maxX - minX, maxY - minY);
  }

  static inline function isFill(p:AnimPath):Bool
    return p.fill != null || p.gradient != null || p.bitmapFill != null;

  /**
   * The part of a path outside `region` (`keepInside` false) or inside it (true). Null if nothing is left. Paths the
   * region doesn't touch come back unchanged.
   */
  public static function cut(p:AnimPath, region:Array<Float>, keepInside:Bool):Null<AnimPath>
  {
    var rb = polyBounds(region);
    var pb = AnimGeom.pathBounds(p);
    pb.inflate(0.5, 0.5);
    if (!rb.intersects(pb)) return keepInside ? null : p;
    // Entirely inside or entirely outside: nothing to cut (and curves stay curves).
    var polys = AnimGeom.flatten(p, 0);
    var anyIn = false, allIn = true;
    for (poly in polys)
    {
      var i = 0;
      while (i + 1 < poly.length)
      {
        if (pointIn(region, poly[i], poly[i + 1])) anyIn = true;
        else
          allIn = false;
        i += 2;
      }
    }
    var regionInPath = false;
    if (isFill(p))
    {
      var i = 0;
      while (i + 1 < region.length)
      {
        if (AnimGeom.pathContains(p, region[i], region[i + 1]))
        {
          regionInPath = true;
          break;
        }
        i += 2;
      }
    }
    if (!anyIn && !regionInPath && !edgesCross(polys, region)) return keepInside ? null : p;
    if (allIn && !regionInPath) return keepInside ? p : null;
    var out:AnimPath = Reflect.copy(p);
    if (isFill(p))
    {
      var d = cutFill(p, region, keepInside);
      if (d == null) return null;
      out.d = d;
      // Clipper's results never cross themselves; holes wind the other way.
      out.winding = 'nonzero';
      if (p.stroke != null)
      {
        // A filled shape's outline is cut along with it.
        var sd = cutStroke(p.d, region, keepInside);
        out.stroke = null;
        if (sd != null)
        {
          var outline:AnimPath = Reflect.copy(p);
          outline.fill = null;
          outline.gradient = null;
          outline.bitmapFill = null;
          outline.winding = null;
          outline.d = sd;
          return merge(out, outline);
        }
      }
      return out;
    }
    if (p.stroke == null) return keepInside ? null : p;
    var sd = cutStroke(p.d, region, keepInside);
    if (sd == null) return null;
    out.d = sd;
    return out;
  }

  /**
   * Whether any edge of the polylines crosses the region's outline.
   */
  static function edgesCross(polys:Array<Array<Float>>, region:Array<Float>):Bool
  {
    var m = region.length >> 1;
    for (poly in polys)
    {
      var n = poly.length >> 1;
      for (k in 0...n - 1)
      {
        var ax = poly[k * 2], ay = poly[k * 2 + 1], bx = poly[k * 2 + 2], by = poly[k * 2 + 3];
        for (e in 0...m)
        {
          var t = segmentHit(ax, ay, bx, by, region[e * 2], region[e * 2 + 1], region[((e + 1) % m) * 2], region[((e + 1) % m) * 2 + 1]);
          if (t >= 0 && t <= 1) return true;
        }
      }
    }
    return false;
  }

  /**
   * Two paths can't be one AnimPath when one is filled and the other only stroked; the caller gets the fill back with
   * the outline stashed on `extra`.
   */
  static function merge(fill:AnimPath, outline:AnimPath):AnimPath
  {
    Reflect.setField(fill, '__outline', outline);
    return fill;
  }

  /**
   * `cut` for every path of a shape element (region in the layer's coordinates). Returns the new paths (empty when
   * everything went), or null when the region missed the shape entirely.
   */
  public static function cutPaths(el:AnimElement, layerRegion:Array<Float>, keepInside:Bool):Null<Array<AnimPath>>
  {
    if (el.paths == null) return null;
    var region = intoElement(layerRegion, el);
    var rb = polyBounds(region);
    var out:Array<AnimPath> = [];
    var changed = false;
    for (p in el.paths)
    {
      var pb = AnimGeom.pathBounds(p);
      pb.inflate(1, 1);
      if (!pb.intersects(rb))
      {
        if (keepInside) changed = true;
        else
          out.push(p);
        continue;
      }
      var c = cut(p, region, keepInside);
      if (c != p) changed = true;
      if (c == null) continue;
      var extra:Null<AnimPath> = Reflect.field(c, '__outline');
      if (extra != null) Reflect.deleteField(c, '__outline');
      if (c.d.length > 0) out.push(c);
      if (extra != null && extra.d.length > 0) out.push(extra);
    }
    return changed ? out : null;
  }

  /**
   * A shape element's paths split into the parts inside and outside a region (in the layer's coordinates).
   */
  public static function split(el:AnimElement, layerRegion:Array<Float>):{inside:Array<AnimPath>, outside:Array<AnimPath>}
  {
    var inside:Array<AnimPath> = [], outside:Array<AnimPath> = [];
    if (el.paths == null) return {inside: inside, outside: outside};
    var region = intoElement(layerRegion, el);
    function add(list:Array<AnimPath>, c:Null<AnimPath>)
    {
      if (c == null) return;
      var extra:Null<AnimPath> = Reflect.field(c, '__outline');
      if (extra != null) Reflect.deleteField(c, '__outline');
      if (c.d.length > 0) list.push(c);
      if (extra != null && extra.d.length > 0) list.push(extra);
    }
    for (p in el.paths)
    {
      add(inside, cut(p, region, true));
      add(outside, cut(p, region, false));
    }
    return {inside: inside, outside: outside};
  }

  //
  // Fills
  //

  static function cutFill(p:AnimPath, region:Array<Float>, keepInside:Bool):Null<Array<Float>>
  {
    var subject = toClipper(AnimGeom.flatten(p, 0));
    var clip:Paths = [toClipperPoly(region)];
    var c = new Clipper();
    c.addPaths(subject, PolyType.PT_SUBJECT, true);
    c.addPaths(clip, PolyType.PT_CLIP, true);
    var solution:Paths = [];
    var fill = AnimGeom.usesNonZero(p) ? PolyFillType.PFT_NON_ZERO : PolyFillType.PFT_EVEN_ODD;
    c.executePaths(keepInside ? ClipType.CT_INTERSECTION : ClipType.CT_DIFFERENCE, solution, fill, PolyFillType.PFT_NON_ZERO);
    if (solution.length == 0) return null;
    var d:Array<Float> = [];
    for (poly in solution)
    {
      if (poly.length < 3) continue;
      d.push(0);
      d.push(poly[0].x / SCALE);
      d.push(poly[0].y / SCALE);
      for (i in 1...poly.length)
      {
        d.push(1);
        d.push(poly[i].x / SCALE);
        d.push(poly[i].y / SCALE);
      }
      d.push(4);
    }
    return d.length == 0 ? null : d;
  }

  static function toClipper(polys:Array<Array<Float>>):Paths
    return [for (poly in polys) if (poly.length >= 6) toClipperPoly(poly)];

  static function toClipperPoly(poly:Array<Float>):Path
  {
    var out:Path = [];
    var i = 0;
    while (i + 1 < poly.length)
    {
      out.push(new IntPoint(Math.round(poly[i] * SCALE), Math.round(poly[i + 1] * SCALE)));
      i += 2;
    }
    return out;
  }

  //
  // Strokes
  //

  /**
   * Cut a stroked path's center line: the pieces outside (or inside) `region`, as separate open lines.
   */
  static function cutStroke(d:Array<Float>, region:Array<Float>, keepInside:Bool):Null<Array<Float>>
  {
    var tmp:AnimPath = {d: d};
    var out:Array<Float> = [];
    for (line in AnimGeom.flatten(tmp, 0))
    {
      var n = line.length >> 1;
      if (n < 2) continue;
      var run:Array<Float> = [];
      function flush()
      {
        if (run.length >= 4)
        {
          out.push(0);
          out.push(run[0]);
          out.push(run[1]);
          var i = 2;
          while (i + 1 < run.length)
          {
            out.push(1);
            out.push(run[i]);
            out.push(run[i + 1]);
            i += 2;
          }
        }
        run = [];
      }
      for (k in 0...n - 1)
      {
        var ax = line[k * 2], ay = line[k * 2 + 1], bx = line[k * 2 + 2], by = line[k * 2 + 3];
        // Where the segment crosses the region's edge, in order.
        var ts = [0.0];
        var m = region.length >> 1;
        for (e in 0...m)
        {
          var cx = region[e * 2], cy = region[e * 2 + 1];
          var dx = region[((e + 1) % m) * 2], dy = region[((e + 1) % m) * 2 + 1];
          var t = segmentHit(ax, ay, bx, by, cx, cy, dx, dy);
          if (t > 0 && t < 1) ts.push(t);
        }
        ts.push(1);
        ts.sort((x, y) -> x < y ? -1 : (x > y ? 1 : 0));
        for (j in 0...ts.length - 1)
        {
          var t0 = ts[j], t1 = ts[j + 1];
          if (t1 - t0 < 1e-9) continue;
          var tm = (t0 + t1) / 2;
          var inside = pointIn(region, ax + (bx - ax) * tm, ay + (by - ay) * tm);
          if (inside == keepInside)
          {
            var x0 = ax + (bx - ax) * t0, y0 = ay + (by - ay) * t0;
            var x1 = ax + (bx - ax) * t1, y1 = ay + (by - ay) * t1;
            var rl = run.length;
            if (rl == 0 || Math.abs(run[rl - 2] - x0) > 1e-6 || Math.abs(run[rl - 1] - y0) > 1e-6)
            {
              flush();
              run.push(x0);
              run.push(y0);
            }
            run.push(x1);
            run.push(y1);
          }
          else
            flush();
        }
      }
      flush();
    }
    return out.length == 0 ? null : out;
  }

  /**
   * Where along a->b (0..1) it crosses c->d, or -1.
   */
  static function segmentHit(ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float, dx:Float, dy:Float):Float
  {
    var rx = bx - ax, ry = by - ay, sx = dx - cx, sy = dy - cy;
    var den = rx * sy - ry * sx;
    if (Math.abs(den) < 1e-12) return -1;
    var t = ((cx - ax) * sy - (cy - ay) * sx) / den;
    var u = ((cx - ax) * ry - (cy - ay) * rx) / den;
    return (u >= 0 && u <= 1) ? t : -1;
  }

  public static function pointIn(poly:Array<Float>, px:Float, py:Float):Bool
  {
    var inside = false;
    var n = poly.length >> 1;
    var j = n - 1;
    for (i in 0...n)
    {
      var xi = poly[i * 2], yi = poly[i * 2 + 1];
      var xj = poly[j * 2], yj = poly[j * 2 + 1];
      if (((yi > py) != (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi + 1e-12) + xi)) inside = !inside;
      j = i;
    }
    return inside;
  }
}
