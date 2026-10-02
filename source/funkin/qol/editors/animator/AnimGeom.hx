package funkin.qol.editors.animator;

import funkin.qol.editors.animator.AnimData;
import openfl.display.Graphics;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;

typedef AnimPoint =
{
  var x:Float;
  var y:Float;
  var ?w:Float;
}

typedef AnimDecomposed =
{
  var x:Float;
  var y:Float;
  var scaleX:Float;
  var scaleY:Float;
  var rotation:Float; // degrees
  var skew:Float; // degrees
}

/**
 * Geometry for the Animator: element matrices, drawing paths, smoothing freehand strokes, brush outlines, and turning
 * filled pixel regions back into vector shapes.
 */
class AnimGeom
{
  //
  // Matrices
  //

  public static function matrixOf(el:AnimElement, ?out:Matrix):Matrix
  {
    var m = out ?? new Matrix();
    m.setTo(el.a, el.b, el.c, el.d, el.tx, el.ty);
    return m;
  }

  public static function setMatrix(el:AnimElement, m:Matrix):Void
  {
    el.a = m.a;
    el.b = m.b;
    el.c = m.c;
    el.d = m.d;
    el.tx = m.tx;
    el.ty = m.ty;
  }

  /**
   * Break a matrix into position/scale/rotation/skew (what tweens interpolate, like Flash's classic tweens).
   */
  public static function decompose(a:Float, b:Float, c:Float, d:Float, tx:Float, ty:Float):AnimDecomposed
  {
    var sx = Math.sqrt(a * a + b * b);
    var rot = Math.atan2(b, a);
    var det = a * d - b * c;
    var sy = sx == 0 ? Math.sqrt(c * c + d * d) : det / sx;
    // Skew: angle between the x axis and the (rotated) y axis, minus 90 degrees.
    var skew = Math.atan2(a * c + b * d, det);
    return {
      x: tx,
      y: ty,
      scaleX: sx,
      scaleY: sy,
      rotation: rot * 180 / Math.PI,
      skew: skew * 180 / Math.PI
    };
  }

  public static function compose(t:AnimDecomposed, ?out:Matrix):Matrix
  {
    var m = out ?? new Matrix();
    var r = t.rotation * Math.PI / 180;
    var k = Math.tan(t.skew * Math.PI / 180);
    var cos = Math.cos(r);
    var sin = Math.sin(r);
    // M = R * K * S  (scale, then skew along x, then rotate)
    m.a = cos * t.scaleX;
    m.b = sin * t.scaleX;
    m.c = (cos * k - sin) * t.scaleY;
    m.d = (sin * k + cos) * t.scaleY;
    m.tx = t.x;
    m.ty = t.y;
    return m;
  }

  public static function decomposeEl(el:AnimElement):AnimDecomposed
    return decompose(el.a, el.b, el.c, el.d, el.tx, el.ty);

  //
  // Paths
  //

  public static function drawPath(g:Graphics, p:AnimPath, outline:Bool = false, outlineColor:Int = 0xFF5CE1FF):Void
  {
    if (outline)
    {
      g.lineStyle(1, outlineColor & 0xFFFFFF, 1, false, NONE);
    }
    else
    {
      if (p.stroke != null && (p.width ?? 1) > 0) g.lineStyle(p.width ?? 1, p.stroke & 0xFFFFFF, ((p.stroke >>> 24) & 0xFF) / 255, false, NORMAL, ROUND, ROUND);
      else
        g.lineStyle();
      if (p.fill != null) g.beginFill(p.fill & 0xFFFFFF, ((p.fill >>> 24) & 0xFF) / 255);
    }
    var d = p.d;
    var i = 0;
    var sx = 0.0, sy = 0.0;
    while (i < d.length)
    {
      var cmd = Std.int(d[i]);
      switch (cmd)
      {
        case 0:
          sx = d[i + 1];
          sy = d[i + 2];
          g.moveTo(sx, sy);
          i += 3;
        case 1:
          g.lineTo(d[i + 1], d[i + 2]);
          i += 3;
        case 2:
          g.curveTo(d[i + 1], d[i + 2], d[i + 3], d[i + 4]);
          i += 5;
        case 3:
          g.cubicCurveTo(d[i + 1], d[i + 2], d[i + 3], d[i + 4], d[i + 5], d[i + 6]);
          i += 7;
        case 4:
          g.lineTo(sx, sy);
          i += 1;
        default:
          i = d.length;
      }
    }
    if (!outline && p.fill != null) g.endFill();
    g.lineStyle();
  }

  /**
   * Bounds of a path's points (control points included, which is close enough for selection boxes).
   */
  public static function pathBounds(p:AnimPath, ?r:Rectangle):Rectangle
  {
    var minX = Math.POSITIVE_INFINITY, minY = Math.POSITIVE_INFINITY;
    var maxX = Math.NEGATIVE_INFINITY, maxY = Math.NEGATIVE_INFINITY;
    eachPoint(p, (x, y) -> {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    });
    var half = p.stroke != null ? (p.width ?? 1) / 2 : 0;
    var out = r ?? new Rectangle();
    if (minX == Math.POSITIVE_INFINITY) out.setTo(0, 0, 0, 0);
    else
      out.setTo(minX - half, minY - half, maxX - minX + half * 2, maxY - minY + half * 2);
    return out;
  }

  public static function shapeBounds(paths:Array<AnimPath>):Rectangle
  {
    var r:Null<Rectangle> = null;
    var tmp = new Rectangle();
    for (p in paths)
    {
      pathBounds(p, tmp);
      if (tmp.width == 0 && tmp.height == 0) continue;
      r = r == null ? tmp.clone() : r.union(tmp);
    }
    return r ?? new Rectangle();
  }

  public static function eachPoint(p:AnimPath, fn:Float->Float->Void):Void
  {
    var d = p.d;
    var i = 0;
    while (i < d.length)
    {
      var n = switch (Std.int(d[i]))
      {
        case 0 | 1: 1;
        case 2: 2;
        case 3: 3;
        default: 0;
      };
      for (j in 0...n)
        fn(d[i + 1 + j * 2], d[i + 2 + j * 2]);
      i += 1 + n * 2;
    }
  }

  /**
   * Move every point of a path through a matrix (used to bake a transform into a shape).
   */
  public static function transformPath(p:AnimPath, m:Matrix):Void
  {
    var d = p.d;
    var i = 0;
    while (i < d.length)
    {
      var n = switch (Std.int(d[i]))
      {
        case 0 | 1: 1;
        case 2: 2;
        case 3: 3;
        default: 0;
      };
      for (j in 0...n)
      {
        var xi = i + 1 + j * 2;
        var x = d[xi];
        var y = d[xi + 1];
        d[xi] = m.a * x + m.c * y + m.tx;
        d[xi + 1] = m.b * x + m.d * y + m.ty;
      }
      i += 1 + n * 2;
    }
    if (p.width != null)
    {
      var s = Math.sqrt(Math.abs(m.a * m.d - m.b * m.c));
      p.width = p.width * s;
    }
  }

  /**
   * Rough distance from a point to a path's outline (for picking strokes with the eraser).
   */
  public static function distanceToPath(p:AnimPath, px:Float, py:Float):Float
  {
    var best = Math.POSITIVE_INFINITY;
    var pts = flatten(p, 6);
    for (poly in pts)
    {
      for (i in 1...poly.length >> 1)
      {
        var d = segmentDistance(px, py, poly[(i - 1) * 2], poly[(i - 1) * 2 + 1], poly[i * 2], poly[i * 2 + 1]);
        if (d < best) best = d;
      }
      if (poly.length == 2)
      {
        var d = Math.sqrt((px - poly[0]) * (px - poly[0]) + (py - poly[1]) * (py - poly[1]));
        if (d < best) best = d;
      }
    }
    return best;
  }

  /**
   * True if the point is inside a filled path (even-odd).
   */
  public static function pathContains(p:AnimPath, px:Float, py:Float):Bool
  {
    var inside = false;
    for (poly in flatten(p, 8))
    {
      var n = poly.length >> 1;
      var j = n - 1;
      for (i in 0...n)
      {
        var xi = poly[i * 2], yi = poly[i * 2 + 1];
        var xj = poly[j * 2], yj = poly[j * 2 + 1];
        if (((yi > py) != (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi + 1e-9) + xi)) inside = !inside;
        j = i;
      }
    }
    return inside;
  }

  /**
   * Turn a path into polylines (curves split into `steps` segments). One array per subpath: [x0, y0, x1, y1, ...].
   */
  public static function flatten(p:AnimPath, steps:Int = 8):Array<Array<Float>>
  {
    var out:Array<Array<Float>> = [];
    var cur:Array<Float> = [];
    var d = p.d;
    var i = 0;
    var lx = 0.0, ly = 0.0;
    while (i < d.length)
    {
      switch (Std.int(d[i]))
      {
        case 0:
          if (cur.length > 0) out.push(cur);
          cur = [d[i + 1], d[i + 2]];
          lx = d[i + 1];
          ly = d[i + 2];
          i += 3;
        case 1:
          cur.push(d[i + 1]);
          cur.push(d[i + 2]);
          lx = d[i + 1];
          ly = d[i + 2];
          i += 3;
        case 2:
          var cx = d[i + 1], cy = d[i + 2], x = d[i + 3], y = d[i + 4];
          for (s in 1...steps + 1)
          {
            var t = s / steps;
            var u = 1 - t;
            cur.push(u * u * lx + 2 * u * t * cx + t * t * x);
            cur.push(u * u * ly + 2 * u * t * cy + t * t * y);
          }
          lx = x;
          ly = y;
          i += 5;
        case 3:
          var c1x = d[i + 1], c1y = d[i + 2], c2x = d[i + 3], c2y = d[i + 4], x = d[i + 5], y = d[i + 6];
          for (s in 1...steps + 1)
          {
            var t = s / steps;
            var u = 1 - t;
            cur.push(u * u * u * lx + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * x);
            cur.push(u * u * u * ly + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * y);
          }
          lx = x;
          ly = y;
          i += 7;
        case 4:
          if (cur.length >= 2)
          {
            cur.push(cur[0]);
            cur.push(cur[1]);
          }
          i += 1;
        default:
          i = d.length;
      }
    }
    if (cur.length > 0) out.push(cur);
    return out;
  }

  public static function segmentDistance(px:Float, py:Float, ax:Float, ay:Float, bx:Float, by:Float):Float
  {
    var dx = bx - ax, dy = by - ay;
    var len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / len2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    var qx = ax + dx * t - px, qy = ay + dy * t - py;
    return Math.sqrt(qx * qx + qy * qy);
  }

  //
  // Freehand strokes
  //

  /**
   * Drop points that are too close together.
   */
  public static function thin(points:Array<AnimPoint>, minDist:Float):Array<AnimPoint>
  {
    if (points.length < 3) return points.copy();
    var out = [points[0]];
    for (i in 1...points.length - 1)
    {
      var last = out[out.length - 1];
      var p = points[i];
      if ((p.x - last.x) * (p.x - last.x) + (p.y - last.y) * (p.y - last.y) >= minDist * minDist) out.push(p);
    }
    out.push(points[points.length - 1]);
    return out;
  }

  /**
   * Smooth a freehand line (moving average; `amount` 0..1).
   */
  public static function smooth(points:Array<AnimPoint>, amount:Float):Array<AnimPoint>
  {
    if (points.length < 3 || amount <= 0) return points.copy();
    var passes = Std.int(1 + amount * 4);
    var cur = points.copy();
    for (_ in 0...passes)
    {
      var next:Array<AnimPoint> = [cur[0]];
      for (i in 1...cur.length - 1)
      {
        var a = cur[i - 1], b = cur[i], c = cur[i + 1];
        var k = amount * 0.5;
        next.push({
          x: b.x * (1 - k) + (a.x + c.x) * 0.5 * k,
          y: b.y * (1 - k) + (a.y + c.y) * 0.5 * k,
          w: b.w
        });
      }
      next.push(cur[cur.length - 1]);
      cur = next;
    }
    return cur;
  }

  /**
   * A centerline path through the points, using midpoint quadratic curves (smooth, like Flash's pencil "smooth").
   */
  public static function curveThrough(points:Array<AnimPoint>, ?closed:Bool = false):Array<Float>
  {
    var d:Array<Float> = [];
    if (points.length == 0) return d;
    d.push(0);
    d.push(points[0].x);
    d.push(points[0].y);
    if (points.length == 1)
    {
      d.push(1);
      d.push(points[0].x + 0.01);
      d.push(points[0].y);
      return d;
    }
    if (points.length == 2)
    {
      d.push(1);
      d.push(points[1].x);
      d.push(points[1].y);
      return d;
    }
    for (i in 1...points.length - 1)
    {
      var p = points[i], n = points[i + 1];
      d.push(2);
      d.push(p.x);
      d.push(p.y);
      d.push((p.x + n.x) / 2);
      d.push((p.y + n.y) / 2);
    }
    var last = points[points.length - 1];
    d.push(1);
    d.push(last.x);
    d.push(last.y);
    if (closed) d.push(4);
    return d;
  }

  /**
   * A filled outline around a stroke whose width can change along it (the vector brush). Round ends.
   */
  public static function brushOutline(points:Array<AnimPoint>, baseWidth:Float):Array<Float>
  {
    var n = points.length;
    if (n == 0) return [];
    if (n == 1) return circlePath(points[0].x, points[0].y, (points[0].w ?? 1) * baseWidth / 2);
    var left:Array<AnimPoint> = [];
    var right:Array<AnimPoint> = [];
    for (i in 0...n)
    {
      var p = points[i];
      var a = points[i == 0 ? 0 : i - 1];
      var b = points[i == n - 1 ? n - 1 : i + 1];
      var dx = b.x - a.x, dy = b.y - a.y;
      var len = Math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6)
      {
        dx = 1;
        dy = 0;
        len = 1;
      }
      var nx = -dy / len, ny = dx / len;
      var r = Math.max(0.3, (p.w ?? 1) * baseWidth / 2);
      left.push({x: p.x + nx * r, y: p.y + ny * r});
      right.push({x: p.x - nx * r, y: p.y - ny * r});
    }
    var ring:Array<AnimPoint> = left.copy();
    // End cap (half circle around the last point).
    capPoints(points[n - 1], points[n - 2], (points[n - 1].w ?? 1) * baseWidth / 2, ring);
    var r2 = right.copy();
    r2.reverse();
    for (p in r2)
      ring.push(p);
    capPoints(points[0], points[1], (points[0].w ?? 1) * baseWidth / 2, ring);
    return curveThrough(ring, true);
  }

  static function capPoints(p:AnimPoint, prev:AnimPoint, r:Float, out:Array<AnimPoint>):Void
  {
    var ang = Math.atan2(p.y - prev.y, p.x - prev.x);
    var steps = 6;
    for (s in 1...steps)
    {
      var a = ang + Math.PI / 2 - Math.PI * s / steps;
      out.push({x: p.x + Math.cos(a) * r, y: p.y + Math.sin(a) * r});
    }
  }

  public static function circlePath(cx:Float, cy:Float, r:Float):Array<Float>
  {
    return ellipsePath(cx - r, cy - r, r * 2, r * 2);
  }

  public static function ellipsePath(x:Float, y:Float, w:Float, h:Float):Array<Float>
  {
    // Four cubic curves.
    var k = 0.5522847498;
    var rx = w / 2, ry = h / 2;
    var cx = x + rx, cy = y + ry;
    return [
      0, cx + rx, cy,
      3, cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry,
      3, cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy,
      3, cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry,
      3, cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy,
      4
    ];
  }

  public static function rectPath(x:Float, y:Float, w:Float, h:Float, radius:Float = 0):Array<Float>
  {
    if (w < 0)
    {
      x += w;
      w = -w;
    }
    if (h < 0)
    {
      y += h;
      h = -h;
    }
    var r = Math.min(radius, Math.min(w, h) / 2);
    if (r <= 0) return [0, x, y, 1, x + w, y, 1, x + w, y + h, 1, x, y + h, 4];
    return [
      0, x + r, y,
      1, x + w - r, y,
      2, x + w, y, x + w, y + r,
      1, x + w, y + h - r,
      2, x + w, y + h, x + w - r, y + h,
      1, x + r, y + h,
      2, x, y + h, x, y + h - r,
      1, x, y + r,
      2, x, y, x + r, y,
      4
    ];
  }

  public static function polygonPath(cx:Float, cy:Float, r:Float, sides:Int, star:Bool, rotation:Float = -90):Array<Float>
  {
    var d:Array<Float> = [];
    var count = star ? sides * 2 : sides;
    for (i in 0...count)
    {
      var rr = star && i % 2 == 1 ? r * 0.45 : r;
      var a = (rotation + 360 * i / count) * Math.PI / 180;
      d.push(i == 0 ? 0 : 1);
      d.push(cx + Math.cos(a) * rr);
      d.push(cy + Math.sin(a) * rr);
    }
    d.push(4);
    return d;
  }

  //
  // Pixels -> vector (paint bucket on vector layers)
  //

  /**
   * Trace the outlines of a filled mask (1 byte per pixel, nonzero = filled) into polygons (marching squares).
   * Coordinates are in mask pixels.
   */
  public static function traceMask(mask:haxe.io.Bytes, w:Int, h:Int):Array<Array<Float>>
  {
    function at(x:Int, y:Int):Bool
      return x >= 0 && y >= 0 && x < w && y < h && mask.get(y * w + x) != 0;

    // Edges between filled and empty pixels, walked into loops.
    var visited = new haxe.ds.IntMap<Bool>();
    var loops:Array<Array<Float>> = [];
    inline function key(x:Int, y:Int, dir:Int):Int
      return ((y * (w + 1) + x) << 2) | dir;

    for (y in 0...h)
    {
      for (x in 0...w)
      {
        // Start on a top edge of a filled pixel whose upper neighbour is empty.
        if (!at(x, y) || at(x, y - 1)) continue;
        if (visited.exists(key(x, y, 0))) continue;
        var loop:Array<Float> = [];
        // Walk with the filled area on the right. dir: 0 = right, 1 = down, 2 = left, 3 = up.
        var cx = x, cy = y, dir = 0;
        var guard = 0;
        do
        {
          visited.set(key(cx, cy, dir), true);
          loop.push(cx);
          loop.push(cy);
          // Move one step.
          switch (dir)
          {
            case 0: cx++;
            case 1: cy++;
            case 2: cx--;
            default: cy--;
          }
          // Pick the next direction: try turning left, straight, right (keeping filled on the right).
          dir = nextDir(cx, cy, dir, at);
          guard++;
        }
        while ((cx != x || cy != y || dir != 0) && guard < w * h * 4);
        if (loop.length >= 6) loops.push(loop);
      }
    }
    return loops;
  }

  static function nextDir(cx:Int, cy:Int, dir:Int, at:Int->Int->Bool):Int
  {
    // Pixels around the corner (cx, cy): tl = (cx-1, cy-1), tr = (cx, cy-1), bl = (cx-1, cy), br = (cx, cy).
    var tl = at(cx - 1, cy - 1), tr = at(cx, cy - 1), bl = at(cx - 1, cy), br = at(cx, cy);
    // For each heading, "right-hand" pixel ahead and left pixel ahead decide the turn.
    switch (dir)
    {
      case 0: // moving right: filled below (br side). Ahead pixels: tr (up-right), br (down-right).
        if (tr) return 3; // turn left (up)
        if (br) return 0; // straight
        return 1; // turn right (down)
      case 1: // moving down: filled on the left side of travel? (filled is to the west: bl). Ahead: bl, br.
        if (br) return 0; // turn left (east)
        if (bl) return 1; // straight
        return 2; // turn right (west)
      case 2: // moving left: filled above (tl). Ahead: tl, bl.
        if (bl) return 1; // turn left (down)
        if (tl) return 2; // straight
        return 3; // turn right (up)
      default: // moving up: filled to the east (tr). Ahead: tl, tr.
        if (tl) return 2; // turn left (west)
        if (tr) return 3; // straight
        return 0; // turn right (east)
    }
  }

  /**
   * Ramer-Douglas-Peucker on a closed polyline [x0, y0, x1, y1, ...].
   */
  public static function simplify(poly:Array<Float>, tolerance:Float):Array<Float>
  {
    var n = poly.length >> 1;
    if (n < 4) return poly.copy();
    var keep = [for (_ in 0...n) false];
    keep[0] = true;
    keep[n - 1] = true;
    var stack:Array<Int> = [0, n - 1];
    while (stack.length > 0)
    {
      var b = stack.pop();
      var a = stack.pop();
      var maxD = 0.0, idx = -1;
      for (i in a + 1...b)
      {
        var d = segmentDistance(poly[i * 2], poly[i * 2 + 1], poly[a * 2], poly[a * 2 + 1], poly[b * 2], poly[b * 2 + 1]);
        if (d > maxD)
        {
          maxD = d;
          idx = i;
        }
      }
      if (idx >= 0 && maxD > tolerance)
      {
        keep[idx] = true;
        stack.push(a);
        stack.push(idx);
        stack.push(idx);
        stack.push(b);
      }
    }
    var out:Array<Float> = [];
    for (i in 0...n)
      if (keep[i])
      {
        out.push(poly[i * 2]);
        out.push(poly[i * 2 + 1]);
      }
    return out;
  }

  /**
   * Closed smooth path through polygon points (for traced fills).
   */
  public static function smoothClosed(poly:Array<Float>, scale:Float, offsetX:Float, offsetY:Float):Array<Float>
  {
    var pts:Array<AnimPoint> = [];
    var n = poly.length >> 1;
    for (i in 0...n)
      pts.push({x: poly[i * 2] * scale + offsetX, y: poly[i * 2 + 1] * scale + offsetY});
    if (n < 3) return [];
    // Midpoint quadratic curves around the loop.
    var d:Array<Float> = [0, (pts[0].x + pts[1].x) / 2, (pts[0].y + pts[1].y) / 2];
    for (i in 1...n + 1)
    {
      var p = pts[i % n], q = pts[(i + 1) % n];
      d.push(2);
      d.push(p.x);
      d.push(p.y);
      d.push((p.x + q.x) / 2);
      d.push((p.y + q.y) / 2);
    }
    d.push(4);
    return d;
  }
}
