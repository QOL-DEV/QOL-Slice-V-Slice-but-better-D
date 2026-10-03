package funkin.qol.editors.animator;

import funkin.qol.editors.animator.AnimData;

/**
 * One drawn piece of a path: a line, a quadratic or a cubic curve. `at` is where its command starts in the path's
 * `d` array.
 */
typedef AnimSeg =
{
  var path:Int;
  var at:Int;
  var cmd:Int;
  var x0:Float;
  var y0:Float;
  var x1:Float;
  var y1:Float;
}

/**
 * Editing the points and edges of drawn shapes, like Animate's Selection and Subselection tools: drag an edge to bend
 * it, drag a corner to move it, Ctrl+drag an edge to add a corner.
 *
 * Shapes keep fills and outlines as separate paths that share edges (an outline drawn around a fill, or a shape
 * imported from Animate), so every edit is made to every path at once: shared points and edges stay joined.
 */
class AnimEdit
{
  static inline final EPS:Float = 0.02;

  /**
   * Every line and curve of the paths (closing lines are left out).
   */
  public static function segments(paths:Array<AnimPath>):Array<AnimSeg>
  {
    var out:Array<AnimSeg> = [];
    for (pi in 0...paths.length)
    {
      var d = paths[pi].d;
      if (d == null) continue;
      var i = 0, cx = 0.0, cy = 0.0;
      while (i < d.length)
      {
        switch (Std.int(d[i]))
        {
          case 0:
            cx = d[i + 1];
            cy = d[i + 2];
            i += 3;
          case 1:
            out.push({path: pi, at: i, cmd: 1, x0: cx, y0: cy, x1: d[i + 1], y1: d[i + 2]});
            cx = d[i + 1];
            cy = d[i + 2];
            i += 3;
          case 2:
            out.push({path: pi, at: i, cmd: 2, x0: cx, y0: cy, x1: d[i + 3], y1: d[i + 4]});
            cx = d[i + 3];
            cy = d[i + 4];
            i += 5;
          case 3:
            out.push({path: pi, at: i, cmd: 3, x0: cx, y0: cy, x1: d[i + 5], y1: d[i + 6]});
            cx = d[i + 5];
            cy = d[i + 6];
            i += 7;
          case 4:
            i += 1;
          default:
            break;
        }
      }
    }
    return out;
  }

  /**
   * A point on a segment.
   */
  public static function pointAt(paths:Array<AnimPath>, s:AnimSeg, t:Float):{x:Float, y:Float}
  {
    var d = paths[s.path].d;
    var u = 1 - t;
    return switch (s.cmd)
    {
      case 2:
        var cx = d[s.at + 1], cy = d[s.at + 2];
        {x: u * u * s.x0 + 2 * u * t * cx + t * t * s.x1, y: u * u * s.y0 + 2 * u * t * cy + t * t * s.y1};
      case 3:
        var ax = d[s.at + 1], ay = d[s.at + 2], bx = d[s.at + 3], by = d[s.at + 4];
        {
          x: u * u * u * s.x0 + 3 * u * u * t * ax + 3 * u * t * t * bx + t * t * t * s.x1,
          y: u * u * u * s.y0 + 3 * u * u * t * ay + 3 * u * t * t * by + t * t * t * s.y1
        };
      default:
        {x: s.x0 + (s.x1 - s.x0) * t, y: s.y0 + (s.y1 - s.y0) * t};
    }
  }

  /**
   * The edge closest to a point (within `tol`), and where on it.
   */
  public static function nearestEdge(paths:Array<AnimPath>, px:Float, py:Float, tol:Float):Null<{seg:AnimSeg, t:Float, dist:Float}>
  {
    var best:Null<{seg:AnimSeg, t:Float, dist:Float}> = null;
    for (s in segments(paths))
    {
      // Quick reject on the segment's rough bounds.
      var d = paths[s.path].d;
      var minX = Math.min(s.x0, s.x1), maxX = Math.max(s.x0, s.x1), minY = Math.min(s.y0, s.y1), maxY = Math.max(s.y0, s.y1);
      if (s.cmd >= 2)
      {
        var n = s.cmd == 2 ? 1 : 2;
        for (k in 0...n)
        {
          var cx = d[s.at + 1 + k * 2], cy = d[s.at + 2 + k * 2];
          minX = Math.min(minX, cx);
          maxX = Math.max(maxX, cx);
          minY = Math.min(minY, cy);
          maxY = Math.max(maxY, cy);
        }
      }
      if (px < minX - tol || px > maxX + tol || py < minY - tol || py > maxY + tol) continue;
      var steps = s.cmd == 1 ? 1 : 16;
      var prev = {x: s.x0, y: s.y0};
      for (k in 1...steps + 1)
      {
        var t1 = k / steps;
        var p = pointAt(paths, s, t1);
        var dx = p.x - prev.x, dy = p.y - prev.y;
        var len2 = dx * dx + dy * dy;
        var u = len2 == 0 ? 0 : Math.max(0, Math.min(1, ((px - prev.x) * dx + (py - prev.y) * dy) / len2));
        var qx = prev.x + dx * u, qy = prev.y + dy * u;
        var dist = Math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy));
        if (dist <= tol && (best == null || dist < best.dist)) best = {seg: s, t: (k - 1 + u) / steps, dist: dist};
        prev = p;
      }
    }
    return best;
  }

  /**
   * The corner (a point where lines meet) closest to a point, within `tol`.
   */
  public static function nearestAnchor(paths:Array<AnimPath>, px:Float, py:Float, tol:Float):Null<{x:Float, y:Float}>
  {
    var best:Null<{x:Float, y:Float}> = null;
    var bestD = tol;
    for (s in segments(paths))
    {
      for (p in [[s.x0, s.y0], [s.x1, s.y1]])
      {
        var dist = Math.sqrt((px - p[0]) * (px - p[0]) + (py - p[1]) * (py - p[1]));
        if (dist <= bestD)
        {
          bestD = dist;
          best = {x: p[0], y: p[1]};
        }
      }
    }
    return best;
  }

  /**
   * Curve handles (control points) closest to a point, within `tol`.
   */
  public static function nearestControl(paths:Array<AnimPath>, px:Float, py:Float, tol:Float):Null<{x:Float, y:Float}>
  {
    var best:Null<{x:Float, y:Float}> = null;
    var bestD = tol;
    for (s in segments(paths))
    {
      if (s.cmd < 2) continue;
      var d = paths[s.path].d;
      for (k in 0...(s.cmd == 2 ? 1 : 2))
      {
        var cx = d[s.at + 1 + k * 2], cy = d[s.at + 2 + k * 2];
        var dist = Math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
        if (dist <= bestD)
        {
          bestD = dist;
          best = {x: cx, y: cy};
        }
      }
    }
    return best;
  }

  static inline function same(ax:Float, ay:Float, bx:Float, by:Float):Bool
    return Math.abs(ax - bx) < EPS && Math.abs(ay - by) < EPS;

  /**
   * Move every corner at (ox, oy) to (nx, ny) in all the paths.
   */
  public static function moveAnchor(paths:Array<AnimPath>, ox:Float, oy:Float, nx:Float, ny:Float):Void
  {
    for (p in paths)
    {
      var d = p.d;
      if (d == null) continue;
      var i = 0;
      while (i < d.length)
      {
        var cmd = Std.int(d[i]);
        var end = switch (cmd)
        {
          case 0 | 1: i + 1;
          case 2: i + 3;
          case 3: i + 5;
          default: -1;
        }
        if (end >= 0 && same(d[end], d[end + 1], ox, oy))
        {
          d[end] = nx;
          d[end + 1] = ny;
        }
        i += switch (cmd)
        {
          case 0 | 1: 3;
          case 2: 5;
          case 3: 7;
          case 4: 1;
          default: d.length;
        }
      }
    }
  }

  /**
   * Move every curve handle at (ox, oy) to (nx, ny).
   */
  public static function moveControl(paths:Array<AnimPath>, ox:Float, oy:Float, nx:Float, ny:Float):Void
  {
    for (s in segments(paths))
    {
      if (s.cmd < 2) continue;
      var d = paths[s.path].d;
      for (k in 0...(s.cmd == 2 ? 1 : 2))
      {
        var j = s.at + 1 + k * 2;
        if (same(d[j], d[j + 1], ox, oy))
        {
          d[j] = nx;
          d[j + 1] = ny;
        }
      }
    }
  }

  /**
   * The segments in all paths drawn between the same two points as `s` (either way round).
   */
  static function matching(paths:Array<AnimPath>, s:AnimSeg):Array<{seg:AnimSeg, reversed:Bool}>
  {
    var out = [];
    for (o in segments(paths))
    {
      if (same(o.x0, o.y0, s.x0, s.y0) && same(o.x1, o.y1, s.x1, s.y1)) out.push({seg: o, reversed: false});
      else if (same(o.x0, o.y0, s.x1, s.y1) && same(o.x1, o.y1, s.x0, s.y0)) out.push({seg: o, reversed: true});
    }
    return out;
  }

  /**
   * Replace segments' commands (from the end of each path so the positions stay right).
   */
  static function replaceAll(paths:Array<AnimPath>, edits:Array<{seg:AnimSeg, cmd:Array<Float>}>):Void
  {
    edits.sort((a, b) -> a.seg.path == b.seg.path ? b.seg.at - a.seg.at : a.seg.path - b.seg.path);
    for (e in edits)
    {
      var d = paths[e.seg.path].d;
      var len = e.seg.cmd == 1 ? 3 : (e.seg.cmd == 2 ? 5 : 7);
      var tail = d.splice(e.seg.at, d.length);
      for (v in e.cmd)
        d.push(v);
      for (k in len...tail.length)
        d.push(tail[k]);
    }
  }

  /**
   * Bend an edge so it passes through (mx, my) where it was grabbed (at `t`), like dragging a line with Animate's
   * Selection tool.
   */
  public static function bend(paths:Array<AnimPath>, s:AnimSeg, t:Float, mx:Float, my:Float):Void
  {
    t = Math.max(0.12, Math.min(0.88, t));
    var p = pointAt(paths, s, t);
    var dx = mx - p.x, dy = my - p.y;
    var edits = [];
    for (m in matching(paths, s))
    {
      var o = m.seg;
      var d = paths[o.path].d;
      switch (o.cmd)
      {
        case 1:
          var k = 2 * t * (1 - t);
          edits.push({seg: o, cmd: [2, (o.x0 + o.x1) / 2 + dx / k, (o.y0 + o.y1) / 2 + dy / k, o.x1, o.y1]});
        case 2:
          var k = 2 * t * (1 - t);
          edits.push({seg: o, cmd: [2, d[o.at + 1] + dx / k, d[o.at + 2] + dy / k, o.x1, o.y1]});
        default:
          var k = 3 * t * (1 - t);
          edits.push({seg: o, cmd: [3, d[o.at + 1] + dx / k, d[o.at + 2] + dy / k, d[o.at + 3] + dx / k, d[o.at + 4] + dy / k, o.x1, o.y1]});
      }
    }
    replaceAll(paths, edits);
  }

  /**
   * Add a corner where an edge was grabbed (at `t`) and move it to (mx, my), like Ctrl+dragging a line in Animate.
   */
  public static function addCorner(paths:Array<AnimPath>, s:AnimSeg, t:Float, mx:Float, my:Float):Void
  {
    t = Math.max(0.02, Math.min(0.98, t));
    var edits = [];
    for (m in matching(paths, s))
    {
      var o = m.seg;
      var tt = m.reversed ? 1 - t : t;
      var d = paths[o.path].d;
      switch (o.cmd)
      {
        case 1:
          edits.push({seg: o, cmd: [1, mx, my, 1, o.x1, o.y1]});
        case 2:
          // Split the curve in two (de Casteljau), then pull the new corner to the mouse.
          var cx = d[o.at + 1], cy = d[o.at + 2];
          var ax = o.x0 + (cx - o.x0) * tt, ay = o.y0 + (cy - o.y0) * tt;
          var bx = cx + (o.x1 - cx) * tt, by = cy + (o.y1 - cy) * tt;
          edits.push({seg: o, cmd: [2, ax, ay, mx, my, 2, bx, by, o.x1, o.y1]});
        default:
          var c1x = d[o.at + 1], c1y = d[o.at + 2], c2x = d[o.at + 3], c2y = d[o.at + 4];
          inline function lerp(a:Float, b:Float):Float
            return a + (b - a) * tt;
          var abx = lerp(o.x0, c1x), aby = lerp(o.y0, c1y);
          var bcx = lerp(c1x, c2x), bcy = lerp(c1y, c2y);
          var cdx = lerp(c2x, o.x1), cdy = lerp(c2y, o.y1);
          var abcx = lerp(abx, bcx), abcy = lerp(aby, bcy);
          var bcdx = lerp(bcx, cdx), bcdy = lerp(bcy, cdy);
          edits.push({seg: o, cmd: [3, abx, aby, abcx, abcy, mx, my, 3, bcdx, bcdy, cdx, cdy, o.x1, o.y1]});
      }
    }
    replaceAll(paths, edits);
  }

  /**
   * Deep copy of paths (for starting each drag step from the shape as it was).
   */
  public static function copyPaths(paths:Array<AnimPath>):Array<AnimPath>
    return haxe.Json.parse(haxe.Json.stringify(paths));
}
