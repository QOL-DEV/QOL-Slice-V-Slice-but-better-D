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

  public static function inflateSync(data:Bytes, zlib:Bool, pos:Int = 0, len:Int = -1):Null<Bytes>
  {
    if (len < 0) len = data.length - pos;
    try
    {
      #if sys
      var u = new haxe.zip.Uncompress(zlib ? null : -15);
      u.setFlushMode(haxe.zip.FlushMode.SYNC);
      var out = new BytesBuffer();
      var chunk = Bytes.alloc(1 << 20);
      var srcPos = pos;
      while (true)
      {
        var r = u.execute(data, srcPos, chunk, 0);
        srcPos += r.read;
        if (r.write > 0) out.addBytes(chunk, 0, r.write);
        if (r.done || (r.read == 0 && r.write == 0)) break;
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
