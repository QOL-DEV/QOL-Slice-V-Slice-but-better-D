package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import funkin.qol.editors.animator.AnimData;
import funkin.qol.util.QOLFilePicker;
import funkin.qol.util.QOLFilePicker.QOLPickedFile;
import funkin.qol.util.QOLInflate;
import funkin.qol.util.QOLXml;
import funkin.qol.util.QOLXml.QOLXmlNode;
import funkin.qol.util.QOLXml.QOLXmlParser;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import openfl.display.BitmapData;

/**
 * Adobe Animate documents: .fla files (a ZIP of XML and binary data) and .xfl folders.
 *
 * Reading covers what Animate documents are made of: the library's symbols (graphics and movie clips) with their
 * timelines, layers (normal, guide, mask, folder, camera), keyframes with labels, classic tweens (with Animate's
 * eases and custom ease curves) and shape tweens, merge-drawing shapes and drawing objects (solid, gradient and image
 * fills, strokes), groups, symbol and image instances (color effects, filters, blend modes, looping), text, frame
 * blend modes, the camera, images (Animate's own compressed format, JPEGs and PNGs) and sounds.
 */
class XFLFile
{
  /**
   * Read an Animate document from the picked files: one .fla, a .zip of an .xfl folder, every file of an .xfl folder,
   * or (on desktop) its DOMDocument.xml / .xfl file.
   */
  public static function read(files:Array<QOLPickedFile>, onDone:AnimDoc->Array<String>->Void, onError:String->Void,
      ?onProgress:Float->String->Void):Void->Void
  {
    var src:XFLSource;
    try
    {
      src = new XFLSource(files);
    }
    catch (e:Dynamic)
    {
      onError(Std.string(e));
      return () -> {};
    }
    if (!src.exists('DOMDocument.xml'))
    {
      onError('No DOMDocument.xml found. Pick an .fla file, or every file of an .xfl folder (or a .zip of it).');
      return () -> {};
    }
    var reader = new XFLReader(src, onDone, onError, onProgress);
    reader.start();
    return reader.cancel;
  }

  public static function write(doc:AnimDoc):Bytes
    return XFLWriter.write(doc);

  //
  // Numbers and colors
  //

  /**
   * "#RRGGBB" (with an alpha 0..1) as ARGB.
   */
  public static function color(hex:Null<String>, alpha:Float = 1, def:Int = 0x000000):Int
  {
    var rgb = def;
    if (hex != null && hex.length > 1)
    {
      var v = Std.parseInt('0x' + hex.substr(1));
      if (v != null) rgb = v & 0xFFFFFF;
    }
    var a = Std.int(Math.round(Math.max(0, Math.min(1, alpha)) * 255));
    return (a << 24) | rgb;
  }

  public static function hexColor(argb:Int):String
    return '#' + StringTools.hex(argb & 0xFFFFFF, 6);
}

/**
 * The files of an Animate document, wherever they come from (an .fla/.zip, picked files, or a folder on disk).
 */
private typedef XFLEntry =
{
  var data:Bytes;
  var pos:Int;
  var len:Int;
  var compressed:Bool;
}

private class XFLSource
{
  var entries:Map<String, XFLEntry> = new Map();
  var baseDir:Null<String> = null;

  public function new(files:Array<QOLPickedFile>)
  {
    var zipFile = Lambda.find(files, f -> ['fla', 'zip'].contains(QOLFilePicker.ext(f.name)));
    if (zipFile != null)
    {
      var bytes = zipFile.bytes;
      // The picked file's bytes are only needed here now (big .fla files use a lot of memory).
      zipFile.bytes = null;
      readZip(bytes);
      return;
    }
    for (f in files)
    {
      if (f.bytes == null || f.bytes.length == 0) continue;
      entries.set(key(f.name), {data: f.bytes, pos: 0, len: f.bytes.length, compressed: false});
    }
    // An .xfl folder: names may start with the folder ("Name/DOMDocument.xml").
    if (!exists('DOMDocument.xml'))
    {
      var doc = Lambda.find(files, f -> StringTools.endsWith(f.name.toLowerCase(), 'domdocument.xml'));
      if (doc != null)
      {
        var prefix = doc.name.substr(0, doc.name.length - 'DOMDocument.xml'.length);
        if (prefix.length > 0)
        {
          var moved = new Map<String, XFLEntry>();
          for (k => v in entries)
            moved.set(StringTools.startsWith(k, key(prefix)) ? k.substr(prefix.length) : k, v);
          entries = moved;
        }
      }
    }
    #if sys
    // On desktop, a lone DOMDocument.xml or .xfl file brings the rest of its folder.
    var anchor = Lambda.find(files, f -> f.path != null
      && (f.name.toLowerCase() == 'domdocument.xml' || QOLFilePicker.ext(f.name) == 'xfl'));
    if (anchor != null)
    {
      var p = anchor.path;
      baseDir = sys.FileSystem.isDirectory(p) ? p : haxe.io.Path.directory(p);
    }
    #end
  }

  static inline function key(name:String):String
    return StringTools.replace(name, '\\', '/').toLowerCase();

  function readZip(bytes:Bytes):Void
  {
    // Entries point into the file's bytes (no copies). Animate's own ZIP writer gets the central directory's size
    // wrong; QOLZip copes with that.
    for (e in funkin.qol.util.QOLZip.entries(bytes))
      if (!StringTools.endsWith(e.name, '/')) entries.set(key(e.name), {data: bytes, pos: e.pos, len: e.len, compressed: e.compressed});
    // A zipped .xfl folder.
    if (!exists('DOMDocument.xml'))
    {
      for (k in [for (k in entries.keys()) k])
      {
        if (StringTools.endsWith(k, '/domdocument.xml'))
        {
          var prefix = k.substr(0, k.length - 'domdocument.xml'.length);
          var moved = new Map<String, XFLEntry>();
          for (k2 => v in entries)
            moved.set(StringTools.startsWith(k2, prefix) ? k2.substr(prefix.length) : k2, v);
          entries = moved;
          break;
        }
      }
    }
  }

  public function exists(path:String):Bool
  {
    if (entries.exists(key(path))) return true;
    #if sys
    if (baseDir != null) return sys.FileSystem.exists(haxe.io.Path.join([baseDir, path]));
    #end
    return false;
  }

  /**
   * A file's bytes (decompressed), or null.
   */
  public function load(path:String, done:Null<Bytes>->Void):Void
  {
    var e = entries.get(key(path));
    if (e != null)
    {
      if (!e.compressed) done(e.pos == 0 && e.len == e.data.length ? e.data : e.data.sub(e.pos, e.len));
      else
        QOLInflate.inflate(e.data, false, done, e.pos, e.len);
      return;
    }
    #if sys
    if (baseDir != null)
    {
      var full = haxe.io.Path.join([baseDir, path]);
      if (sys.FileSystem.exists(full) && !sys.FileSystem.isDirectory(full))
      {
        done(sys.io.File.getBytes(full));
        return;
      }
    }
    #end
    done(null);
  }
}

private class XFLSeg
{
  public var x0:Float;
  public var y0:Float;
  public var cx:Float;
  public var cy:Float;
  public var x1:Float;
  public var y1:Float;
  public var curve:Bool;

  public function new(x0:Float, y0:Float, cx:Float, cy:Float, x1:Float, y1:Float, curve:Bool)
  {
    this.x0 = x0;
    this.y0 = y0;
    this.cx = cx;
    this.cy = cy;
    this.x1 = x1;
    this.y1 = y1;
    this.curve = curve;
  }

  public inline function reversed():XFLSeg
    return new XFLSeg(x1, y1, cx, cy, x0, y0, curve);
}

/**
 * Turns an Animate document into an Animator document, a step at a time (so the progress bar moves).
 */
private class XFLReader
{
  var src:XFLSource;
  var onDone:AnimDoc->Array<String>->Void;
  var onError:String->Void;
  var onProgress:Null<Float->String->Void>;

  var dom:QOLXmlNode;
  var project:AnimProject;
  var doc:AnimDoc;
  var warnings:Array<String> = [];

  var symbolIds:Map<String, String> = new Map();
  var bitmapIds:Map<String, String> = new Map();
  var soundIds:Map<String, String> = new Map();
  var steps:Array<Void->Void> = [];
  var stepCount:Int = 0;
  var stepsDone:Int = 0;
  var failed:Bool = false;

  public function new(src:XFLSource, onDone:AnimDoc->Array<String>->Void, onError:String->Void, onProgress:Null<Float->String->Void>)
  {
    this.src = src;
    this.onDone = onDone;
    this.onError = onError;
    this.onProgress = onProgress;
  }

  function progress(text:String):Void
  {
    if (onProgress != null) onProgress(READ_SHARE + (1 - READ_SHARE) * (stepCount == 0 ? 0 : stepsDone / stepCount), text);
  }

  /**
   * Run the next step after letting the screen update.
   */
  var lastPause:Float = 0;

  function next():Void
  {
    if (failed) return;
    // Steps run back to back, with a short pause now and then so the screen can update.
    var now = haxe.Timer.stamp();
    var wait = 0;
    if (now - lastPause > 0.05)
    {
      wait = 16;
      lastPause = now + 0.016;
    }
    haxe.Timer.delay(() -> {
      if (failed) return;
      if (steps.length == 0) return;
      var step = steps.shift();
      stepsDone++;
      try
      {
        step();
      }
      catch (e:Dynamic)
      {
        fail('$e');
      }
    }, wait);
  }

  public function cancel():Void
    failed = true;

  function fail(msg:String):Void
  {
    if (failed) return;
    failed = true;
    trace('[QOL] FLA import failed: $msg\n${haxe.CallStack.toString(haxe.CallStack.exceptionStack())}');
    onError(msg);
  }

  public function start():Void
  {
    if (onProgress != null) onProgress(0, 'Reading the document...');
    src.load('DOMDocument.xml', bytes -> {
      if (bytes == null)
      {
        fail('Could not read DOMDocument.xml.');
        return;
      }
      // Big documents are read a slice at a time so the progress bar keeps moving.
      var parser = new QOLXmlParser(bytes);
      bytes = null;
      function chunk()
      {
        if (failed) return;
        try
        {
          var t0 = haxe.Timer.stamp();
          var done = false;
          while (!done && haxe.Timer.stamp() - t0 < 0.06)
            done = parser.step(1 << 19);
          if (!done)
          {
            if (onProgress != null) onProgress(parser.progress * READ_SHARE, 'Reading the document... ${Std.int(parser.progress * 100)}%');
            haxe.Timer.delay(chunk, 1);
            return;
          }
          dom = parser.root.child('DOMDocument');
          if (dom == null) throw 'This isn\'t an Animate document (no DOMDocument).';
          plan();
        }
        catch (e:Dynamic)
        {
          fail('$e');
          return;
        }
        next();
      }
      chunk();
    });
  }

  /**
   * How much of the progress bar reading the XML takes.
   */
  static inline final READ_SHARE:Float = 0.25;

  function plan():Void
  {
    var w = Std.int(dom.float('width', 550));
    var h = Std.int(dom.float('height', 400));
    var fps = dom.float('frameRate', 24);
    var timelines = dom.child('timelines')?.all('DOMTimeline') ?? [];
    var name = timelines.length > 0 ? 'Animate import' : 'Animate import';
    project = AnimData.newProject(name, w, h, fps);
    project.bg = XFLFile.color(dom.get('backgroundColor') ?? '#FFFFFF');
    doc = new AnimDoc(project);

    // Library items get ids up front (instances can refer to symbols that come later).
    var includes = dom.child('symbols')?.all('Include') ?? [];
    for (inc in includes)
    {
      var href = inc.get('href');
      if (href == null) continue;
      var itemName = StringTools.endsWith(href, '.xml') ? href.substr(0, href.length - 4) : href;
      if (!symbolIds.exists(itemName)) symbolIds.set(itemName, AnimData.makeId('sym'));
    }

    var media = dom.child('media')?.children ?? [];
    for (item in media)
    {
      switch (item.name)
      {
        case 'DOMBitmapItem':
          steps.push(() -> loadBitmap(item));
        case 'DOMSoundItem':
          steps.push(() -> loadSound(item));
        case 'DOMVideoItem':
          warnings.push('Embedded video "${item.get('name')}" was left out (import the video file itself with File > Import > Video).');
        default:
      }
    }
    var symbols:Array<AnimSymbol> = [];
    for (inc in includes)
    {
      var href = inc.get('href');
      if (href == null) continue;
      steps.push(() -> loadSymbol(href, symbols));
    }
    for (i in 0...timelines.length)
    {
      var tl = timelines[i];
      if (i == 0)
      {
        // The scene is usually the biggest part: one step per layer.
        var xls = tl.child('layers')?.all('DOMLayer') ?? [];
        var depths = layerDepths(xls);
        var layers:Array<AnimLayer> = [];
        for (li in 0...xls.length)
        {
          steps.push(() -> {
            progress('Scene layer ${li + 1} of ${xls.length}: ${xls[li].get('name') ?? ''}');
            for (l in convertLayer(xls[li], depths[li], li))
              layers.push(l);
            // Done with this part of the document.
            xls[li].children = [];
            next();
          });
        }
        steps.push(() -> {
          project.symbols[0].layers = layers.length > 0 ? layers : [AnimData.newLayer('Layer 1', 'vector', 0)];
          project.symbols[0].name = tl.get('name') ?? 'Scene';
          next();
        });
        continue;
      }
      steps.push(() -> {
        progress('Converting ${tl.get('name') ?? 'the scene'}...');
        var layers = convertTimeline(tl);
        {
          // Extra scenes become symbols named after them.
          var s = AnimData.newSymbol(AnimData.makeId('sym'), tl.get('name') ?? 'Scene ${i + 1}');
          s.layers = layers;
          symbols.push(s);
          warnings.push('Scene "${s.name}" is in the Library as a symbol (the Animator has one scene).');
        }
        next();
      });
    }
    steps.push(() -> {
      for (s in symbols)
        project.symbols.push(s);
      finish();
    });
    stepCount = steps.length;
  }

  function finish():Void
  {
    // Let the document's XML and the file go.
    dom = null;
    steps = [];
    src = null;
    doc.clearHistory();
    // Ready the undo history (the first save of a big document takes a moment).
    if (onProgress != null) onProgress(1, 'Getting the timeline ready...');
    haxe.Timer.delay(() -> {
      if (failed) return;
      doc.snapshot();
      onDone(doc, warnings);
    }, 16);
  }

  //
  // Library: images
  //

  function loadBitmap(item:QOLXmlNode):Void
  {
    var name = item.get('name') ?? 'Bitmap';
    progress('Image: $name');
    var dat = item.get('bitmapDataHRef');
    var href = item.get('href');
    var smooth = item.bool('allowSmoothing', false);
    function done(bmp:Null<BitmapData>)
    {
      if (bmp != null)
      {
        var id = doc.addBitmap(bmp, name, true);
        var info = doc.bitmapInfo(id);
        if (info != null && !smooth) info.smooth = false;
        bitmapIds.set(name, id);
      }
      else
        warnings.push('Image "$name" could not be read.');
      next();
    }
    function fromLibrary()
    {
      if (href == null)
      {
        done(null);
        return;
      }
      src.load('LIBRARY/' + href, b -> {
        if (b == null) done(null);
        else
          AnimIO.decodeImage(b, done);
      });
    }
    if (dat == null)
    {
      fromLibrary();
      return;
    }
    src.load('bin/' + dat, b -> {
      if (b == null)
      {
        fromLibrary();
        return;
      }
      decodeDat(b, bmp -> bmp != null ? done(bmp) : fromLibrary());
    });
  }

  /**
   * Animate's image data: its own compressed ARGB format, or a JPEG.
   */
  static function decodeDat(b:Bytes, done:Null<BitmapData>->Void):Void
  {
    if (b.length > 26 && b.get(0) == 0x03 && b.get(1) == 0x05)
    {
      var w = b.getUInt16(4), h = b.getUInt16(6);
      var hasAlpha = b.get(24) != 0;
      var compressed = b.get(25) != 0;
      var pos = 26;
      function toBitmap(px:Null<Bytes>)
      {
        if (px == null || px.length < w * h * 4)
        {
          done(null);
          return;
        }
        // Premultiplied ARGB -> straight ARGB.
        for (i in 0...w * h)
        {
          var p = i * 4;
          var a = hasAlpha ? px.get(p) : 255;
          if (!hasAlpha) px.set(p, 255);
          else if (a > 0 && a < 255)
          {
            for (k in 1...4)
              px.set(p + k, Std.int(Math.min(255, (px.get(p + k) * 255 + (a >> 1)) / a)));
          }
        }
        done(AnimIO.fromARGB(px, w, h));
      }
      if (!compressed)
      {
        toBitmap(b.sub(pos, b.length - pos));
        return;
      }
      // Chunks: u16 length, data... until a 0 length; together they're one zlib stream.
      var buf = new haxe.io.BytesBuffer();
      while (pos + 2 <= b.length)
      {
        var n = b.getUInt16(pos);
        pos += 2;
        if (n == 0) break;
        buf.addBytes(b, pos, Std.int(Math.min(n, b.length - pos)));
        pos += n;
      }
      QOLInflate.inflate(buf.getBytes(), true, toBitmap);
      return;
    }
    // JPEG (sometimes behind a few extra bytes), PNG or GIF.
    var start = 0;
    while (start + 1 < Std.int(Math.min(b.length, 16)) && !(b.get(start) == 0xFF && b.get(start + 1) == 0xD8))
      start++;
    if (start + 1 < b.length && b.get(start) == 0xFF && b.get(start + 1) == 0xD8)
    {
      AnimIO.decodeImage(b.sub(start, b.length - start), done);
      return;
    }
    AnimIO.decodeImage(b, done);
  }

  //
  // Library: sounds
  //

  function loadSound(item:QOLXmlNode):Void
  {
    var name = item.get('name') ?? 'Sound';
    progress('Sound: $name');
    var href = item.get('href');
    var dat = item.get('soundDataHRef');
    function decode(bytes:Null<Bytes>, fileName:String)
    {
      if (bytes == null)
      {
        warnings.push('Sound "$name" could not be read.');
        next();
        return;
      }
      AnimMedia.decodeAudio({name: fileName, bytes: bytes}, a -> {
        var snd = doc.addSound(haxe.io.Path.withoutExtension(name), a.rate, a.channels, a.pcm);
        soundIds.set(name, snd.id);
        next();
      }, err -> {
        warnings.push('Sound "$name" could not be decoded ($err).');
        next();
      });
    }
    function fromDat()
    {
      if (dat == null)
      {
        decode(null, name);
        return;
      }
      src.load('bin/' + dat, b -> {
        if (b == null)
        {
          decode(null, name);
          return;
        }
        // Uncompressed sounds are raw PCM; compressed ones keep their MP3 data.
        var isMp3 = b.length > 2 && b.get(0) == 0xFF && (b.get(1) & 0xE0) == 0xE0;
        if (!isMp3 && !(b.length > 3 && AnimSound.ascii(b, 0, 3) == 'ID3')) decode(rawToWav(b, item.get('format') ?? '44kHz 16bit Stereo'), name + '.wav');
        else
          decode(b, name + '.mp3');
      });
    }
    if (href != null && src.exists('LIBRARY/' + href))
    {
      src.load('LIBRARY/' + href, b -> b != null ? decode(b, href) : fromDat());
      return;
    }
    fromDat();
  }

  static function rawToWav(b:Bytes, format:String):Bytes
  {
    var rate = 44100;
    if (format.indexOf('5kHz') >= 0) rate = 5512;
    else if (format.indexOf('11kHz') >= 0) rate = 11025;
    else if (format.indexOf('22kHz') >= 0) rate = 22050;
    var channels = format.indexOf('Mono') >= 0 ? 1 : 2;
    var bits = format.indexOf('8bit') >= 0 ? 8 : 16;
    if (bits == 16) return AnimSound.writeWav(b, rate, channels);
    // 8-bit -> 16-bit.
    var out = Bytes.alloc(b.length * 2);
    for (i in 0...b.length)
    {
      var v = (b.get(i) - 128) << 8;
      out.set(i * 2, v & 0xFF);
      out.set(i * 2 + 1, (v >> 8) & 0xFF);
    }
    return AnimSound.writeWav(out, rate, channels);
  }

  //
  // Library: symbols
  //

  function loadSymbol(href:String, out:Array<AnimSymbol>):Void
  {
    progress('Symbol: ${href.substr(0, href.length - 4)}');
    src.load('LIBRARY/' + href, bytes -> {
      if (bytes == null)
      {
        warnings.push('Library item "$href" is missing.');
        next();
        return;
      }
      try
      {
        var item = QOLXml.parse(bytes).child('DOMSymbolItem');
        if (item != null)
        {
          var itemName = href.substr(0, href.length - 4);
          var id = symbolIds.get(itemName);
          var realName = item.get('name') ?? itemName;
          if (!symbolIds.exists(realName)) symbolIds.set(realName, id);
          var type = item.get('symbolType');
          var sym:AnimSymbol = {
            id: id,
            name: realName,
            kind: type == 'graphic' ? 'graphic' : 'movieclip',
            layers: []
          };
          var tl = item.path('timeline', 'DOMTimeline');
          if (tl != null) sym.layers = convertTimeline(tl);
          if (sym.layers.length == 0) sym.layers = [AnimData.newLayer('Layer 1', 'vector', 0)];
          out.push(sym);
        }
      }
      catch (e:Dynamic)
      {
        warnings.push('Symbol "$href" could not be read ($e).');
      }
      next();
    });
  }

  //
  // Timelines
  //

  function convertTimeline(tl:QOLXmlNode):Array<AnimLayer>
  {
    var xls = tl.child('layers')?.all('DOMLayer') ?? [];
    var depths = layerDepths(xls);
    var out:Array<AnimLayer> = [];
    for (i in 0...xls.length)
      for (l in convertLayer(xls[i], depths[i], i))
        out.push(l);
    return out;
  }

  /**
   * How deeply each layer is nested in folders and masks.
   */
  static function layerDepths(xls:Array<QOLXmlNode>):Array<Int>
  {
    var hasCamera = Lambda.exists(xls, l -> l.get('layerType') == 'camera');
    var depths:Array<Int> = [];
    for (i in 0...xls.length)
    {
      var xl = xls[i];
      var d = 0;
      if (xl.has('parentLayerIndex'))
      {
        // With a camera layer, parent indexes don't count it.
        var p = xl.int('parentLayerIndex') + (hasCamera ? 1 : 0);
        if (p >= 0 && p < i) d = depths[p] + 1;
      }
      depths.push(d);
    }
    return depths;
  }

  function convertLayer(xl:QOLXmlNode, depth:Int, index:Int):Array<AnimLayer>
  {
    var type = xl.get('layerType') ?? 'normal';
    var layer = AnimData.newLayer(xl.get('name') ?? 'Layer', 'vector', index);
    layer.color = XFLFile.color(xl.get('color') ?? '#4F80FF');
    layer.visible = xl.bool('visible', true);
    layer.locked = xl.bool('locked', false);
    if (xl.bool('outline', false)) layer.outline = true;
    if (depth > 0) layer.depth = depth;
    if (xl.bool('attachedToCamera', false)) layer.fixed = true;
    layer.frames = [];
    switch (type)
    {
      case 'folder':
        layer.kind = 'folder';
        return [layer];
      case 'mask':
        layer.mask = true;
      case 'guide':
        layer.guide = true;
      case 'camera':
        layer.kind = 'camera';
      default:
    }
    var xframes = xl.child('frames')?.all('DOMFrame') ?? [];
    var soundFrames:Array<AnimKeyframe> = [];
    var hasSound = false;
    var hasElements = false;
    for (xf in xframes)
    {
      var start = xf.int('index');
      var duration = Std.int(Math.max(1, xf.int('duration', 1)));
      var key:AnimKeyframe = {start: start, duration: duration, elements: []};
      var label = xf.get('name');
      if (label != null && label != '' && xf.get('labelType') != 'comment') key.label = label;
      var blend = xf.get('blendMode');
      if (blend != null && blend != 'normal') key.blend = blend;
      var tween = tweenOf(xf);
      if (tween != null) key.tween = tween;
      var elements = xf.child('elements');
      if (layer.kind == 'camera')
      {
        key.camera = cameraOf(elements);
      }
      else if (elements != null)
      {
        convertElements(elements.children, key.elements);
        if (key.elements.length > 0) hasElements = true;
      }
      var filters = xf.child('filters');
      if (filters != null)
      {
        var fl = filtersOf(filters);
        if (fl.length > 0) key.filters = fl;
      }
      layer.frames.push(key);
      // Sounds go on a sound layer of their own.
      var sk:AnimKeyframe = {start: start, duration: duration, elements: []};
      var soundName = xf.get('soundName');
      if (soundName != null && soundIds.exists(soundName))
      {
        sk.sound = soundIds.get(soundName);
        var inPoint = xf.float('inPoint44', 0);
        if (inPoint > 0) sk.soundStart = inPoint / 44100;
        hasSound = true;
      }
      soundFrames.push(sk);
    }
    if (layer.frames.length == 0) layer.frames.push({start: 0, duration: 1, elements: []});
    if (!hasSound) return [layer];
    var audio = AnimData.newLayer(layer.name, 'audio', index);
    audio.frames = soundFrames;
    audio.depth = layer.depth;
    audio.visible = layer.visible;
    if (!hasElements && layer.kind == 'vector' && layer.mask != true) return [audio];
    audio.name = layer.name + ' (sound)';
    return [layer, audio];
  }

  function tweenOf(xf:QOLXmlNode):Null<AnimTween>
  {
    var type = xf.get('tweenType');
    if (type != 'motion' && type != 'shape') return null;
    var tween:AnimTween = {ease: 'linear'};
    if (type == 'shape') tween.shape = true;
    var accel = xf.float('acceleration', 0);
    if (accel != 0) tween.accel = accel;
    var tweens = xf.child('tweens');
    if (tweens != null)
    {
      var custom = Lambda.find(tweens.all('CustomEase'), e -> (e.get('target') ?? 'all') == 'all') ?? tweens.child('CustomEase');
      var named = Lambda.find(tweens.all('Ease'), e -> (e.get('target') ?? 'all') == 'all') ?? tweens.child('Ease');
      if (custom != null)
      {
        var pts:Array<Float> = [];
        for (p in custom.all('Point'))
        {
          pts.push(p.float('x', 0));
          pts.push(p.float('y', 0));
        }
        if (pts.length >= 8) tween.curve = pts;
      }
      else if (named != null) tween.ease = AnimEase.fromAnimate(named.get('method'));
    }
    var rotate = xf.get('motionTweenRotate');
    var times = xf.int('motionTweenRotateTimes', 1);
    if (rotate == 'clockwise') tween.spins = times;
    else if (rotate == 'counter-clockwise') tween.spins = -times;
    return tween;
  }

  /**
   * The camera keyframe from Animate's camera layer (a hidden "__Camera__" instance the view follows).
   */
  function cameraOf(elements:Null<QOLXmlNode>):AnimCamera
  {
    var cam = AnimData.defaultCamera(project);
    if (elements == null) return cam;
    for (el in elements.children)
    {
      if (el.name != 'DOMSymbolInstance') continue;
      var m = matrixOf(el);
      var scale = Math.sqrt(m[0] * m[0] + m[1] * m[1]);
      cam.x = m[4];
      cam.y = m[5];
      cam.zoom = scale > 0.0001 ? 1 / scale : 1;
      cam.rotation = Math.atan2(m[1], m[0]) * 180 / Math.PI;
      break;
    }
    return cam;
  }

  //
  // Elements
  //

  static function matrixOf(node:QOLXmlNode):Array<Float>
  {
    var m = node.path('matrix', 'Matrix');
    if (m == null) return [1, 0, 0, 1, 0, 0];
    return [m.float('a', 1), m.float('b', 0), m.float('c', 0), m.float('d', 1), m.float('tx', 0), m.float('ty', 0)];
  }

  static function setMatrix(el:AnimElement, m:Array<Float>):Void
  {
    el.a = m[0];
    el.b = m[1];
    el.c = m[2];
    el.d = m[3];
    el.tx = m[4];
    el.ty = m[5];
  }

  function convertElements(nodes:Array<QOLXmlNode>, out:Array<AnimElement>):Void
  {
    for (node in nodes)
    {
      switch (node.name)
      {
        case 'DOMShape':
          var paths = shapePaths(node);
          if (paths.length == 0) continue;
          var el = AnimData.identity('shape');
          setMatrix(el, matrixOf(node));
          el.paths = paths;
          out.push(el);
        case 'DOMGroup':
          // Group members are in the group's parent's coordinates already.
          var members = node.child('members');
          if (members != null) convertElements(members.children, out);
        case 'DOMSymbolInstance':
          var el = symbolInstance(node);
          if (el != null) out.push(el);
        case 'DOMBitmapInstance':
          var id = bitmapIds.get(node.get('libraryItemName') ?? '');
          if (id == null) continue;
          var el = AnimData.identity('bitmap');
          el.bitmap = id;
          setMatrix(el, matrixOf(node));
          out.push(el);
        case 'DOMStaticText' | 'DOMDynamicText' | 'DOMInputText':
          var el = textOf(node);
          if (el != null) out.push(el);
        default:
      }
    }
  }

  function symbolInstance(node:QOLXmlNode):Null<AnimElement>
  {
    var id = symbolIds.get(node.get('libraryItemName') ?? '');
    if (id == null) return null;
    var el = AnimData.identity('symbol');
    el.symbol = id;
    setMatrix(el, matrixOf(node));
    var tp = node.path('transformationPoint', 'Point');
    if (tp != null)
    {
      el.px = tp.float('x', 0);
      el.py = tp.float('y', 0);
    }
    var graphic = node.get('symbolType') == 'graphic';
    el.loop = graphic ? switch (node.get('loop') ?? 'loop')
    {
      case 'play once': 'once';
      case 'single frame': 'single';
      case 'loop reverse': 'loopReverse';
      case 'play once reverse': 'onceReverse';
      default: 'loop';
    } : 'loop';
    if (graphic && node.has('firstFrame')) el.firstFrame = node.int('firstFrame');
    if (graphic && node.has('lastFrame')) el.lastFrame = node.int('lastFrame');
    var blend = node.get('blendMode');
    if (blend != null && blend != 'normal') el.blend = blend;
    if (node.get('isVisible') == 'false') el.hidden = true;
    var name = node.get('name');
    if (name != null && name != '') el.name = name;
    var c = node.path('color', 'Color');
    if (c != null) colorOf(c, el);
    var filters = node.child('filters');
    if (filters != null)
    {
      var fl = filtersOf(filters);
      if (fl.length > 0) el.filters = fl;
    }
    return el;
  }

  static function colorOf(c:QOLXmlNode, el:AnimElement):Void
  {
    var advanced = false;
    for (k in ['redMultiplier', 'greenMultiplier', 'blueMultiplier', 'redOffset', 'greenOffset', 'blueOffset', 'alphaOffset'])
      if (c.has(k)) advanced = true;
    if (advanced)
    {
      el.ct = [
        c.float('redMultiplier', 1), c.float('greenMultiplier', 1), c.float('blueMultiplier', 1), c.float('alphaMultiplier', 1),
        c.float('redOffset', 0), c.float('greenOffset', 0), c.float('blueOffset', 0), c.float('alphaOffset', 0)
      ];
      return;
    }
    if (c.has('alphaMultiplier')) el.alpha = c.float('alphaMultiplier', 1);
    if (c.has('brightness')) el.brightness = c.float('brightness', 0);
    if (c.has('tintMultiplier'))
    {
      el.tint = XFLFile.color(c.get('tintColor') ?? '#000000');
      el.tintAmount = c.float('tintMultiplier', 0);
    }
  }

  static function filtersOf(node:QOLXmlNode):Array<AnimFilter>
  {
    var out:Array<AnimFilter> = [];
    for (f in node.children)
    {
      if (f.get('enabled') == 'false') continue;
      var q = f.int('quality', 1);
      switch (f.name)
      {
        case 'BlurFilter':
          out.push({type: 'blur', blurX: f.float('blurX', 5), blurY: f.float('blurY', 5), quality: q});
        case 'GlowFilter':
          out.push({
            type: 'glow',
            color: XFLFile.color(f.get('color') ?? '#FF0000'),
            alpha: f.float('alpha', 1),
            blurX: f.float('blurX', 5),
            blurY: f.float('blurY', 5),
            strength: f.float('strength', 1),
            inner: f.bool('inner'),
            knockout: f.bool('knockout'),
            quality: q
          });
        case 'DropShadowFilter':
          out.push({
            type: 'shadow',
            color: XFLFile.color(f.get('color') ?? '#000000'),
            alpha: f.float('alpha', 1),
            blurX: f.float('blurX', 5),
            blurY: f.float('blurY', 5),
            strength: f.float('strength', 1),
            distance: f.float('distance', 5),
            angle: f.float('angle', 45),
            inner: f.bool('inner'),
            knockout: f.bool('knockout'),
            quality: q
          });
        case 'AdjustColorFilter':
          out.push({
            type: 'adjust',
            brightness: f.float('brightness', 0),
            contrast: f.float('contrast', 0),
            saturation: f.float('saturation', 0),
            hue: f.float('hue', 0)
          });
        case 'BevelFilter':
          out.push({
            type: 'bevel',
            highlight: XFLFile.color(f.get('highlightColor') ?? '#FFFFFF', f.float('highlightAlpha', 1)),
            shadowColor: XFLFile.color(f.get('shadowColor') ?? '#000000', f.float('shadowAlpha', 1)),
            blurX: f.float('blurX', 5),
            blurY: f.float('blurY', 5),
            strength: f.float('strength', 1),
            distance: f.float('distance', 5),
            angle: f.float('angle', 45),
            knockout: f.bool('knockout'),
            quality: q
          });
        case 'GradientBevelFilter' | 'GradientGlowFilter':
          var entries = f.all('GradientEntry');
          var first = entries.length > 0 ? entries[0] : null;
          var last = entries.length > 0 ? entries[entries.length - 1] : null;
          if (f.name == 'GradientGlowFilter')
          {
            out.push({
              type: 'glow',
              color: XFLFile.color(last?.get('color') ?? '#FFFFFF'),
              alpha: last?.float('alpha', 1) ?? 1,
              blurX: f.float('blurX', 5),
              blurY: f.float('blurY', 5),
              strength: f.float('strength', 1),
              inner: f.get('type') == 'inner',
              knockout: f.bool('knockout'),
              quality: q
            });
          }
          else
          {
            out.push({
              type: 'bevel',
              highlight: XFLFile.color(last?.get('color') ?? '#FFFFFF', last?.float('alpha', 1) ?? 1),
              shadowColor: XFLFile.color(first?.get('color') ?? '#000000', first?.float('alpha', 1) ?? 1),
              blurX: f.float('blurX', 5),
              blurY: f.float('blurY', 5),
              strength: f.float('strength', 1),
              distance: f.float('distance', 5),
              angle: f.float('angle', 45),
              knockout: f.bool('knockout'),
              quality: q
            });
          }
        default:
      }
    }
    return out;
  }

  function textOf(node:QOLXmlNode):Null<AnimElement>
  {
    var runs = node.child('textRuns')?.all('DOMTextRun') ?? [];
    var text = new StringBuf();
    var attrs:Null<QOLXmlNode> = null;
    for (r in runs)
    {
      var chars = r.child('characters')?.text ?? '';
      text.add(StringTools.replace(chars, '\r', '\n'));
      if (attrs == null) attrs = r.path('textAttrs', 'DOMTextAttrs');
    }
    var s = text.toString();
    if (s == '') return null;
    var el = AnimData.identity('text');
    setMatrix(el, matrixOf(node));
    el.text = s;
    el.font = attrs?.get('face') ?? '_sans';
    el.size = attrs?.float('size', 12) ?? 12;
    el.color = XFLFile.color(attrs?.get('fillColor') ?? '#000000', attrs?.float('alpha', 1) ?? 1);
    if (!node.bool('autoExpand', false) && node.has('width')) el.boxWidth = node.float('width');
    el.tx += node.float('left', 0);
    return el;
  }

  //
  // Shapes
  //

  /**
   * Animate stores shapes as edges, each with the fill on its left and right and a stroke. Fills are rebuilt by
   * following the edges around each filled area; strokes by joining edges end to end.
   */
  function shapePaths(node:QOLXmlNode):Array<AnimPath>
  {
    var fills = new Map<Int, AnimPath>();
    var fillNode = node.child('fills');
    if (fillNode != null)
    {
      for (fs in fillNode.all('FillStyle'))
      {
        var style = fillStyle(fs);
        if (style != null) fills.set(fs.int('index'), style);
      }
    }
    var strokes = new Map<Int, AnimPath>();
    var strokeNode = node.child('strokes');
    if (strokeNode != null)
    {
      for (ss in strokeNode.all('StrokeStyle'))
      {
        var style = strokeStyle(ss);
        if (style != null) strokes.set(ss.int('index'), style);
      }
    }
    var fillSegs = new Map<Int, Array<XFLSeg>>();
    var strokeSegs = new Map<Int, Array<Array<XFLSeg>>>();
    var edges = node.child('edges');
    if (edges == null) return [];
    for (e in edges.all('Edge'))
    {
      var s = e.get('edges');
      if (s == null) continue;
      var f0 = e.int('fillStyle0'), f1 = e.int('fillStyle1'), st = e.int('strokeStyle');
      if (f0 == 0 && f1 == 0 && st == 0) continue;
      var segs = parseEdges(s);
      if (segs.length == 0) continue;
      if (f0 != f1)
      {
        if (f1 > 0 && fills.exists(f1))
        {
          var list = fillSegs.get(f1);
          if (list == null) fillSegs.set(f1, list = []);
          for (sg in segs)
            list.push(sg);
        }
        if (f0 > 0 && fills.exists(f0))
        {
          var list = fillSegs.get(f0);
          if (list == null) fillSegs.set(f0, list = []);
          for (sg in segs)
            list.push(sg.reversed());
        }
      }
      if (st > 0 && strokes.exists(st))
      {
        var list = strokeSegs.get(st);
        if (list == null) strokeSegs.set(st, list = []);
        list.push(segs);
      }
    }
    var out:Array<AnimPath> = [];
    var fillKeys = [for (k in fillSegs.keys()) k];
    fillKeys.sort((a, b) -> a - b);
    for (k in fillKeys)
    {
      var d = loops(fillSegs.get(k));
      if (d.length == 0) continue;
      var p:AnimPath = Reflect.copy(fills.get(k));
      p.d = d;
      out.push(p);
    }
    var strokeKeys = [for (k in strokeSegs.keys()) k];
    strokeKeys.sort((a, b) -> a - b);
    for (k in strokeKeys)
    {
      var d = lines(strokeSegs.get(k));
      if (d.length == 0) continue;
      var p:AnimPath = Reflect.copy(strokes.get(k));
      p.d = d;
      out.push(p);
    }
    return out;
  }

  static inline function px(twips:Float):Float
    return Math.round(twips * 5) / 100; // twips -> pixels, to 1/100 pixel

  static inline function pointKey(x:Float, y:Float):String
    return Math.round(x * 8) + ',' + Math.round(y * 8);

  /**
   * Join fill edges (fill on their right) into closed outlines.
   */
  static function loops(segs:Array<XFLSeg>):Array<Float>
  {
    var byStart = new Map<String, Array<Int>>();
    for (i in 0...segs.length)
    {
      var k = pointKey(segs[i].x0, segs[i].y0);
      var list = byStart.get(k);
      if (list == null) byStart.set(k, list = []);
      list.push(i);
    }
    var used = [for (_ in 0...segs.length) false];
    var d:Array<Float> = [];
    for (i in 0...segs.length)
    {
      if (used[i]) continue;
      var first = segs[i];
      var startKey = pointKey(first.x0, first.y0);
      d.push(0);
      d.push(px(first.x0));
      d.push(px(first.y0));
      var cur = i;
      var guard = 0;
      while (cur >= 0 && guard++ < segs.length + 1)
      {
        used[cur] = true;
        var s = segs[cur];
        if (s.curve)
        {
          d.push(2);
          d.push(px(s.cx));
          d.push(px(s.cy));
          d.push(px(s.x1));
          d.push(px(s.y1));
        }
        else
        {
          d.push(1);
          d.push(px(s.x1));
          d.push(px(s.y1));
        }
        var endKey = pointKey(s.x1, s.y1);
        if (endKey == startKey) break;
        cur = -1;
        var cands = byStart.get(endKey);
        if (cands != null)
        {
          for (c in cands)
          {
            if (!used[c])
            {
              cur = c;
              break;
            }
          }
        }
      }
      d.push(4);
    }
    return d;
  }

  /**
   * Stroke edges as lines (each edge's pieces already run end to end).
   */
  static function lines(groups:Array<Array<XFLSeg>>):Array<Float>
  {
    var d:Array<Float> = [];
    var lastX = Math.NaN, lastY = Math.NaN;
    for (segs in groups)
    {
      for (s in segs)
      {
        if (s.x0 != lastX || s.y0 != lastY)
        {
          d.push(0);
          d.push(px(s.x0));
          d.push(px(s.y0));
        }
        if (s.curve)
        {
          d.push(2);
          d.push(px(s.cx));
          d.push(px(s.cy));
          d.push(px(s.x1));
          d.push(px(s.y1));
        }
        else
        {
          d.push(1);
          d.push(px(s.x1));
          d.push(px(s.y1));
        }
        lastX = s.x1;
        lastY = s.y1;
      }
    }
    return d;
  }

  /**
   * Animate's edge commands: "!x y" moves, "|x y" (or "/") draws a line, "[cx cy x y" (or "]") a curve; "S1" marks
   * selections. Numbers are twips, in decimal or "#hex.hex" fixed point.
   */
  public static function parseEdges(s:String):Array<XFLSeg>
  {
    var out:Array<XFLSeg> = [];
    var n = s.length;
    var i = 0;
    var x = 0.0, y = 0.0;
    inline function code(j:Int):Int
      return StringTools.fastCodeAt(s, j);
    function num():Float
    {
      while (i < n)
      {
        var c = code(i);
        if (c == 32 || c == 10 || c == 13 || c == 9) i++;
        else
          break;
      }
      if (i >= n) return 0;
      if (code(i) == '#'.code)
      {
        i++;
        var ip = 0.0, digits = 0;
        while (i < n)
        {
          var c = code(i);
          var v = hexVal(c);
          if (v < 0) break;
          ip = ip * 16 + v;
          digits++;
          i++;
        }
        var frac = 0.0;
        if (i < n && code(i) == '.'.code)
        {
          i++;
          var scale = 1 / 16;
          while (i < n)
          {
            var v = hexVal(code(i));
            if (v < 0) break;
            frac += v * scale;
            scale /= 16;
            i++;
          }
        }
        var value = ip + frac;
        // 6 hex digits are a signed 24-bit number.
        if (digits >= 6 && ip >= 0x800000) value -= 0x1000000;
        return value;
      }
      var start = i;
      while (i < n)
      {
        var c = code(i);
        if ((c >= '0'.code && c <= '9'.code) || c == '.'.code || c == '-'.code || c == '+'.code || c == 'e'.code || c == 'E'.code) i++;
        else
          break;
      }
      if (i == start)
      {
        i++;
        return 0;
      }
      var f = Std.parseFloat(s.substring(start, i));
      return Math.isNaN(f) ? 0 : f;
    }
    while (i < n)
    {
      var c = code(i);
      switch (c)
      {
        case '!'.code:
          i++;
          x = num();
          y = num();
        case '|'.code | '/'.code:
          i++;
          var nx = num(), ny = num();
          out.push(new XFLSeg(x, y, 0, 0, nx, ny, false));
          x = nx;
          y = ny;
        case '['.code | ']'.code:
          i++;
          var cx = num(), cy = num(), nx = num(), ny = num();
          out.push(new XFLSeg(x, y, cx, cy, nx, ny, true));
          x = nx;
          y = ny;
        case 'S'.code:
          i++;
          while (i < n && code(i) >= '0'.code && code(i) <= '9'.code)
            i++;
        default:
          i++;
      }
    }
    return out;
  }

  static inline function hexVal(c:Int):Int
  {
    return if (c >= '0'.code && c <= '9'.code) c - '0'.code; else if (c >= 'A'.code && c <= 'F'.code) c - 'A'.code + 10; else if (c >= 'a'.code
      && c <= 'f'.code) c - 'a'.code + 10; else -1;
  }

  function fillStyle(fs:QOLXmlNode):Null<AnimPath>
  {
    for (f in fs.children)
    {
      var style = fillOf(f);
      if (style != null) return style;
    }
    return null;
  }

  function fillOf(f:QOLXmlNode):Null<AnimPath>
  {
    switch (f.name)
    {
      case 'SolidColor':
        return {fill: XFLFile.color(f.get('color') ?? '#000000', f.float('alpha', 1)), d: []};
      case 'LinearGradient' | 'RadialGradient':
        var colors:Array<Int> = [], ratios:Array<Int> = [];
        for (g in f.all('GradientEntry'))
        {
          colors.push(XFLFile.color(g.get('color') ?? '#000000', g.float('alpha', 1)));
          ratios.push(Std.int(Math.round(Math.max(0, Math.min(1, g.float('ratio', 0))) * 255)));
        }
        if (colors.length == 0) return null;
        var spread = f.get('spreadMethod');
        return {
          d: [],
          gradient: {
            type: f.name == 'RadialGradient' ? 'radial' : 'linear',
            colors: colors,
            ratios: ratios,
            matrix: matrixOf(f),
            spread: spread == 'reflect' || spread == 'repeat' ? spread : null,
            focal: f.has('focalPointRatio') ? f.float('focalPointRatio') : null,
            linearRGB: f.get('interpolationMethod') == 'linearRGB' ? true : null
          }
        };
      case 'BitmapFill':
        var id = bitmapIds.get(f.get('bitmapPath') ?? '');
        if (id == null) return {fill: 0xFF808080, d: []};
        var m = matrixOf(f);
        // Image fill matrices are in twips per pixel.
        return {
          d: [],
          bitmapFill: {
            bitmap: id,
            matrix: [m[0] / 20, m[1] / 20, m[2] / 20, m[3] / 20, m[4], m[5]],
            clip: f.bool('bitmapIsClipped', false) ? true : null,
            smooth: doc.bitmapInfo(id)?.smooth
          }
        };
      default:
        return null;
    }
  }

  function strokeStyle(ss:QOLXmlNode):Null<AnimPath>
  {
    var st = ss.children.length > 0 ? ss.children[0] : null;
    if (st == null) return null;
    var color = 0xFF000000;
    var fillNode = st.child('fill');
    if (fillNode != null && fillNode.children.length > 0)
    {
      var f = fillOf(fillNode.children[0]);
      if (f != null)
      {
        if (f.fill != null) color = f.fill;
        else if (f.gradient != null) color = f.gradient.colors[0];
      }
    }
    var hairline = st.get('solidStyle') == 'hairline' || st.get('scaleMode') == 'none';
    var p:AnimPath = {
      stroke: color,
      width: hairline && !st.has('weight') ? 1 : st.float('weight', 1),
      d: []
    };
    var caps = st.get('caps');
    if (caps == 'none' || caps == 'square') p.caps = caps;
    var joints = st.get('joints');
    if (joints == 'miter' || joints == 'bevel') p.joints = joints;
    if (hairline) p.hairline = true;
    return p;
  }
}
#end
