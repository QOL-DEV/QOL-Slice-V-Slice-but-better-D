package funkin.qol.editors.animator;

import haxe.io.Bytes;
import haxe.io.BytesOutput;

/**
 * A sound in an Animator document: 16-bit PCM in memory (saved as a WAV next to the animation), with a waveform
 * summary for the timeline and a playable OpenFL sound made on demand.
 */
class AnimSound
{
  public var id:String;
  public var name:String;
  public var rate:Int;
  public var channels:Int;

  /**
   * Interleaved signed 16-bit little-endian samples.
   */
  public var pcm:Bytes;

  /**
   * Loudest sample (0..1) in each 1/100 second, all channels mixed.
   */
  public var peaks:Array<Float>;

  var sound:Null<openfl.media.Sound> = null;

  public static inline final PEAKS_PER_SECOND:Int = 100;

  public function new(id:String, name:String, rate:Int, channels:Int, pcm:Bytes)
  {
    this.id = id;
    this.name = name;
    this.rate = rate;
    this.channels = Std.int(Math.max(1, channels));
    this.pcm = pcm;
    computePeaks();
  }

  public var frames(get, never):Int;

  inline function get_frames():Int
    return Std.int(pcm.length / (2 * channels));

  /**
   * Length in seconds.
   */
  public var length(get, never):Float;

  inline function get_length():Float
    return rate > 0 ? frames / rate : 0;

  function computePeaks():Void
  {
    peaks = [];
    var per = Std.int(Math.max(1, rate / PEAKS_PER_SECOND));
    var n = frames;
    var i = 0;
    while (i < n)
    {
      var end = Std.int(Math.min(n, i + per));
      var peak = 0;
      // Every 4th frame is plenty for a waveform.
      var f = i;
      while (f < end)
      {
        for (c in 0...channels)
        {
          var v = sample(f, c);
          if (v < 0) v = -v;
          if (v > peak) peak = v;
        }
        f += 4;
      }
      peaks.push(peak / 32768);
      i = end;
    }
  }

  public inline function sample(frame:Int, channel:Int):Int
  {
    var p = (frame * channels + channel) * 2;
    var v = pcm.get(p) | (pcm.get(p + 1) << 8);
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  /**
   * Loudness (0..1) from `t0` to `t1` seconds (for drawing the waveform).
   */
  public function peakBetween(t0:Float, t1:Float):Float
  {
    var a = Std.int(Math.max(0, t0 * PEAKS_PER_SECOND));
    var b = Std.int(Math.min(peaks.length, Math.ceil(t1 * PEAKS_PER_SECOND)));
    var m = 0.0;
    for (i in a...b)
      if (peaks[i] > m) m = peaks[i];
    return m;
  }

  /**
   * A playable sound (made the first time it's needed).
   */
  public function getSound():Null<openfl.media.Sound>
  {
    if (sound != null) return sound;
    try
    {
      var buffer = lime.media.AudioBuffer.fromBytes(toWav());
      if (buffer != null) sound = openfl.media.Sound.fromAudioBuffer(buffer);
    }
    catch (e:Dynamic)
    {
      trace('[QOL] Could not make a playable sound for $name: $e');
    }
    return sound;
  }

  public function dispose():Void
  {
    if (sound != null) sound.close();
    sound = null;
  }

  //
  // WAV
  //

  public function toWav():Bytes
    return writeWav(pcm, rate, channels);

  public static function writeWav(pcm:Bytes, rate:Int, channels:Int):Bytes
  {
    var o = new BytesOutput();
    o.bigEndian = false;
    o.writeString('RIFF');
    o.writeInt32(36 + pcm.length);
    o.writeString('WAVE');
    o.writeString('fmt ');
    o.writeInt32(16);
    o.writeUInt16(1);
    o.writeUInt16(channels);
    o.writeInt32(rate);
    o.writeInt32(rate * channels * 2);
    o.writeUInt16(channels * 2);
    o.writeUInt16(16);
    o.writeString('data');
    o.writeInt32(pcm.length);
    o.write(pcm);
    return o.getBytes();
  }

  /**
   * Reads PCM WAV files (8/16/24/32-bit integer or 32-bit float) as 16-bit. Null if it isn't one.
   */
  public static function readWav(b:Bytes):Null<{rate:Int, channels:Int, pcm:Bytes}>
  {
    if (b.length < 44 || b.getString(0, 4) != 'RIFF' || b.getString(8, 4) != 'WAVE') return null;
    var pos = 12;
    var fmt = -1, channels = 0, rate = 0, bits = 0;
    var data:Null<Bytes> = null;
    while (pos + 8 <= b.length)
    {
      var id = b.getString(pos, 4);
      var len = b.getInt32(pos + 4);
      var start = pos + 8;
      if (id == 'fmt ')
      {
        fmt = b.getUInt16(start);
        channels = b.getUInt16(start + 2);
        rate = b.getInt32(start + 4);
        bits = b.getUInt16(start + 14);
        if (fmt == 0xFFFE && len >= 26) fmt = b.getUInt16(start + 24); // WAVE_FORMAT_EXTENSIBLE
      }
      else if (id == 'data')
      {
        data = b.sub(start, Std.int(Math.min(len, b.length - start)));
      }
      pos = start + len + (len % 2);
    }
    if (data == null || channels <= 0 || rate <= 0) return null;
    if (fmt == 1 && bits == 16) return {rate: rate, channels: channels, pcm: data};
    var bytesPer = Std.int(bits / 8);
    if (bytesPer <= 0) return null;
    var count = Std.int(data.length / bytesPer);
    var out = Bytes.alloc(count * 2);
    for (i in 0...count)
    {
      var p = i * bytesPer;
      var v:Float = switch ([fmt, bits])
      {
        case [1, 8]: (data.get(p) - 128) / 128;
        case [1, 24]:
          var x = data.get(p) | (data.get(p + 1) << 8) | (data.get(p + 2) << 16);
          if (x >= 0x800000) x -= 0x1000000;
          x / 8388608;
        case [1, 32]: data.getInt32(p) / 2147483648.0;
        case [3, 32]: data.getFloat(p);
        case [3, 64]: data.getDouble(p);
        default: 0;
      };
      var s = Std.int(Math.max(-32768, Math.min(32767, v * 32767)));
      out.set(i * 2, s & 0xFF);
      out.set(i * 2 + 1, (s >> 8) & 0xFF);
    }
    return {rate: rate, channels: channels, pcm: out};
  }

  //
  // Mixing
  //

  /**
   * Mix sounds into one 44.1 kHz stereo track. Each part starts at `at` seconds, plays from `from` seconds into its
   * sound, for up to `length` seconds, at `volume`.
   */
  public static function mix(parts:Array<{sound:AnimSound, at:Float, from:Float, length:Float, volume:Float}>, total:Float):Bytes
  {
    var rate = 44100;
    var frames = Std.int(Math.max(1, Math.ceil(total * rate)));
    var acc = new haxe.ds.Vector<Float>(frames * 2);
    for (i in 0...acc.length)
      acc[i] = 0;
    for (p in parts)
    {
      var s = p.sound;
      var startFrame = Std.int(p.at * rate);
      var count = Std.int(Math.min(p.length * rate, (s.length - p.from) * rate));
      for (i in 0...count)
      {
        var o = startFrame + i;
        if (o < 0) continue;
        if (o >= frames) break;
        // Nearest-sample resampling is plenty for a preview mix.
        var src = Std.int((p.from + i / rate) * s.rate);
        if (src >= s.frames) break;
        var l = s.sample(src, 0) / 32768;
        var r = s.channels > 1 ? s.sample(src, 1) / 32768 : l;
        acc[o * 2] += l * p.volume;
        acc[o * 2 + 1] += r * p.volume;
      }
    }
    var out = Bytes.alloc(frames * 4);
    for (i in 0...frames * 2)
    {
      var v = Std.int(Math.max(-32768, Math.min(32767, acc[i] * 32767)));
      out.set(i * 2, v & 0xFF);
      out.set(i * 2 + 1, (v >> 8) & 0xFF);
    }
    return out;
  }
}
