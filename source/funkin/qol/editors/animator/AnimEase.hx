package funkin.qol.editors.animator;

import funkin.qol.editors.animator.AnimData;
import funkin.qol.util.QOLEase;

/**
 * Tween timing: named eases, Animate's classic -100..100 ease and custom ease curves.
 */
class AnimEase
{
  /**
   * How far (0..1, can overshoot) a tween is at `t` (0..1).
   */
  public static function apply(tween:Null<AnimTween>, t:Float):Float
  {
    if (tween == null) return t;
    if (tween.curve != null && tween.curve.length >= 8) return curveAt(tween.curve, t);
    if (tween.accel != null && tween.accel != 0) return classic(tween.accel, t);
    return QOLEase.get(tween.ease)(t);
  }

  /**
   * Animate's classic tween ease (-100 = ease in, 100 = ease out), the same quadratic Animate uses.
   */
  public static inline function classic(accel:Float, t:Float):Float
  {
    var a = Math.max(-1, Math.min(1, accel / 100));
    return t + a * (t - t * t);
  }

  /**
   * A custom ease curve (cubic Bezier pieces: x0 y0 cx1 cy1 cx2 cy2 x1 y1 cx...) at `x`.
   */
  public static function curveAt(c:Array<Float>, x:Float):Float
  {
    if (x <= 0) return c[1];
    var n = Std.int((c.length / 2 - 1) / 3);
    if (n <= 0) return x;
    var last = c.length - 2;
    if (x >= c[last]) return c[last + 1];
    for (k in 0...n)
    {
      var i = k * 6;
      var x0 = c[i], x3 = c[i + 6];
      if (x > x3 && k < n - 1) continue;
      var x1 = c[i + 2], x2 = c[i + 4];
      var y0 = c[i + 1], y1 = c[i + 3], y2 = c[i + 5], y3 = c[i + 7];
      // Find the curve parameter whose x is `x` (x grows along the curve), then read its y.
      var lo = 0.0, hi = 1.0, u = 0.5;
      for (_ in 0...30)
      {
        u = (lo + hi) / 2;
        var bx = bez(x0, x1, x2, x3, u);
        if (bx < x) lo = u;
        else
          hi = u;
      }
      return bez(y0, y1, y2, y3, (lo + hi) / 2);
    }
    return x;
  }

  static inline function bez(p0:Float, p1:Float, p2:Float, p3:Float, u:Float):Float
  {
    var v = 1 - u;
    return v * v * v * p0 + 3 * v * v * u * p1 + 3 * v * u * u * p2 + u * u * u * p3;
  }

  /**
   * Animate's preset ease names (quadIn, cubicOut...) as QOLEase names.
   */
  public static function fromAnimate(method:String):String
  {
    if (method == null || method == '' || method == 'none' || method == 'classic') return 'linear';
    var m = StringTools.replace(method, 'cubic', 'cube');
    m = StringTools.replace(m, 'Circ', 'circ');
    return QOLEase.ALL.contains(m) ? m : 'linear';
  }

  /**
   * QOLEase names as Animate's preset ease names.
   */
  public static function toAnimate(ease:String):Null<String>
  {
    if (ease == null || ease == 'linear') return null;
    if (StringTools.startsWith(ease, 'smooth')) return null;
    return StringTools.replace(ease, 'cube', 'cubic');
  }
}
