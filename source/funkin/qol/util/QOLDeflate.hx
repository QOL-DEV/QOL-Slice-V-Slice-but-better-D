package funkin.qol.util;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/**
 * Deflate compression on every platform: zlib on desktop, and a small built-in compressor elsewhere (the web has no
 * synchronous one). The built-in one finds repeats (LZ77) and uses deflate's fixed codes: not as small as zlib, but
 * much smaller than storing.
 */
class QOLDeflate
{
  /**
   * Raw deflate data (what ZIP files store).
   */
  public static function raw(data:Bytes):Bytes
  {
    #if sys
    var z = haxe.zip.Compress.run(data, 6);
    return z.sub(2, z.length - 6);
    #else
    return new QOLDeflater(data).run();
    #end
  }

  /**
   * A zlib stream (header, deflate data, checksum).
   */
  public static function zlib(data:Bytes):Bytes
  {
    #if sys
    return haxe.zip.Compress.run(data, 6);
    #else
    var body = new QOLDeflater(data).run();
    var out = Bytes.alloc(body.length + 6);
    out.set(0, 0x78);
    out.set(1, 0x01);
    out.blit(2, body, 0, body.length);
    var a = adler32(data);
    var p = body.length + 2;
    out.set(p, (a >>> 24) & 0xFF);
    out.set(p + 1, (a >>> 16) & 0xFF);
    out.set(p + 2, (a >>> 8) & 0xFF);
    out.set(p + 3, a & 0xFF);
    return out;
    #end
  }

  public static function adler32(b:Bytes):Int
  {
    var a = 1, s = 0;
    var i = 0;
    var n = b.length;
    while (i < n)
    {
      var end = Std.int(Math.min(n, i + 3800));
      while (i < end)
      {
        a += b.get(i++);
        s += a;
      }
      a %= 65521;
      s %= 65521;
    }
    return (s << 16) | a;
  }
}

/**
 * LZ77 with hash chains + fixed Huffman codes.
 */
private class QOLDeflater
{
  static inline final WINDOW:Int = 32768;
  static inline final HASH_BITS:Int = 15;
  static inline final MAX_CHAIN:Int = 24;
  static inline final MIN_MATCH:Int = 3;
  static inline final MAX_MATCH:Int = 258;

  static var LEN_BASE:Array<Int> = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
  static var LEN_EXTRA:Array<Int> = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
  static var DIST_BASE:Array<Int> = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
  ];
  static var DIST_EXTRA:Array<Int> = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];

  var src:Bytes;
  var out:BytesBuffer = new BytesBuffer();
  var bitBuf:Int = 0;
  var bitCount:Int = 0;

  public function new(src:Bytes)
  {
    this.src = src;
  }

  inline function putBits(value:Int, count:Int):Void
  {
    bitBuf |= value << bitCount;
    bitCount += count;
    while (bitCount >= 8)
    {
      out.addByte(bitBuf & 0xFF);
      bitBuf >>>= 8;
      bitCount -= 8;
    }
  }

  /**
   * Huffman codes go most significant bit first.
   */
  inline function putCode(code:Int, len:Int):Void
  {
    var r = 0;
    for (i in 0...len)
      r |= ((code >> i) & 1) << (len - 1 - i);
    putBits(r, len);
  }

  inline function literal(sym:Int):Void
  {
    if (sym < 144) putCode(0x30 + sym, 8);
    else if (sym < 256) putCode(0x190 + sym - 144, 9);
    else if (sym < 280) putCode(sym - 256, 7);
    else
      putCode(0xC0 + sym - 280, 8);
  }

  function match(len:Int, dist:Int):Void
  {
    var li = 28;
    while (LEN_BASE[li] > len)
      li--;
    literal(257 + li);
    if (LEN_EXTRA[li] > 0) putBits(len - LEN_BASE[li], LEN_EXTRA[li]);
    var di = 29;
    while (DIST_BASE[di] > dist)
      di--;
    putCode(di, 5);
    if (DIST_EXTRA[di] > 0) putBits(dist - DIST_BASE[di], DIST_EXTRA[di]);
  }

  public function run():Bytes
  {
    var n = src.length;
    // One fixed-code block for everything.
    putBits(1, 1);
    putBits(1, 2);
    var head = new haxe.ds.Vector<Int>(1 << HASH_BITS);
    for (i in 0...head.length)
      head[i] = -1;
    var prev = new haxe.ds.Vector<Int>(WINDOW);
    var b = src;
    inline function hashAt(p:Int):Int
      return ((b.get(p) << 10) ^ (b.get(p + 1) << 5) ^ b.get(p + 2)) & ((1 << HASH_BITS) - 1);
    inline function insert(p:Int)
    {
      if (p + 2 < n)
      {
        var h = hashAt(p);
        prev[p & (WINDOW - 1)] = head[h];
        head[h] = p;
      }
    }
    var pos = 0;
    while (pos < n)
    {
      var bestLen = 0, bestDist = 0;
      if (pos + MIN_MATCH <= n)
      {
        var cand = head[hashAt(pos)];
        var chain = 0;
        var maxLen = Std.int(Math.min(MAX_MATCH, n - pos));
        while (cand >= 0 && pos - cand <= WINDOW - 1 && chain++ < MAX_CHAIN)
        {
          if (b.get(cand + bestLen) == b.get(pos + bestLen))
          {
            var l = 0;
            while (l < maxLen && b.get(cand + l) == b.get(pos + l))
              l++;
            if (l > bestLen)
            {
              bestLen = l;
              bestDist = pos - cand;
              if (l >= maxLen) break;
            }
          }
          var nx = prev[cand & (WINDOW - 1)];
          if (nx >= cand) break;
          cand = nx;
        }
      }
      if (bestLen >= MIN_MATCH)
      {
        match(bestLen, bestDist);
        for (k in 0...bestLen)
          insert(pos + k);
        pos += bestLen;
      }
      else
      {
        literal(b.get(pos));
        insert(pos);
        pos++;
      }
    }
    literal(256);
    if (bitCount > 0) out.addByte(bitBuf & 0xFF);
    bitBuf = 0;
    bitCount = 0;
    return out.getBytes();
  }
}
