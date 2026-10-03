package funkin.qol.util;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesInput;

/**
 * Decompressing deflate data as fast as each platform allows: zlib on desktop, the browser's own decompressor on the
 * web (falling back to Haxe's slower one).
 */
class QOLInflate
{
  /**
   * Decompress `data`. `zlib` = it has a zlib header (otherwise it's raw deflate, like inside ZIP files).
   */
  public static function inflate(data:Bytes, zlib:Bool, done:Null<Bytes>->Void, pos:Int = 0, len:Int = -1):Void
  {
    if (len < 0) len = data.length - pos;
    #if js
    if (js.Syntax.code("typeof DecompressionStream !== 'undefined'"))
    {
      try
      {
        var ds:Dynamic = js.Syntax.code('new DecompressionStream({0})', zlib ? 'deflate' : 'deflate-raw');
        var src:Dynamic = js.Syntax.code('new Blob([{0}.subarray({1}, {2})])', @:privateAccess data.b, pos, pos + len);
        var stream:Dynamic = src.stream().pipeThrough(ds);
        var resp:Dynamic = js.Syntax.code('new Response({0})', stream);
        resp.arrayBuffer().then(function(ab:Dynamic) done(Bytes.ofData(ab)), function(_) done(inflateSync(data, zlib, pos, len)));
        return;
      }
      catch (e:Dynamic) {}
    }
    #end
    done(inflateSync(data, zlib, pos, len));
  }

  #if sys
  static var totalsChecked:Bool = false;
  static var totals:Bool = false;

  /**
   * Whether `Uncompress.execute` reports running totals instead of what one call read and wrote. Newer hxcpp versions
   * report totals, older ones (and other targets) per call. Found out once by inflating a tiny stored block with a small
   * output buffer: the second call's count only goes past the buffer's size if it's a total.
   */
  static function countsAreTotals():Bool
  {
    if (totalsChecked) return totals;
    totalsChecked = true;
    try
    {
      var n = 1000;
      var raw = Bytes.alloc(5 + n);
      raw.set(0, 1); // the last block, stored
      raw.set(1, n & 0xFF);
      raw.set(2, n >> 8);
      raw.set(3, ~n & 0xFF);
      raw.set(4, (~n >> 8) & 0xFF);
      for (i in 0...n)
        raw.set(5 + i, i & 0xFF);
      var u = new haxe.zip.Uncompress(-15);
      u.setFlushMode(haxe.zip.FlushMode.SYNC);
      var small = Bytes.alloc(256);
      var r1 = u.execute(raw, 0, small, 0);
      var r2 = u.execute(raw, r1.read, small, 0);
      u.close();
      totals = r2.write > small.length;
    }
    catch (e:Dynamic)
    {
      totals = false;
    }
    return totals;
  }
  #end

  public static function inflateSync(data:Bytes, zlib:Bool, pos:Int = 0, len:Int = -1):Null<Bytes>
  {
    if (len < 0) len = data.length - pos;
    try
    {
      #if sys
      var u = new haxe.zip.Uncompress(zlib ? null : -15);
      u.setFlushMode(haxe.zip.FlushMode.SYNC);
      var totals = countsAreTotals();
      var out = new BytesBuffer();
      var chunk = Bytes.alloc(1 << 20);
      var srcPos = pos;
      var lastIn = 0;
      var lastOut = 0;
      while (true)
      {
        var r = u.execute(data, srcPos, chunk, 0);
        var readNow = totals ? r.read - lastIn : r.read;
        var wroteNow = totals ? r.write - lastOut : r.write;
        lastIn = r.read;
        lastOut = r.write;
        srcPos += readNow;
        if (wroteNow > 0) out.addBytes(chunk, 0, wroteNow);
        if (r.done || (readNow == 0 && wroteNow == 0) || srcPos >= pos + len) break;
      }
      u.close();
      return out.getBytes();
      #else
      var inflater = new haxe.zip.InflateImpl(new BytesInput(data, pos, len), zlib, false);
      var buf = new BytesBuffer();
      var chunk = Bytes.alloc(65536);
      while (true)
      {
        var n = inflater.readBytes(chunk, 0, chunk.length);
        if (n <= 0) break;
        buf.addBytes(chunk, 0, n);
      }
      return buf.getBytes();
      #end
    }
    catch (e:Dynamic)
    {
      trace('[QOL] Inflate failed: $e');
      return null;
    }
  }
}
