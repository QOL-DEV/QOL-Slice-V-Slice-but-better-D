package funkin.qol.util;

import haxe.io.Bytes;

/**
 * A much faster compact `haxe.Json.stringify` on desktop for big documents (an imported Animate file can be close to a
 * hundred megabytes of JSON, and the standard writer turns every number into text through the slow general
 * formatter). Writes bytes directly; numbers keep up to 4 decimals. On the web the browser's own JSON is used.
 */
class QOLFastJson
{
  public static function stringify(value:Dynamic):String
  {
    #if js
    return haxe.Json.stringify(value);
    #else
    var w = new QOLJsonWriter();
    w.value(value);
    return w.result();
    #end
  }
}

#if !js
private class QOLJsonWriter
{
  var b:Bytes = Bytes.alloc(1 << 16);
  var len:Int = 0;

  public function new() {}

  public function result():String
    return b.getString(0, len);

  inline function ensure(n:Int):Void
  {
    if (len + n > b.length)
    {
      var size = b.length * 2;
      while (size < len + n)
        size *= 2;
      var nb = Bytes.alloc(size);
      nb.blit(0, b, 0, len);
      b = nb;
    }
  }

  inline function byte(c:Int):Void
  {
    ensure(1);
    b.set(len++, c);
  }

  function raw(s:String):Void
  {
    var n = s.length;
    ensure(n);
    for (i in 0...n)
      b.set(len++, StringTools.fastCodeAt(s, i));
  }

  public function value(v:Dynamic):Void
  {
    switch (Type.typeof(v))
    {
      case TNull:
        raw('null');
      case TInt:
        int((v : Int));
      case TFloat:
        number((v : Float));
      case TBool:
        raw((v : Bool) ? 'true' : 'false');
      case TClass(String):
        string(v);
      case TClass(Array):
        var a:Array<Dynamic> = v;
        byte('['.code);
        var n = a.length;
        if (n > 2 && Std.isOfType(a[0], Float) && Std.isOfType(a[n - 1], Float) && Std.isOfType(a[n >> 1], Float))
        {
          // A list of numbers (shape outlines): no per-item type checks.
          var fa:Array<Float> = cast v;
          for (i in 0...n)
          {
            if (i > 0) byte(','.code);
            number(fa[i]);
          }
        }
        else
        {
          for (i in 0...n)
          {
            if (i > 0) byte(','.code);
            value(a[i]);
          }
        }
        byte(']'.code);
      case TObject:
        byte('{'.code);
        var first = true;
        for (f in Reflect.fields(v))
        {
          var fv:Dynamic = Reflect.field(v, f);
          if (Reflect.isFunction(fv)) continue;
          if (!first) byte(','.code);
          first = false;
          string(f);
          byte(':'.code);
          value(fv);
        }
        byte('}'.code);
      default:
        // Rare in our data: whatever the standard writer makes of it.
        var s = haxe.Json.stringify(v);
        var bytes = Bytes.ofString(s);
        ensure(bytes.length);
        b.blit(len, bytes, 0, bytes.length);
        len += bytes.length;
    }
  }

  function int(n:Int):Void
  {
    if (n == 0)
    {
      byte('0'.code);
      return;
    }
    if (n == -2147483648)
    {
      raw('-2147483648');
      return;
    }
    ensure(11);
    if (n < 0)
    {
      b.set(len++, '-'.code);
      n = -n;
    }
    var start = len;
    while (n > 0)
    {
      var q = Std.int(n / 10);
      b.set(len++, '0'.code + (n - q * 10));
      n = q;
    }
    // Digits went in backwards.
    var i = start, j = len - 1;
    while (i < j)
    {
      var t = b.get(i);
      b.set(i, b.get(j));
      b.set(j, t);
      i++;
      j--;
    }
  }

  function number(f:Float):Void
  {
    if (!Math.isFinite(f))
    {
      raw('null');
      return;
    }
    if (f > -2e9 && f < 2e9 && f == Std.int(f))
    {
      int(Std.int(f));
      return;
    }
    var a = Math.abs(f);
    if (a < 2e5)
    {
      // Up to 4 decimals with whole-number math.
      var scaled = Std.int(a * 10000 + 0.5);
      if (scaled == 0)
      {
        byte('0'.code);
        return;
      }
      if (f < 0) byte('-'.code);
      var whole = Std.int(scaled / 10000);
      var frac = scaled - whole * 10000;
      int(whole);
      if (frac != 0)
      {
        ensure(5);
        b.set(len++, '.'.code);
        var div = 1000;
        while (frac > 0)
        {
          var d = Std.int(frac / div);
          b.set(len++, '0'.code + d);
          frac -= d * div;
          div = Std.int(div / 10);
        }
      }
      return;
    }
    raw(Std.string(f));
  }

  function string(s:String):Void
  {
    byte('"'.code);
    var n = s.length;
    var i = 0;
    while (i < n)
    {
      var c = StringTools.fastCodeAt(s, i++);
      if (c >= 0x20 && c < 0x80 && c != '"'.code && c != '\\'.code)
      {
        byte(c);
        continue;
      }
      switch (c)
      {
        case '"'.code:
          raw('\\"');
        case '\\'.code:
          raw('\\\\');
        case '\n'.code:
          raw('\\n');
        case '\r'.code:
          raw('\\r');
        case '\t'.code:
          raw('\\t');
        default:
          if (c < 0x20)
          {
            raw('\\u' + StringTools.hex(c, 4));
            continue;
          }
          // UTF-16 surrogate pairs (strings with emoji and the like).
          if (c >= 0xD800 && c < 0xDC00 && i < n)
          {
            var lo = StringTools.fastCodeAt(s, i);
            if (lo >= 0xDC00 && lo < 0xE000)
            {
              c = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
              i++;
            }
          }
          ensure(4);
          if (c < 0x800)
          {
            b.set(len++, 0xC0 | (c >> 6));
            b.set(len++, 0x80 | (c & 0x3F));
          }
          else if (c < 0x10000)
          {
            b.set(len++, 0xE0 | (c >> 12));
            b.set(len++, 0x80 | ((c >> 6) & 0x3F));
            b.set(len++, 0x80 | (c & 0x3F));
          }
          else
          {
            b.set(len++, 0xF0 | (c >> 18));
            b.set(len++, 0x80 | ((c >> 12) & 0x3F));
            b.set(len++, 0x80 | ((c >> 6) & 0x3F));
            b.set(len++, 0x80 | (c & 0x3F));
          }
      }
    }
    byte('"'.code);
  }
}
#end
