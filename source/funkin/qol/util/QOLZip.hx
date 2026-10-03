package funkin.qol.util;

import haxe.io.Bytes;
import haxe.io.BytesOutput;

/**
 * Reading and writing ZIP files on every platform.
 *
 * Written by hand: the standard library's ZIP writer gets offsets wrong for file names with accents or other
 * non-English letters, and its reader is slow on the web.
 */
class QOLZip
{
  /**
   * Every file in a ZIP (folders left out), uncompressed.
   */
  public static function read(bytes:Bytes):Array<{name:String, data:Bytes}>
  {
    var out:Array<{name:String, data:Bytes}> = [];
    for (e in entries(bytes))
    {
      if (StringTools.endsWith(e.name, '/')) continue;
      var data = e.compressed ? QOLInflate.inflateSync(bytes, false, e.pos, e.len) : bytes.sub(e.pos, e.len);
      if (data != null) out.push({name: e.name, data: data});
    }
    return out;
  }

  /**
   * Where each file's data is (no copies): from the central directory, or by walking the local headers if that's
   * damaged.
   */
  public static function entries(b:Bytes):Array<{name:String, pos:Int, len:Int, compressed:Bool}>
  {
    var out:Array<{name:String, pos:Int, len:Int, compressed:Bool}> = [];
    // End of central directory: the last "PK\x05\x06" (a comment may follow it).
    var eocd = -1;
    var i = b.length - 22;
    var stop = Std.int(Math.max(0, b.length - 22 - 65535));
    while (i >= stop)
    {
      if (b.get(i) == 0x50 && b.get(i + 1) == 0x4B && b.get(i + 2) == 0x05 && b.get(i + 3) == 0x06)
      {
        eocd = i;
        break;
      }
      i--;
    }
    if (eocd >= 0)
    {
      // Count the entries rather than trusting the directory's size (some writers get it wrong).
      var count = b.getUInt16(eocd + 10);
      var p = b.getInt32(eocd + 16);
      var ok = p >= 0 && p < b.length;
      for (_ in 0...count)
      {
        if (!ok || p + 46 > b.length || b.getInt32(p) != 0x02014b50)
        {
          ok = false;
          break;
        }
        var method = b.getUInt16(p + 10);
        var csize = b.getInt32(p + 20);
        var nlen = b.getUInt16(p + 28), elen = b.getUInt16(p + 30), clen = b.getUInt16(p + 32);
        var local = b.getInt32(p + 42);
        var name = text(b, p + 46, nlen);
        if (local < 0 || local + 30 > b.length || b.getInt32(local) != 0x04034b50)
        {
          ok = false;
          break;
        }
        var dataPos = local + 30 + b.getUInt16(local + 26) + b.getUInt16(local + 28);
        if (csize < 0 || dataPos + csize > b.length)
        {
          ok = false;
          break;
        }
        out.push({name: name, pos: dataPos, len: csize, compressed: method == 8});
        p += 46 + nlen + elen + clen;
      }
      if (ok) return out;
      out = [];
    }
    // Walk the local headers.
    var pos = 0;
    while (pos + 30 <= b.length && b.getInt32(pos) == 0x04034b50)
    {
      var flags = b.getUInt16(pos + 6), method = b.getUInt16(pos + 8);
      var csize = b.getInt32(pos + 18);
      var nlen = b.getUInt16(pos + 26), elen = b.getUInt16(pos + 28);
      if ((flags & 8) != 0 && csize == 0) break;
      var dataPos = pos + 30 + nlen + elen;
      if (csize < 0 || dataPos + csize > b.length) break;
      out.push({name: text(b, pos + 30, nlen), pos: dataPos, len: csize, compressed: method == 8});
      pos = dataPos + csize;
    }
    return out;
  }

  /**
   * A file name (UTF-8, or byte by byte if it isn't valid UTF-8).
   */
  static function text(b:Bytes, pos:Int, len:Int):String
  {
    var ascii = true;
    for (i in pos...pos + len)
      if (b.get(i) >= 0x80) ascii = false;
    if (!ascii)
    {
      try
      {
        return b.getString(pos, len);
      }
      catch (e:Dynamic) {}
    }
    var s = new StringBuf();
    for (i in pos...pos + len)
      s.addChar(b.get(i));
    return s.toString();
  }

  /**
   * Make a ZIP. Files are stored as-is (`compress` false) or deflated (when that makes them smaller).
   */
  public static function write(files:Array<{name:String, data:Bytes}>, compress:Bool = true):Bytes
  {
    var o = new BytesOutput();
    o.bigEndian = false;
    var now = Date.now();
    var dosTime = (now.getHours() << 11) | (now.getMinutes() << 5) | Std.int(now.getSeconds() / 2);
    var dosDate = ((now.getFullYear() - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate();
    var central = new BytesOutput();
    central.bigEndian = false;
    var offset = 0;
    for (f in files)
    {
      var name = Bytes.ofString(f.name);
      var crc = haxe.crypto.Crc32.make(f.data);
      var data = f.data;
      var method = 0;
      if (compress && f.data.length > 64)
      {
        var raw = QOLDeflate.raw(f.data);
        // Already-compressed data (PNG, MP3...) can come out bigger: keep it stored then.
        if (raw.length < f.data.length)
        {
          data = raw;
          method = 8;
        }
      }
      // Local header.
      o.writeInt32(0x04034b50);
      o.writeUInt16(20);
      o.writeUInt16(0x0800); // names are UTF-8
      o.writeUInt16(method);
      o.writeUInt16(dosTime);
      o.writeUInt16(dosDate);
      o.writeInt32(crc);
      o.writeInt32(data.length);
      o.writeInt32(f.data.length);
      o.writeUInt16(name.length);
      o.writeUInt16(0);
      o.write(name);
      o.write(data);
      // Its central directory entry.
      central.writeInt32(0x02014b50);
      central.writeUInt16(20);
      central.writeUInt16(20);
      central.writeUInt16(0x0800);
      central.writeUInt16(method);
      central.writeUInt16(dosTime);
      central.writeUInt16(dosDate);
      central.writeInt32(crc);
      central.writeInt32(data.length);
      central.writeInt32(f.data.length);
      central.writeUInt16(name.length);
      central.writeUInt16(0);
      central.writeUInt16(0);
      central.writeUInt16(0);
      central.writeUInt16(0);
      central.writeInt32(0);
      central.writeInt32(offset);
      central.write(name);
      offset += 30 + name.length + data.length;
    }
    var cd = central.getBytes();
    o.write(cd);
    o.writeInt32(0x06054b50);
    o.writeUInt16(0);
    o.writeUInt16(0);
    o.writeUInt16(files.length);
    o.writeUInt16(files.length);
    o.writeInt32(cd.length);
    o.writeInt32(offset);
    o.writeUInt16(0);
    return o.getBytes();
  }
}
