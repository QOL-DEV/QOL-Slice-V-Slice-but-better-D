package funkin.qol.util;

import flixel.tweens.FlxEase;
import flixel.tweens.FlxEase.EaseFunction;

/**
 * Every ease type QOL Slice knows about, in one place.
 * Used by the ease picker (chart events, stage events, modcharts and the animator).
 */
class QOLEase
{
  /**
   * Ease families, in the order they're shown in the picker.
   */
  public static final FAMILIES:Array<String> = [
    'quad', 'cube', 'quart', 'quint', 'sine', 'circ', 'expo', 'smoothStep', 'smootherStep', 'back', 'elastic', 'bounce'
  ];

  public static final DIRECTIONS:Array<String> = ['In', 'Out', 'InOut'];

  /**
   * Every ease name. `linear` first, then every family in In / Out / InOut order.
   * Special value `INSTANT` is not included here (see `ALL_WITH_INSTANT`).
   */
  public static var ALL(get, never):Array<String>;

  static var _all:Array<String> = null;

  static function get_ALL():Array<String>
  {
    if (_all == null)
    {
      _all = ['linear'];
      for (family in FAMILIES)
        for (dir in DIRECTIONS)
          _all.push(family + dir);
    }
    return _all;
  }

  public static var ALL_WITH_INSTANT(get, never):Array<String>;

  static function get_ALL_WITH_INSTANT():Array<String>
  {
    return ['INSTANT'].concat(ALL);
  }

  /**
   * Turns `quadInOut` into `Quad In/Out`.
   */
  public static function displayName(ease:String):String
  {
    if (ease == null || ease == '') return 'Linear';
    if (ease == 'INSTANT') return 'Instant';
    if (ease == 'CLASSIC') return 'Classic';
    if (ease == 'linear') return 'Linear';
    for (family in FAMILIES)
    {
      if (ease.startsWith(family))
      {
        var dir = ease.substr(family.length);
        var famName = switch (family)
        {
          case 'smoothStep': 'Smooth Step';
          case 'smootherStep': 'Smoother Step';
          default: family.charAt(0).toUpperCase() + family.substr(1);
        };
        var dirName = switch (dir)
        {
          case 'InOut': 'In/Out';
          default: dir;
        };
        return '$famName $dirName';
      }
    }
    return ease;
  }

  /**
   * Combines V-Slice style `ease` + `easeDir` values into a single ease name.
   */
  public static function combine(ease:Null<String>, ?easeDir:String):String
  {
    if (ease == null || ease == '') return 'linear';
    if (ease == 'INSTANT' || ease == 'linear' || ease == 'CLASSIC') return ease;
    if (~/(In|Out|InOut)$/.match(ease)) return ease;
    return ease + (easeDir == null || easeDir == '' ? 'In' : easeDir);
  }

  /**
   * Splits a full ease name into a V-Slice style `[ease, easeDir]` pair.
   */
  public static function split(ease:String):Array<String>
  {
    if (ease == null || ease == 'linear' || ease == 'INSTANT' || ease == 'CLASSIC') return [ease ?? 'linear', ''];
    for (dir in ['InOut', 'Out', 'In'])
    {
      if (ease.endsWith(dir)) return [ease.substr(0, ease.length - dir.length), dir];
    }
    return [ease, ''];
  }

  /**
   * Get the easing function by name. Never returns null (falls back to linear).
   */
  public static function get(name:Null<String>):EaseFunction
  {
    return switch (name)
    {
      // V-Slice's "classic" camera follow (a smooth lerp that ignores the duration); approximated for previews.
      case 'CLASSIC': t -> 1 - Math.pow(1 - t, 5);
      case 'quadIn': FlxEase.quadIn;
      case 'quadOut': FlxEase.quadOut;
      case 'quadInOut': FlxEase.quadInOut;
      case 'cubeIn': FlxEase.cubeIn;
      case 'cubeOut': FlxEase.cubeOut;
      case 'cubeInOut': FlxEase.cubeInOut;
      case 'quartIn': FlxEase.quartIn;
      case 'quartOut': FlxEase.quartOut;
      case 'quartInOut': FlxEase.quartInOut;
      case 'quintIn': FlxEase.quintIn;
      case 'quintOut': FlxEase.quintOut;
      case 'quintInOut': FlxEase.quintInOut;
      case 'sineIn': FlxEase.sineIn;
      case 'sineOut': FlxEase.sineOut;
      case 'sineInOut': FlxEase.sineInOut;
      case 'circIn': FlxEase.circIn;
      case 'circOut': FlxEase.circOut;
      case 'circInOut': FlxEase.circInOut;
      case 'expoIn': FlxEase.expoIn;
      case 'expoOut': FlxEase.expoOut;
      case 'expoInOut': FlxEase.expoInOut;
      case 'smoothStepIn': FlxEase.smoothStepIn;
      case 'smoothStepOut': FlxEase.smoothStepOut;
      case 'smoothStepInOut': FlxEase.smoothStepInOut;
      case 'smootherStepIn': FlxEase.smootherStepIn;
      case 'smootherStepOut': FlxEase.smootherStepOut;
      case 'smootherStepInOut': FlxEase.smootherStepInOut;
      case 'backIn': FlxEase.backIn;
      case 'backOut': FlxEase.backOut;
      case 'backInOut': FlxEase.backInOut;
      case 'elasticIn': FlxEase.elasticIn;
      case 'elasticOut': FlxEase.elasticOut;
      case 'elasticInOut': FlxEase.elasticInOut;
      case 'bounceIn': FlxEase.bounceIn;
      case 'bounceOut': FlxEase.bounceOut;
      case 'bounceInOut': FlxEase.bounceInOut;
      case 'INSTANT': (t:Float) -> 1.0;
      default: FlxEase.linear;
    }
  }

  /**
   * Evaluate an ease by name. Values outside 0..1 are clamped.
   */
  public static inline function apply(name:Null<String>, t:Float):Float
  {
    return get(name)(t < 0 ? 0 : (t > 1 ? 1 : t));
  }

  /**
   * Interpolate between two values using a named ease.
   */
  public static inline function lerp(a:Float, b:Float, t:Float, ease:Null<String>):Float
  {
    return a + (b - a) * apply(ease, t);
  }
}
