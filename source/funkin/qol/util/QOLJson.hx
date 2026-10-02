package funkin.qol.util;

import haxe.Json;

/**
 * Pretty JSON writer with a stable, human-friendly key order.
 * Short arrays of numbers/strings are written on a single line, so files like
 * character offsets stay readable (`"offsets": [0, 0]`).
 */
class QOLJson
{
  /**
   * Keys that should appear first in any object, in this order.
   */
  static final DEFAULT_ORDER:Array<String> = [
    'version', 'id', 'name', 'title', 'description', 'author', 'renderType', 'assetPath', 'type', 'time', 't', 'beat', 'kind', 'prefix', 'position',
    'x', 'y', 'offsets', 'scale', 'scroll', 'zIndex', 'alpha', 'angle'
  ];

  public static function stringify(value:Dynamic, ?keyOrder:Array<String>, indent:String = '  '):String
  {
    var buf = new StringBuf();
    write(buf, value, keyOrder ?? DEFAULT_ORDER, indent, '');
    return buf.toString();
  }

  public static function parse(text:String):Dynamic
  {
    if (text == null) return null;
    // Strip a UTF-8 BOM.
    if (text.charCodeAt(0) == 0xFEFF) text = text.substr(1);
    return Json.parse(text.trim());
  }

  public static function tryParse(text:String):Dynamic
  {
    try
    {
      return parse(text);
    }
    catch (e)
    {
      trace('[QOL] JSON parse error: $e');
      return null;
    }
  }

  static function isSimple(v:Dynamic):Bool
  {
    return v == null || Std.isOfType(v, Float) || Std.isOfType(v, Int) || Std.isOfType(v, Bool) || Std.isOfType(v, String);
  }

  static function write(buf:StringBuf, v:Dynamic, order:Array<String>, indent:String, cur:String):Void
  {
    if (v == null)
    {
      buf.add('null');
      return;
    }
    if (Std.isOfType(v, String))
    {
      buf.add(Json.stringify(v));
      return;
    }
    if (Std.isOfType(v, Bool))
    {
      buf.add(v ? 'true' : 'false');
      return;
    }
    if (Std.isOfType(v, Int))
    {
      buf.add(Std.string(v));
      return;
    }
    if (Std.isOfType(v, Float))
    {
      var f:Float = v;
      if (Math.isNaN(f) || !Math.isFinite(f)) buf.add('0');
      else
      {
        // Round away float noise like 0.30000000000000004
        buf.add(Std.string(Math.round(f * 1000000) / 1000000));
      }
      return;
    }
    if (Std.isOfType(v, Array))
    {
      var arr:Array<Dynamic> = cast v;
      if (arr.length == 0)
      {
        buf.add('[]');
        return;
      }
      var allSimple = arr.length <= 16;
      if (allSimple) for (item in arr)
        if (!isSimple(item))
        {
          allSimple = false;
          break;
        }
      if (allSimple)
      {
        buf.add('[');
        for (i in 0...arr.length)
        {
          if (i > 0) buf.add(', ');
          write(buf, arr[i], order, indent, cur);
        }
        buf.add(']');
        return;
      }
      var next = cur + indent;
      buf.add('[\n');
      for (i in 0...arr.length)
      {
        buf.add(next);
        write(buf, arr[i], order, indent, next);
        if (i < arr.length - 1) buf.add(',');
        buf.add('\n');
      }
      buf.add(cur + ']');
      return;
    }
    if (Std.isOfType(v, haxe.ds.StringMap))
    {
      var map:haxe.ds.StringMap<Dynamic> = cast v;
      var obj:Dynamic = {};
      for (k in map.keys())
        Reflect.setField(obj, k, map.get(k));
      write(buf, obj, order, indent, cur);
      return;
    }

    // Generic object.
    var keys = Reflect.fields(v);
    if (keys.length == 0)
    {
      buf.add('{}');
      return;
    }
    keys.sort(function(a, b) {
      var ia = order.indexOf(a);
      var ib = order.indexOf(b);
      if (ia != -1 && ib != -1) return ia - ib;
      if (ia != -1) return -1;
      if (ib != -1) return 1;
      return a < b ? -1 : (a > b ? 1 : 0);
    });
    var next = cur + indent;
    buf.add('{\n');
    var first = true;
    for (k in keys)
    {
      var fieldValue:Dynamic = Reflect.field(v, k);
      if (Reflect.isFunction(fieldValue)) continue;
      if (!first) buf.add(',\n');
      first = false;
      buf.add(next);
      buf.add(Json.stringify(k));
      buf.add(': ');
      write(buf, fieldValue, order, indent, next);
    }
    buf.add('\n' + cur + '}');
  }

  /**
   * Deep copies a JSON-like structure.
   */
  public static function clone<T>(v:T):T
  {
    if (v == null) return null;
    return cast Json.parse(Json.stringify(v));
  }
}
