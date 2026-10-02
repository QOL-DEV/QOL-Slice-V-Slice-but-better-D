package funkin.qol.util;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesInput;
import haxe.zip.Entry;

/**
 * Reading and writing ZIP files on every platform (the standard library can only unzip on desktop).
 */
class QOLZip
{
  /**
   * Every file in a ZIP (folders left out), uncompressed.
   */
  public static function read(bytes:Bytes):Array<{name:String, data:Bytes}>
  {
    var out:Array<{name:String, data:Bytes}> = [];
    var entries = haxe.zip.Reader.readZip(new BytesInput(bytes));
    for (e in entries)
    {
      if (StringTools.endsWith(e.fileName, '/')) continue;
      out.push({name: e.fileName, data: unzip(e)});
    }
    return out;
  }

  public static function unzip(e:Entry):Bytes
  {
    if (!e.compressed) return e.data;
    var inflater = new haxe.zip.InflateImpl(new BytesInput(e.data), false, false);
    var buf = new BytesBuffer();
    var chunk = Bytes.alloc(65536);
    while (true)
    {
      var n = inflater.readBytes(chunk, 0, chunk.length);
      if (n <= 0) break;
      buf.addBytes(chunk, 0, n);
    }
    return buf.getBytes();
  }

  /**
   * Make a ZIP. Files are stored as-is (`compress` false) or deflated.
   */
  public static function write(files:Array<{name:String, data:Bytes}>, compress:Bool = true):Bytes
  {
    var entries = new haxe.ds.List<Entry>();
    for (f in files)
    {
      var e:Entry = {
        fileName: f.name,
        fileSize: f.data.length,
        fileTime: Date.now(),
        compressed: false,
        dataSize: f.data.length,
        data: f.data,
        crc32: haxe.crypto.Crc32.make(f.data)
      };
      if (compress && f.data.length > 64) deflate(e);
      entries.add(e);
    }
    var o = new haxe.io.BytesOutput();
    new haxe.zip.Writer(o).write(entries);
    return o.getBytes();
  }

  static function deflate(e:Entry):Void
  {
    #if sys
    var z = haxe.zip.Compress.run(e.data, 6);
    // Strip the zlib header and checksum: ZIP stores raw deflate data.
    e.data = z.sub(2, z.length - 6);
    e.dataSize = e.data.length;
    e.compressed = true;
    #end
  }
}
