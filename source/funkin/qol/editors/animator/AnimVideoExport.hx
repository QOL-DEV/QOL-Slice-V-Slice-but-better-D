package funkin.qol.editors.animator;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesOutput;

/**
 * Video files from the Animator: AVI (Motion-JPEG pictures + PCM sound, plays in VLC, Windows Media Player and
 * video editors) and animated GIF. Pure Haxe writers.
 */
class AnimVideoExport
{
  //
  // AVI
  //

  /**
   * @param jpegs One JPEG per frame.
   * @param pcm 16-bit stereo 44.1 kHz sound (or null).
   */
  public static function writeAvi(jpegs:Array<Bytes>, width:Int, height:Int, fps:Float, ?pcm:Bytes):Bytes
  {
    var frames = jpegs.length;
    var audioRate = 44100, audioChannels = 2, blockAlign = 4;
    var hasAudio = pcm != null && pcm.length > 0;
    // Frame rate as a fraction.
    var scale = Math.abs(fps - Math.round(fps)) < 0.0001 ? 1 : 1000;
    var rate = Std.int(Math.round(fps * scale));
    var maxJpeg = 0;
    for (j in jpegs)
      if (j.length > maxJpeg) maxJpeg = j.length;

    // Movie data: a picture, then the sound for that frame.
    var movi = le();
    var index:Array<{id:String, offset:Int, size:Int}> = [];
    var samplesPerFrame = audioRate / fps;
    var audioPos = 0;
    for (i in 0...frames)
    {
      chunk(movi, '00dc', jpegs[i], index);
      if (hasAudio)
      {
        var endSample = Std.int(Math.round((i + 1) * samplesPerFrame));
        var endByte = Std.int(Math.min(pcm.length, endSample * blockAlign));
        if (endByte > audioPos)
        {
          chunk(movi, '01wb', pcm.sub(audioPos, endByte - audioPos), index);
          audioPos = endByte;
        }
      }
    }
    var moviBytes = movi.getBytes();

    // Headers.
    var hdrl = le();
    var avih = le();
    avih.writeInt32(Std.int(1000000 / fps));
    avih.writeInt32(Std.int(maxJpeg * fps + (hasAudio ? audioRate * blockAlign : 0)));
    avih.writeInt32(0);
    avih.writeInt32(0x10); // has an index
    avih.writeInt32(frames);
    avih.writeInt32(0);
    avih.writeInt32(hasAudio ? 2 : 1);
    avih.writeInt32(maxJpeg + 8);
    avih.writeInt32(width);
    avih.writeInt32(height);
    for (i in 0...4)
      avih.writeInt32(0);
    riffChunk(hdrl, 'avih', avih.getBytes());

    // Video stream.
    var vstrl = le();
    var strh = le();
    strh.writeString('vids');
    strh.writeString('MJPG');
    strh.writeInt32(0);
    strh.writeUInt16(0);
    strh.writeUInt16(0);
    strh.writeInt32(0);
    strh.writeInt32(scale);
    strh.writeInt32(rate);
    strh.writeInt32(0);
    strh.writeInt32(frames);
    strh.writeInt32(maxJpeg + 8);
    strh.writeInt32(-1);
    strh.writeInt32(0);
    strh.writeUInt16(0);
    strh.writeUInt16(0);
    strh.writeUInt16(width);
    strh.writeUInt16(height);
    riffChunk(vstrl, 'strh', strh.getBytes());
    var strf = le();
    strf.writeInt32(40);
    strf.writeInt32(width);
    strf.writeInt32(height);
    strf.writeUInt16(1);
    strf.writeUInt16(24);
    strf.writeString('MJPG');
    strf.writeInt32(width * height * 3);
    for (i in 0...4)
      strf.writeInt32(0);
    riffChunk(vstrl, 'strf', strf.getBytes());
    list(hdrl, 'strl', vstrl.getBytes());

    // Sound stream.
    if (hasAudio)
    {
      var astrl = le();
      var ah = le();
      ah.writeString('auds');
      ah.writeInt32(0);
      ah.writeInt32(0);
      ah.writeUInt16(0);
      ah.writeUInt16(0);
      ah.writeInt32(0);
      ah.writeInt32(blockAlign);
      ah.writeInt32(audioRate * blockAlign);
      ah.writeInt32(0);
      ah.writeInt32(Std.int(pcm.length / blockAlign));
      ah.writeInt32(Std.int(audioRate * blockAlign));
      ah.writeInt32(-1);
      ah.writeInt32(blockAlign);
      for (i in 0...4)
        ah.writeUInt16(0);
      riffChunk(astrl, 'strh', ah.getBytes());
      var af = le();
      af.writeUInt16(1);
      af.writeUInt16(audioChannels);
      af.writeInt32(audioRate);
      af.writeInt32(audioRate * blockAlign);
      af.writeUInt16(blockAlign);
      af.writeUInt16(16);
      af.writeUInt16(0);
      riffChunk(astrl, 'strf', af.getBytes());
      list(hdrl, 'strl', astrl.getBytes());
    }

    var body = le();
    body.writeString('AVI ');
    list(body, 'hdrl', hdrl.getBytes());
    list(body, 'movi', moviBytes);
    // Index (offsets from the 'movi' tag).
    var idx = le();
    for (e in index)
    {
      idx.writeString(e.id);
      idx.writeInt32(e.id == '00dc' ? 0x10 : 0);
      idx.writeInt32(e.offset + 4);
      idx.writeInt32(e.size);
    }
    riffChunk(body, 'idx1', idx.getBytes());
    var out = le();
    riffChunk(out, 'RIFF', body.getBytes());
    return out.getBytes();
  }

  static function le():BytesOutput
  {
    var o = new BytesOutput();
    o.bigEndian = false;
    return o;
  }

  static function riffChunk(o:BytesOutput, id:String, data:Bytes):Void
  {
    o.writeString(id);
    o.writeInt32(data.length);
    o.write(data);
    if (data.length % 2 == 1) o.writeByte(0);
  }

  static function list(o:BytesOutput, type:String, data:Bytes):Void
  {
    o.writeString('LIST');
    o.writeInt32(data.length + 4);
    o.writeString(type);
    o.write(data);
    if (data.length % 2 == 1) o.writeByte(0);
  }

  static function chunk(movi:BytesOutput, id:String, data:Bytes, index:Array<{id:String, offset:Int, size:Int}>):Void
  {
    index.push({id: id, offset: movi.length, size: data.length});
    riffChunk(movi, id, data);
  }

  //
  // GIF
  //

  /**
   * An animated GIF from ARGB frames (all the same size). Pixels under half opacity become transparent.
   * @param fps Frames per second. GIF delays are in hundredths of a second, so they're spread out to keep the timing
   *            right overall (24 fps alternates 4 and 5).
   */
  public static function writeGif(frames:Array<Bytes>, width:Int, height:Int, fps:Float, loop:Bool = true):Bytes
  {
    var transparent = false;
    // Palette: the most used colors (15-bit buckets), plus a transparent entry.
    var counts = new Map<Int, Int>();
    var stride = Std.int(Math.max(1, (width * height * frames.length) / 400000));
    for (f in frames)
    {
      var i = 0;
      var n = width * height;
      while (i < n)
      {
        var p = i * 4;
        if (f.get(p) < 128) transparent = true;
        else
        {
          var key = ((f.get(p + 1) >> 3) << 10) | ((f.get(p + 2) >> 3) << 5) | (f.get(p + 3) >> 3);
          counts.set(key, (counts.exists(key) ? counts.get(key) : 0) + 1);
        }
        i += stride;
      }
    }
    var keys = [for (k in counts.keys()) k];
    keys.sort((a, b) -> counts.get(b) - counts.get(a));
    var maxColors = transparent ? 255 : 256;
    var palette:Array<Int> = [];
    if (transparent) palette.push(0);
    for (k in keys)
    {
      if (palette.length >= (transparent ? maxColors + 1 : maxColors)) break;
      palette.push(((k >> 10) & 31) << 19 | ((k >> 5) & 31) << 11 | (k & 31) << 3 | 0x040404);
    }
    while (palette.length < 2)
      palette.push(0);
    var tableBits = 1;
    while ((1 << tableBits) < palette.length)
      tableBits++;
    var tableSize = 1 << tableBits;
    var nearest = new Map<Int, Int>();
    function indexOf(r:Int, g:Int, b:Int):Int
    {
      var key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      var cached = nearest.get(key);
      if (cached != null) return cached;
      var best = transparent ? 1 : 0, bestD = 1 << 30;
      for (i in (transparent ? 1 : 0)...palette.length)
      {
        var c = palette[i];
        var dr = ((c >> 16) & 0xFF) - r, dg = ((c >> 8) & 0xFF) - g, db = (c & 0xFF) - b;
        var d = dr * dr * 3 + dg * dg * 4 + db * db * 2;
        if (d < bestD)
        {
          bestD = d;
          best = i;
        }
      }
      nearest.set(key, best);
      return best;
    }

    var o = le();
    o.writeString('GIF89a');
    o.writeUInt16(width);
    o.writeUInt16(height);
    o.writeByte(0x80 | ((tableBits - 1) << 4) | (tableBits - 1));
    o.writeByte(0);
    o.writeByte(0);
    for (i in 0...tableSize)
    {
      var c = i < palette.length ? palette[i] : 0;
      o.writeByte((c >> 16) & 0xFF);
      o.writeByte((c >> 8) & 0xFF);
      o.writeByte(c & 0xFF);
    }
    if (loop)
    {
      o.writeByte(0x21);
      o.writeByte(0xFF);
      o.writeByte(11);
      o.writeString('NETSCAPE2.0');
      o.writeByte(3);
      o.writeByte(1);
      o.writeUInt16(0);
      o.writeByte(0);
    }
    var indexes = Bytes.alloc(width * height);
    for (i in 0...frames.length)
    {
      var f = frames[i];
      // Graphic control: delay, transparency, and clear before the next frame.
      o.writeByte(0x21);
      o.writeByte(0xF9);
      o.writeByte(4);
      o.writeByte((transparent ? 1 : 0) | (2 << 2));
      // Browsers treat delays under 2 as 10, so faster animations are capped at 50 fps.
      var delay = Std.int(Math.max(2, Math.round((i + 1) * 100 / fps) - Math.round(i * 100 / fps)));
      o.writeUInt16(delay);
      o.writeByte(0);
      o.writeByte(0);
      o.writeByte(0x2C);
      o.writeUInt16(0);
      o.writeUInt16(0);
      o.writeUInt16(width);
      o.writeUInt16(height);
      o.writeByte(0);
      for (i in 0...width * height)
      {
        var p = i * 4;
        indexes.set(i, transparent && f.get(p) < 128 ? 0 : indexOf(f.get(p + 1), f.get(p + 2), f.get(p + 3)));
      }
      var minCode = Std.int(Math.max(2, tableBits));
      o.writeByte(minCode);
      var data = lzw(indexes, minCode);
      var pos = 0;
      while (pos < data.length)
      {
        var n = Std.int(Math.min(255, data.length - pos));
        o.writeByte(n);
        o.writeFullBytes(data, pos, n);
        pos += n;
      }
      o.writeByte(0);
    }
    o.writeByte(0x3B);
    return o.getBytes();
  }

  /**
   * GIF's LZW compression.
   */
  static function lzw(pixels:Bytes, minCode:Int):Bytes
  {
    var out = new BytesBuffer();
    var clear = 1 << minCode;
    var eoi = clear + 1;
    var codeSize = minCode + 1;
    var next = eoi + 1;
    var dict = new Map<Int, Int>();
    var bitBuf = 0, bitCount = 0;
    function emit(code:Int)
    {
      bitBuf |= code << bitCount;
      bitCount += codeSize;
      while (bitCount >= 8)
      {
        out.addByte(bitBuf & 0xFF);
        bitBuf >>>= 8;
        bitCount -= 8;
      }
    }
    emit(clear);
    var prefix = pixels.get(0);
    for (i in 1...pixels.length)
    {
      var k = pixels.get(i);
      var key = (prefix << 8) | k;
      var found = dict.get(key);
      if (found != null)
      {
        prefix = found;
        continue;
      }
      emit(prefix);
      if (next < 4096)
      {
        dict.set(key, next++);
        if (next > (1 << codeSize) && codeSize < 12) codeSize++;
      }
      else
      {
        emit(clear);
        dict = new Map<Int, Int>();
        codeSize = minCode + 1;
        next = eoi + 1;
      }
      prefix = k;
    }
    emit(prefix);
    // The decoder adds one more entry on reading the last code, which can widen the end code.
    if (next >= (1 << codeSize) && codeSize < 12) codeSize++;
    emit(eoi);
    if (bitCount > 0) out.addByte(bitBuf & 0xFF);
    return out.getBytes();
  }
}
