package funkin.qol.editors.animator;

import funkin.qol.editors.animator.AnimData;

private typedef MorphContour =
{
  /**
   * Cubic pieces as flat points: x0 y0, then c1x c1y c2x c2y x y for each piece (the same count in both).
   */
  var a:Array<Float>;

  var b:Array<Float>;
  var closed:Bool;
}

private typedef MorphPair =
{
  var a:AnimPath;
  var b:AnimPath;
  var contours:Array<MorphContour>;
}

private typedef MorphPrepared =
{
  var from:AnimKeyframe;
  var to:AnimKeyframe;
  var sig:Float;
  var pairs:Array<MorphPair>;
}

/**
 * Shape tweens: morphing a keyframe's shapes into the next keyframe's shapes (like Animate's shape tweens).
 *
 * Shapes are matched in order (fill areas with fill areas, contour by contour), each contour is split into the same
 * number of curve pieces as its partner and lined up so the starting points match, then every point moves straight to
 * its partner. Shapes without a partner shrink away or grow in.
 */
class AnimMorph
{
  static var cache:Array<MorphPrepared> = [];

  /**
   * The elements of `from` morphed `t` (0..1, already eased) of the way to `to`.
   */
  public static function elements(from:AnimKeyframe, to:AnimKeyframe, t:Float):Array<AnimElement>
  {
    var prep = prepared(from, to);
    var paths:Array<AnimPath> = [for (p in prep.pairs) lerpPair(p, t)];
    var out:Array<AnimElement> = [];
    var placed = false;
    for (el in from.elements)
    {
      if (el.type != 'shape')
      {
        out.push(el);
        continue;
      }
      if (placed) continue;
      placed = true;
      var shape = AnimData.identity('shape');
      shape.paths = paths;
      out.push(shape);
    }
    if (!placed && paths.length > 0)
    {
      var shape = AnimData.identity('shape');
      shape.paths = paths;
      out.push(shape);
    }
    return out;
  }

  static function signature(k:AnimKeyframe):Float
  {
    var s = 0.0;
    for (el in k.elements)
    {
      s += el.a * 3 + el.b * 5 + el.c * 7 + el.d * 11 + el.tx * 13 + el.ty * 17;
      if (el.paths != null) for (p in el.paths)
      {
        s += p.d.length * 19 + (p.fill ?? 0) * 1e-9;
        var i = 0;
        while (i < p.d.length)
        {
          s += p.d[i] * ((i % 7) + 1);
          i += 3;
        }
      }
    }
    return s;
  }

  static function prepared(from:AnimKeyframe, to:AnimKeyframe):MorphPrepared
  {
    var sig = signature(from) + signature(to) * 1.5;
    for (c in cache)
      if (c.from == from && c.to == to && c.sig == sig) return c;
    var prep:MorphPrepared = {
      from: from,
      to: to,
      sig: sig,
      pairs: pairPaths(worldPaths(from), worldPaths(to))
    };
    cache.push(prep);
    if (cache.length > 48) cache.shift();
    return prep;
  }

  /**
   * Every shape path of a keyframe in the layer's coordinates.
   */
  static function worldPaths(k:AnimKeyframe):Array<AnimPath>
  {
    var out:Array<AnimPath> = [];
    for (el in k.elements)
    {
      if (el.type != 'shape' || el.paths == null) continue;
      var identity = el.a == 1 && el.b == 0 && el.c == 0 && el.d == 1 && el.tx == 0 && el.ty == 0;
      for (p in el.paths)
      {
        if (identity)
        {
          out.push(p);
          continue;
        }
        var copy:AnimPath = AnimData.copy(p);
        AnimGeom.transformPath(copy, AnimGeom.matrixOf(el));
        out.push(copy);
      }
    }
    return out;
  }

  static function pairPaths(pa:Array<AnimPath>, pb:Array<AnimPath>):Array<MorphPair>
  {
    // Fills pair with fills and strokes with strokes, in order.
    var fa = [for (p in pa) if (!isStroke(p)) p], fb = [for (p in pb) if (!isStroke(p)) p];
    var sa = [for (p in pa) if (isStroke(p)) p], sb = [for (p in pb) if (isStroke(p)) p];
    var out:Array<MorphPair> = [];
    for (lists in [[fa, fb], [sa, sb]])
    {
      var a = lists[0], b = lists[1];
      var n = Std.int(Math.max(a.length, b.length));
      for (i in 0...n)
      {
        var p = i < a.length ? a[i] : null;
        var q = i < b.length ? b[i] : null;
        out.push(pairOf(p, q));
      }
    }
    return out;
  }

  static inline function isStroke(p:AnimPath):Bool
    return p.fill == null && p.gradient == null && p.bitmapFill == null && p.stroke != null;

  static function pairOf(p:Null<AnimPath>, q:Null<AnimPath>):MorphPair
  {
    var ca = p != null ? contoursOf(p.d) : [];
    var cb = q != null ? contoursOf(q.d) : [];
    var contours:Array<MorphContour> = [];
    var n = Std.int(Math.max(ca.length, cb.length));
    for (i in 0...n)
    {
      var a = i < ca.length ? ca[i] : null;
      var b = i < cb.length ? cb[i] : null;
      // A contour without a partner shrinks to (or grows from) its middle.
      if (a == null) a = {pts: collapsed(b.pts), closed: b.closed};
      if (b == null) b = {pts: collapsed(a.pts), closed: a.closed};
      var ap = a.pts.copy(), bp = b.pts.copy();
      while (pieces(ap) < pieces(bp))
        splitLongest(ap);
      while (pieces(bp) < pieces(ap))
        splitLongest(bp);
      var closed = a.closed && b.closed;
      if (closed) bp = align(ap, bp);
      contours.push({a: ap, b: bp, closed: a.closed || b.closed});
    }
    // A path without a partner fades out (or in).
    var styleA:AnimPath = p ?? faded(q);
    var styleB:AnimPath = q ?? faded(p);
    return {a: styleA, b: styleB, contours: contours};
  }

  static function faded(p:AnimPath):AnimPath
  {
    var f:AnimPath = Reflect.copy(p);
    if (f.fill != null) f.fill = f.fill & 0xFFFFFF;
    if (f.stroke != null) f.stroke = f.stroke & 0xFFFFFF;
    return f;
  }

  static inline function pieces(pts:Array<Float>):Int
    return Std.int((pts.length - 2) / 6);

  static function collapsed(pts:Array<Float>):Array<Float>
  {
    var cx = 0.0, cy = 0.0, n = 0;
    var i = 0;
    while (i < pts.length)
    {
      cx += pts[i];
      cy += pts[i + 1];
      n++;
      i += 2;
    }
    cx /= Math.max(1, n);
    cy /= Math.max(1, n);
    return [for (j in 0...pts.length) j % 2 == 0 ? cx : cy];
  }

  /**
   * A path's contours as cubic pieces.
   */
  static function contoursOf(d:Array<Float>):Array<{pts:Array<Float>, closed:Bool}>
  {
    var out:Array<{pts:Array<Float>, closed:Bool}> = [];
    var cur:Null<{pts:Array<Float>, closed:Bool}> = null;
    var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
    var i = 0;
    function piece(c1x:Float, c1y:Float, c2x:Float, c2y:Float, ex:Float, ey:Float)
    {
      if (cur == null)
      {
        cur = {pts: [x, y], closed: false};
        out.push(cur);
      }
      cur.pts.push(c1x);
      cur.pts.push(c1y);
      cur.pts.push(c2x);
      cur.pts.push(c2y);
      cur.pts.push(ex);
      cur.pts.push(ey);
      x = ex;
      y = ey;
    }
    while (i < d.length)
    {
      switch (Std.int(d[i]))
      {
        case 0:
          x = sx = d[i + 1];
          y = sy = d[i + 2];
          cur = null;
          i += 3;
        case 1:
          var ex = d[i + 1], ey = d[i + 2];
          piece(x + (ex - x) / 3, y + (ey - y) / 3, x + (ex - x) * 2 / 3, y + (ey - y) * 2 / 3, ex, ey);
          i += 3;
        case 2:
          var cx = d[i + 1], cy = d[i + 2], ex = d[i + 3], ey = d[i + 4];
          piece(x + (cx - x) * 2 / 3, y + (cy - y) * 2 / 3, ex + (cx - ex) * 2 / 3, ey + (cy - ey) * 2 / 3, ex, ey);
          i += 5;
        case 3:
          piece(d[i + 1], d[i + 2], d[i + 3], d[i + 4], d[i + 5], d[i + 6]);
          i += 7;
        case 4:
          if (cur != null)
          {
            if (Math.abs(x - sx) > 0.01 || Math.abs(y - sy) > 0.01)
              piece(x + (sx - x) / 3, y + (sy - y) / 3, x + (sx - x) * 2 / 3, y + (sy - y) * 2 / 3, sx, sy);
            cur.closed = true;
          }
          cur = null;
          x = sx;
          y = sy;
          i += 1;
        default:
          i = d.length;
      }
    }
    for (c in out)
    {
      var n = c.pts.length;
      if (!c.closed && n >= 8 && Math.abs(c.pts[0] - c.pts[n - 2]) < 0.01 && Math.abs(c.pts[1] - c.pts[n - 1]) < 0.01) c.closed = true;
    }
    return [for (c in out) if (c.pts.length >= 8) c];
  }

  /**
   * Split the longest piece in half (de Casteljau).
   */
  static function splitLongest(pts:Array<Float>):Void
  {
    var n = pieces(pts);
    if (n == 0)
    {
      // A lone point: give it one piece.
      for (_ in 0...3)
      {
        pts.push(pts[0]);
        pts.push(pts[1]);
      }
      return;
    }
    var best = 0, bestLen = -1.0;
    for (k in 0...n)
    {
      var i = k * 6;
      var dx = pts[i + 6] - pts[i], dy = pts[i + 7] - pts[i + 1];
      var len = dx * dx + dy * dy;
      if (len > bestLen)
      {
        bestLen = len;
        best = k;
      }
    }
    var i = best * 6;
    var x0 = pts[i], y0 = pts[i + 1], x1 = pts[i + 2], y1 = pts[i + 3], x2 = pts[i + 4], y2 = pts[i + 5], x3 = pts[i + 6], y3 = pts[i + 7];
    var ax = (x0 + x1) / 2, ay = (y0 + y1) / 2;
    var bx = (x1 + x2) / 2, by = (y1 + y2) / 2;
    var cx = (x2 + x3) / 2, cy = (y2 + y3) / 2;
    var dx = (ax + bx) / 2, dy = (ay + by) / 2;
    var ex = (bx + cx) / 2, ey = (by + cy) / 2;
    var mx = (dx + ex) / 2, my = (dy + ey) / 2;
    var repl = [ax, ay, dx, dy, mx, my, ex, ey, cx, cy];
    // pts[i+2..i+5] (two control points) become the 10 values above, then the end point stays.
    pts.splice(i + 2, 4);
    for (j in 0...repl.length)
      pts.insert(i + 2 + j, repl[j]);
  }

  /**
   * Rotate (and maybe reverse) closed contour `b` so its points line up with `a`'s.
   */
  static function align(a:Array<Float>, b:Array<Float>):Array<Float>
  {
    var n = pieces(a);
    if (n < 2 || n > 400) return b;
    var best = b, bestCost = Math.POSITIVE_INFINITY;
    for (reversed in [false, true])
    {
      var src = reversed ? reverse(b) : b;
      for (k in 0...n)
      {
        var cost = 0.0;
        for (j in 0...n)
        {
          var ia = j * 6, ib = ((j + k) % n) * 6;
          var dx = a[ia] - src[ib], dy = a[ia + 1] - src[ib + 1];
          cost += dx * dx + dy * dy;
          if (cost >= bestCost) break;
        }
        if (cost < bestCost)
        {
          bestCost = cost;
          best = rotate(src, k);
        }
      }
    }
    return best;
  }

  static function rotate(pts:Array<Float>, k:Int):Array<Float>
  {
    if (k == 0) return pts;
    var n = pieces(pts);
    var out:Array<Float> = [pts[k * 6], pts[k * 6 + 1]];
    for (j in 0...n)
    {
      var i = ((j + k) % n) * 6;
      for (m in 2...8)
        out.push(pts[i + m]);
    }
    return out;
  }

  static function reverse(pts:Array<Float>):Array<Float>
  {
    var n = pieces(pts);
    var out:Array<Float> = [pts[pts.length - 2], pts[pts.length - 1]];
    var k = n - 1;
    while (k >= 0)
    {
      var i = k * 6;
      out.push(pts[i + 4]);
      out.push(pts[i + 5]);
      out.push(pts[i + 2]);
      out.push(pts[i + 3]);
      out.push(pts[i]);
      out.push(pts[i + 1]);
      k--;
    }
    return out;
  }

  static function lerpPair(p:MorphPair, t:Float):AnimPath
  {
    var a = p.a, b = p.b;
    var out:AnimPath = {d: []};
    if (a.fill != null || b.fill != null)
      out.fill = AnimRender.lerpColor(a.fill ?? ((b.fill ?? 0) & 0xFFFFFF), b.fill ?? ((a.fill ?? 0) & 0xFFFFFF), t);
    if (a.stroke != null || b.stroke != null)
    {
      out.stroke = AnimRender.lerpColor(a.stroke ?? ((b.stroke ?? 0) & 0xFFFFFF), b.stroke ?? ((a.stroke ?? 0) & 0xFFFFFF), t);
      out.width = lerp(a.width ?? b.width ?? 1, b.width ?? a.width ?? 1, t);
      out.caps = a.caps;
      out.joints = a.joints;
      out.hairline = a.hairline;
    }
    if (a.gradient != null || b.gradient != null) out.gradient = lerpGradient(a, b, t);
    if (a.bitmapFill != null || b.bitmapFill != null) out.bitmapFill = t < 0.5 ? (a.bitmapFill ?? b.bitmapFill) : (b.bitmapFill ?? a.bitmapFill);
    if (out.gradient != null || out.bitmapFill != null) out.fill = null;
    var d = out.d;
    for (c in p.contours)
    {
      var ca = c.a, cb = c.b;
      d.push(0);
      d.push(lerp(ca[0], cb[0], t));
      d.push(lerp(ca[1], cb[1], t));
      var i = 2;
      while (i + 5 < ca.length)
      {
        d.push(3);
        for (j in 0...6)
          d.push(lerp(ca[i + j], cb[i + j], t));
        i += 6;
      }
      if (c.closed) d.push(4);
    }
    return out;
  }

  static function lerpGradient(a:AnimPath, b:AnimPath, t:Float):AnimGradient
  {
    var ga = a.gradient ?? solidAsGradient(a.fill ?? 0, b.gradient);
    var gb = b.gradient ?? solidAsGradient(b.fill ?? 0, a.gradient);
    if (ga.type != gb.type || ga.colors.length != gb.colors.length) return t < 0.5 ? ga : gb;
    return {
      type: ga.type,
      colors: [for (i in 0...ga.colors.length) AnimRender.lerpColor(ga.colors[i], gb.colors[i], t)],
      ratios: [for (i in 0...ga.ratios.length) Std.int(lerp(ga.ratios[i], gb.ratios[i], t))],
      matrix: [for (i in 0...6) lerp(ga.matrix[i], gb.matrix[i], t)],
      spread: ga.spread,
      focal: lerp(ga.focal ?? 0, gb.focal ?? 0, t),
      linearRGB: ga.linearRGB
    };
  }

  static function solidAsGradient(color:Int, like:AnimGradient):AnimGradient
  {
    return {
      type: like.type,
      colors: [for (_ in like.colors) color],
      ratios: like.ratios.copy(),
      matrix: like.matrix.copy(),
      spread: like.spread,
      focal: like.focal,
      linearRGB: like.linearRGB
    };
  }

  static inline function lerp(a:Float, b:Float, t:Float):Float
    return a + (b - a) * t;
}
