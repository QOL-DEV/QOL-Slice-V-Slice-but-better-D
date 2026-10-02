package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import funkin.qol.util.QOLFilePicker;
import funkin.qol.util.QOLFilePicker.QOLPickedFile;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import openfl.display.BitmapData;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
import openfl.utils.ByteArray;

typedef DecodedAudio =
{
  var rate:Int;
  var channels:Int;

  /**
   * Interleaved signed 16-bit little-endian samples.
   */
  var pcm:Bytes;
}

typedef VideoOptions =
{
  var fps:Float;
  var maxWidth:Int;
  var maxHeight:Int;

  /**
   * Seconds to import from the start (long videos use lots of memory).
   */
  var maxSeconds:Float;

  var withAudio:Bool;
}

typedef DecodedVideo =
{
  var frames:Array<BitmapData>;

  /**
   * Original size.
   */
  var width:Int;

  var height:Int;
  var audio:Null<DecodedAudio>;
}

/**
 * Decoding audio, video and GIFs for the Animator.
 *
 * - Desktop: WAV, OGG, MP3, FLAC and Opus decode instantly; everything else (M4A/AAC, WMA, AIFF, AU, CAF, MKA,
 *   AC3, AMR, tracker modules (MOD/XM/IT/S3M), and every video format: MP4, MOV, M4V, MKV, WebM, AVI, WMV, FLV,
 *   MPEG, 3GP, OGV, TS...) goes through LibVLC (the engine's video player), which plays the file silently and
 *   records its frames and sound, so it takes about as long as the clip.
 * - Web: the browser's own decoders.
 * - GIF: decoded here on every platform.
 */
class AnimMedia
{
  public static final AUDIO_EXTS:Array<String> = [
    'wav', 'ogg', 'oga', 'mp3', 'flac', 'opus', 'm4a', 'aac', 'wma', 'aif', 'aiff', 'aifc', 'au', 'snd', 'caf', 'mka', 'ac3', 'amr', 'mp2', 'mpc', 'spx',
    'weba', 'mod', 'xm', 'it', 's3m', 'mid', 'mp4', 'webm', 'mov', 'mkv'
  ];

  public static final VIDEO_EXTS:Array<String> = [
    'mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', 'wmv', 'asf', 'flv', 'f4v', 'mpg', 'mpeg', 'm2v', 'vob', '3gp', '3g2', 'ogv', 'ogg', 'ts', 'mts', 'm2ts',
    'dv', 'gif'
  ];

  static final LIME_AUDIO:Array<String> = ['ogg', 'oga', 'mp3', 'flac', 'opus'];

  //
  // Audio
  //

  /**
   * Decode an audio (or video) file's sound. Returns a function that cancels.
   */
  public static function decodeAudio(file:QOLPickedFile, onDone:DecodedAudio->Void, onError:String->Void, ?onProgress:Float->Void):Void->Void
  {
    var ext = QOLFilePicker.ext(file.name);
    var wav = AnimSound.readWav(file.bytes);
    if (wav != null)
    {
      onDone(wav);
      return () -> {};
    }
    #if html5
    return webAudio(file.bytes, onDone, onError);
    #else
    if (LIME_AUDIO.contains(ext))
    {
      try
      {
        var buf = lime.media.AudioBuffer.fromBytes(file.bytes);
        if (buf != null && buf.data != null && buf.bitsPerSample == 16)
        {
          onDone({rate: buf.sampleRate, channels: buf.channels, pcm: buf.data.toBytes()});
          return () -> {};
        }
      }
      catch (e:Dynamic) {}
    }
    #if (hxvlc && cpp)
    return vlcCapture(file, false, true, null, v -> {
      if (v.audio == null || v.audio.pcm.length == 0) onError('No sound found in ${file.name}.');
      else
        onDone(v.audio);
    }, onError, onProgress);
    #else
    onError('This build can\'t decode .$ext files.');
    return () -> {};
    #end
    #end
  }

  //
  // Video
  //

  /**
   * Decode a video's frames (and sound). Returns a function that cancels.
   */
  public static function decodeVideo(file:QOLPickedFile, opts:VideoOptions, onDone:DecodedVideo->Void, onError:String->Void, ?onProgress:Float->Void):Void->Void
  {
    if (QOLFilePicker.ext(file.name) == 'gif')
    {
      try
      {
        onDone(decodeGif(file.bytes, opts));
      }
      catch (e:Dynamic)
      {
        onError('Could not read this GIF: $e');
      }
      return () -> {};
    }
    #if html5
    return webVideo(file, opts, onDone, onError, onProgress);
    #elseif (hxvlc && cpp)
    return vlcCapture(file, true, opts.withAudio, opts, onDone, onError, onProgress);
    #else
    onError('This build can\'t decode videos.');
    return () -> {};
    #end
  }

  /**
   * The size frames are scaled to (keeping the aspect ratio).
   */
  public static function fitSize(w:Int, h:Int, maxW:Int, maxH:Int):{w:Int, h:Int}
  {
    var s = Math.min(1, Math.min(maxW / Math.max(1, w), maxH / Math.max(1, h)));
    return {w: Std.int(Math.max(1, Math.round(w * s))), h: Std.int(Math.max(1, Math.round(h * s)))};
  }

  /**
   * Animated GIFs: every frame (with disposal and transparency), resampled to `fps`.
   */
  public static function decodeGif(bytes:Bytes, opts:VideoOptions):DecodedVideo
  {
    var data = new format.gif.Reader(new BytesInput(bytes)).read();
    var n = format.gif.Tools.framesCount(data);
    var w = data.logicalScreenDescriptor.width, h = data.logicalScreenDescriptor.height;
    var size = fitSize(w, h, opts.maxWidth, opts.maxHeight);
    var frames:Array<BitmapData> = [];
    var t = 0.0;
    var next = 0;
    var limit = Std.int(opts.maxSeconds * opts.fps);
    for (i in 0...n)
    {
      var gce = format.gif.Tools.graphicControl(data, i);
      var delay = gce != null && gce.delay > 0 ? gce.delay / 100 : 0.1;
      var bgra = format.gif.Tools.extractFullBGRA(data, i);
      var bmp = scaled(AnimIO.fromBGRA(bgra, w, h), size.w, size.h);
      t += delay;
      // Hold this frame until the next GIF frame starts.
      var until = Std.int(Math.max(next + 1, Math.round(t * opts.fps)));
      while (next < until && frames.length < limit)
      {
        frames.push(next == until - 1 ? bmp : bmp.clone());
        next++;
      }
      if (frames.length >= limit) break;
    }
    return {
      frames: frames,
      width: w,
      height: h,
      audio: null
    };
  }

  static function scaled(bmp:BitmapData, tw:Int, th:Int):BitmapData
  {
    if (bmp.width == tw && bmp.height == th) return bmp;
    var out = new BitmapData(tw, th, true, 0);
    var m = new Matrix();
    m.scale(tw / bmp.width, th / bmp.height);
    out.draw(bmp, m, null, null, null, true);
    bmp.dispose();
    return out;
  }

  #if html5
  static function webAudio(bytes:Bytes, onDone:DecodedAudio->Void, onError:String->Void):Void->Void
  {
    var cancelled = false;
    try
    {
      var ctx:Dynamic = js.Syntax.code('new (window.AudioContext || window.webkitAudioContext)()');
      var ab:Dynamic = (bytes.getData() : Dynamic).slice(0);
      ctx.decodeAudioData(ab).then(function(buf:Dynamic) {
        if (cancelled) return;
        var ch:Int = Std.int(Math.min(2, buf.numberOfChannels));
        var n:Int = buf.length;
        var out = Bytes.alloc(n * ch * 2);
        var datas:Array<Dynamic> = [for (c in 0...ch) buf.getChannelData(c)];
        for (i in 0...n)
        {
          for (c in 0...ch)
          {
            var f:Float = datas[c][i];
            var v = Std.int(Math.max(-32768, Math.min(32767, f * 32767)));
            var p = (i * ch + c) * 2;
            out.set(p, v & 0xFF);
            out.set(p + 1, (v >> 8) & 0xFF);
          }
        }
        ctx.close();
        onDone({rate: Std.int(buf.sampleRate), channels: ch, pcm: out});
      }, function(e:Dynamic) {
        ctx.close();
        if (!cancelled) onError('Your browser can\'t decode this sound.');
      });
    }
    catch (e:Dynamic)
    {
      onError('Could not decode: $e');
    }
    return () -> cancelled = true;
  }

  static function webVideo(file:QOLPickedFile, opts:VideoOptions, onDone:DecodedVideo->Void, onError:String->Void, ?onProgress:Float->Void):Void->Void
  {
    var cancelled = false;
    var finished = false;
    var blob = new js.html.Blob([file.bytes.getData()]);
    var url = js.html.URL.createObjectURL(blob);
    var video:js.html.VideoElement = cast js.Browser.document.createElement('video');
    video.muted = true;
    video.preload = 'auto';
    js.Syntax.code('{0}.playsInline = true', video);
    var frames:Array<BitmapData> = [];
    var total = 0;
    var size = {w: 1, h: 1};
    // The last frame the browser showed (play-through mode).
    var held:Null<js.html.CanvasElement> = null;

    function canvasOf(src:Dynamic):js.html.CanvasElement
    {
      var c:js.html.CanvasElement = cast js.Browser.document.createElement('canvas');
      c.width = size.w;
      c.height = size.h;
      c.getContext2d().drawImage(src, 0, 0, size.w, size.h);
      return c;
    }
    function finish()
    {
      if (finished) return;
      finished = true;
      video.pause();
      video.onseeked = null;
      video.onended = null;
      js.html.URL.revokeObjectURL(url);
      if (cancelled) return;
      var w = video.videoWidth, h = video.videoHeight;
      if (opts.withAudio) webAudio(file.bytes, a -> onDone({
        frames: frames,
        width: w,
        height: h,
        audio: a
      }), _ -> onDone({
        frames: frames,
        width: w,
        height: h,
        audio: null
      }));
      else
        onDone({
          frames: frames,
          width: w,
          height: h,
          audio: null
        });
    }

    // Seeking to a frame is exact but slow in some browsers, so frames are first caught while the clip plays, then any
    // the browser skipped (a slow machine drops frames) are fixed by seeking to them.
    var shownAt:Array<Float> = []; // when each of our frames was shown in the clip
    var lagOf:Array<Float> = []; // how late it was grabbed (a late grab may have caught the next frame instead)
    var heldLag = 0.0;
    var minGap = 1.0; // shortest time between two frames the browser showed (about the clip's frame length)
    var heldTime = 0.0;
    var lastTime = -1.0;
    var times:Array<Float> = [];
    var fixing:Array<Int> = [];
    var fixTotal = 0;
    function progress(p:Float)
      if (onProgress != null) onProgress(p);

    function seekNext()
    {
      if (cancelled || finished) return;
      if (fixing.length == 0)
      {
        finish();
        return;
      }
      video.currentTime = Math.min(video.duration, fixing[0] / opts.fps + 0.0001);
    }
    function seekFrames(list:Array<Int>)
    {
      video.pause();
      fixing = list;
      fixTotal = list.length;
      video.onseeked = function(_) {
        if (cancelled || finished) return;
        var i = fixing.shift();
        var bmp = BitmapData.fromCanvas(canvasOf(video));
        if (i < frames.length)
        {
          frames[i].dispose();
          frames[i] = bmp;
        }
        else
          frames.push(bmp);
        progress(0.85 + 0.15 * (fixTotal - fixing.length) / Math.max(1, fixTotal));
        seekNext();
      };
      seekNext();
    }
    function emit(c:js.html.CanvasElement, time:Float, lag:Float)
    {
      frames.push(BitmapData.fromCanvas(canvasOf(c)));
      shownAt.push(time);
      lagOf.push(lag);
      progress(0.85 * frames.length / total);
    }
    var played = false;
    function playedThrough()
    {
      if (cancelled || finished || played) return;
      played = true;
      video.pause();
      while (held != null && frames.length < total)
        emit(held, heldTime, heldLag);
      // The clip's frame length: the shortest gap between shown frames, or a fraction of it when the browser skipped
      // every other frame (all frame times are multiples of it).
      var frameLen = Math.min(minGap, 1 / 60);
      if (times.length > 1)
      {
        for (n in 1...6)
        {
          var d = minGap / n;
          if (Lambda.foreach(times, t -> {
            var k = (t - times[0]) / d;
            return Math.abs(k - Math.round(k)) * d < 0.0015;
          }))
          {
            frameLen = d;
            break;
          }
        }
      }
      // A frame is stale if a newer one should have been on screen at its time.
      var stale = [for (i in 0...frames.length) if (i / opts.fps - shownAt[i] > frameLen + 0.001 || lagOf[i] > frameLen * 0.8) i];
      for (i in frames.length...total)
        stale.push(i);
      if (stale.length == 0) finish();
      else
        seekFrames(stale);
    }
    function onFrame(_:Float, meta:Dynamic)
    {
      if (cancelled || finished || played) return;
      var t:Float = meta.mediaTime;
      if (lastTime >= 0 && t > lastTime + 0.0005) minGap = Math.min(minGap, t - lastTime);
      lastTime = t;
      times.push(t);
      while (frames.length < total && frames.length / opts.fps < t - 0.0005)
      {
        if (held != null) emit(held, heldTime, heldLag);
        else
          emit(canvasOf(video), t, video.currentTime - t);
      }
      if (frames.length >= total)
      {
        playedThrough();
        return;
      }
      held = canvasOf(video);
      heldTime = t;
      heldLag = video.currentTime - t;
      js.Syntax.code('{0}.requestVideoFrameCallback({1})', video, onFrame);
    }
    function startPlaying()
    {
      js.Syntax.code('{0}.requestVideoFrameCallback({1})', video, onFrame);
      video.onended = _ -> playedThrough();
      var p:Dynamic = video.play();
      if (p != null && p.then != null) p.then(null, _ -> if (!cancelled && !finished && frames.length == 0) seekFrames([for (i in 0...total) i]));
    }

    video.onloadedmetadata = function(_) {
      size = fitSize(video.videoWidth, video.videoHeight, opts.maxWidth, opts.maxHeight);
      total = Std.int(Math.max(1, Math.round(Math.min(opts.maxSeconds, video.duration) * opts.fps)));
      if (js.Syntax.code("typeof {0}.requestVideoFrameCallback === 'function'", video)) startPlaying();
      else
        seekFrames([for (i in 0...total) i]);
    };
    video.onerror = function(_) {
      if (!cancelled && !finished) onError('Your browser can\'t play this video format.');
    };
    video.src = url;
    return () -> {
      cancelled = true;
      video.pause();
      js.html.URL.revokeObjectURL(url);
    };
  }
  #end

  #if (hxvlc && cpp)
  /**
   * Play a file silently through LibVLC and record its frames and/or sound.
   */
  static function vlcCapture(file:QOLPickedFile, wantVideo:Bool, wantAudio:Bool, opts:Null<VideoOptions>, onDone:DecodedVideo->Void, onError:String->Void,
      ?onProgress:Float->Void):Void->Void
  {
    var fps = opts != null ? opts.fps : 24.0;
    var maxSeconds = opts != null ? opts.maxSeconds : 60 * 60.0;
    var limit = Std.int(maxSeconds * fps);
    var cap:Null<VLCCapture> = null;
    var frames:Array<BitmapData> = [];
    var done = false;
    var size:Null<{w:Int, h:Int}> = null;
    var options:Array<String> = [];
    if (!wantVideo) options.push(':no-video');
    if (!wantAudio) options.push(':no-audio');
    function finish(error:Null<String>)
    {
      if (done) return;
      done = true;
      var c = cap;
      cap = null;
      var audio:Null<DecodedAudio> = null;
      if (c != null)
      {
        audio = c.takeAudio(maxSeconds);
        // Stop and free the player outside its own event handlers.
        haxe.Timer.delay(() -> {
          try
          {
            c.stop();
            c.dispose();
          }
          catch (e:Dynamic) {}
        }, 1);
      }
      if (error != null && frames.length == 0 && (audio == null || audio.pcm.length == 0))
      {
        onError(error);
        return;
      }
      onDone({
        frames: frames,
        width: c != null ? c.frameW : 0,
        height: c != null ? c.frameH : 0,
        audio: audio
      });
    }
    try
    {
      cap = new VLCCapture();
      var c = cap;
      c.onFrame = function(pixels) {
        if (done || c.frameW <= 0) return;
        if (size == null) size = opts != null ? fitSize(c.frameW, c.frameH, opts.maxWidth, opts.maxHeight) : {w: c.frameW, h: c.frameH};
        var t = haxe.Int64.toInt(c.time) / 1000;
        var index = Std.int(t * fps);
        if (frames.length > index || frames.length >= limit) return;
        var bmp = VLCCapture.toBitmap(pixels, c.frameW, c.frameH, size.w, size.h);
        // Frames VLC skipped repeat the next one.
        while (frames.length < index && frames.length < limit)
          frames.push(bmp.clone());
        if (frames.length < limit) frames.push(bmp);
        else
          bmp.dispose();
      };
      c.onEndReached.add(() -> finish(null));
      c.onEncounteredError.add(e -> finish('LibVLC could not play ${file.name}.'));
      c.onTimeChanged.add(t -> {
        var secs = haxe.Int64.toInt(t) / 1000;
        var len = haxe.Int64.toInt(c.length) / 1000;
        if (onProgress != null) onProgress(len > 0 ? Math.min(1, secs / Math.min(len, maxSeconds)) : 0);
        if (secs >= maxSeconds || (wantVideo && frames.length >= limit)) finish(null);
      });
      var opened = file.path != null ? c.load(file.path, options) : c.load(file.bytes, options);
      if (!opened)
      {
        finish('LibVLC could not open ${file.name}.');
        return () -> {};
      }
      if (!c.play()) finish('LibVLC could not play ${file.name}.');
    }
    catch (e:Dynamic)
    {
      finish('Video playback isn\'t available: $e');
    }
    return () -> finish('Cancelled');
  }
  #end
}

#if (hxvlc && cpp)
/**
 * A LibVLC player that records frames and sound instead of showing/playing them.
 */
private class VLCCapture extends hxvlc.openfl.Video
{
  public var sampleRate:Int = 0;
  public var channels:Int = 0;
  public var frameW:Int = 0;
  public var frameH:Int = 0;
  public var onFrame:Null<haxe.io.BytesData->Void> = null;

  var chunks:Array<Bytes> = [];
  var lock = new sys.thread.Mutex();

  public function new()
  {
    super();
  }

  override function audioOutput_onMapFormat(format:String):String
    return 'S16N';

  override function audioOutput_onMapChannels(c:Int):Int
    return c <= 1 ? 1 : 2;

  override function audioOutput_onFormatSetup(format:String, rate:Int, channels:Int):Void
  {
    this.sampleRate = rate;
    this.channels = channels;
  }

  // Called on LibVLC's audio thread: copy the samples, play nothing.
  override function audioOutput_onPlay(samples:haxe.io.BytesData):Void
  {
    if (samples == null || channels <= 0) return;
    var total = samples.length * channels * 2;
    if (total <= 0) return;
    var out = Bytes.alloc(total);
    cpp.Stdlib.memcpy(cpp.NativeArray.address(out.getData(), 0), cpp.NativeArray.address(samples, 0), total);
    lock.acquire();
    chunks.push(out);
    lock.release();
  }

  override function audioOutput_onPause():Void {}

  override function audioOutput_onResume():Void {}

  override function audioOutput_onFlush():Void {}

  override function videoOutput_onSetup(width:Int, height:Int):Void
  {
    frameW = width;
    frameH = height;
  }

  override function videoOutput_onDisplay(pixels:haxe.io.BytesData):Void
  {
    if (onFrame != null && pixels != null) onFrame(pixels);
  }

  /**
   * Everything recorded so far, as one sound.
   */
  public function takeAudio(maxSeconds:Float):Null<DecodedAudio>
  {
    lock.acquire();
    var parts = chunks;
    chunks = [];
    lock.release();
    if (sampleRate <= 0 || channels <= 0 || parts.length == 0) return null;
    var size = 0;
    for (p in parts)
      size += p.length;
    var maxBytes = Std.int(maxSeconds * sampleRate) * channels * 2;
    if (size > maxBytes) size = maxBytes;
    var pcm = Bytes.alloc(size);
    var pos = 0;
    for (p in parts)
    {
      var n = Std.int(Math.min(p.length, size - pos));
      if (n <= 0) break;
      pcm.blit(pos, p, 0, n);
      pos += n;
    }
    return {rate: sampleRate, channels: channels, pcm: pcm};
  }

  /**
   * A frame (BGRX) as an opaque bitmap at the wanted size.
   */
  public static function toBitmap(pixels:haxe.io.BytesData, w:Int, h:Int, tw:Int, th:Int):BitmapData
  {
    var src = Bytes.ofData(pixels);
    var ba = new ByteArray(w * h * 4);
    ba.endian = openfl.utils.Endian.BIG_ENDIAN; // setPixels reads 32-bit ARGB in this order
    for (i in 0...w * h)
    {
      var p = i * 4;
      ba[p] = 255;
      ba[p + 1] = src.get(p + 2);
      ba[p + 2] = src.get(p + 1);
      ba[p + 3] = src.get(p);
    }
    ba.position = 0;
    var full = new BitmapData(w, h, true, 0);
    full.setPixels(new Rectangle(0, 0, w, h), ba);
    if (tw == w && th == h) return full;
    var out = new BitmapData(tw, th, true, 0);
    var m = new Matrix();
    m.scale(tw / w, th / h);
    out.draw(full, m, null, null, null, true);
    full.dispose();
    return out;
  }
}
#end
#end
