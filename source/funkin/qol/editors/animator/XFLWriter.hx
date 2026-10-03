package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import funkin.qol.editors.animator.AnimData;
import funkin.qol.util.QOLDeflate;
import funkin.qol.util.QOLXml;
import funkin.qol.util.QOLZip;
import haxe.io.Bytes;
import hxClipper.Clipper;
import openfl.display.BitmapData;

private typedef XFLOutSeg =
{
  var curve:Bool;
  var cx:Float;
  var cy:Float;
  var x:Float;
  var y:Float;
}

private typedef XFLOutContour =
{
  var x0:Float;
  var y0:Float;
  var segs:Array<XFLOutSeg>;
  var closed:Bool;
}

/**
 * Writing Animator documents as Adobe Animate .fla files: the library (symbols, images in Animate's own lossless
 * format, sounds), every timeline with its layers (folders, masks, guides, the camera), keyframes with labels,
 * classic and shape tweens with their eases, shapes (as drawing objects, with solid, gradient and image fills and
 * strokes), symbol and image instances with color effects, filters and blend modes, and text. Paint layers become
 * images on a normal layer.
 */
class XFLWriter
{
  public static function write(doc:AnimDoc):Bytes
    return new XFLWriter(doc).run();

  var doc:AnimDoc;
  var files:Array<{name:String, data:Bytes}> = [];
  var media:StringBuf = new StringBuf();
  var includes:StringBuf = new StringBuf();
  var symbolNames:Map<String, String> = new Map();
  var bitmapNames:Map<String, String> = new Map();
  var soundNames:Map<String, String> = new Map();
  var usedNames:Map<String, Bool> = new Map();
  var itemCount:Int = 0;
  var datCount:Int = 0;
  var stamp:Int;

  function new(doc:AnimDoc)
  {
    this.doc = doc;
    stamp = Std.int(Date.now().getTime() / 1000);
  }

  function run():Bytes
  {
    var p = doc.project;
    // Library names (unique, safe as file names).
    for (i in 1...p.symbols.length)
      symbolNames.set(p.symbols[i].id, uniqueName(p.symbols[i].name));
    var canvasCount = 0;
    for (b in p.bitmaps)
    {
      if (b.library != true && !usedCanvas(b.id)) continue;
      var base = b.library == true ? haxe.io.Path.withoutExtension(b.name) : 'Paint ${++canvasCount}';
      bitmapNames.set(b.id, uniqueName(base));
    }
    if (p.sounds != null) for (s in p.sounds)
      soundNames.set(s.id, uniqueName(haxe.io.Path.withoutExtension(s.name)) + '.wav');

    for (b in p.bitmaps)
      if (bitmapNames.exists(b.id)) writeBitmap(b);
    if (p.sounds != null) for (s in p.sounds)
      writeSound(s);
    for (i in 1...p.symbols.length)
      writeSymbol(p.symbols[i]);

    var main = new StringBuf();
    main.add('<DOMDocument xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://ns.adobe.com/xfl/2008/"');
    main.add(attr('backgroundColor', hex(p.bg)));
    main.add(attr('width', '${p.width}'));
    main.add(attr('height', '${p.height}'));
    main.add(attr('frameRate', num(p.fps)));
    main.add(' currentTimeline="1" xflVersion="2.97" creatorInfo="QOL Slice Animator" platform="Windows" versionInfo="Saved by QOL Slice" majorVersion="17" buildNumber="0" nextSceneIdentifier="2">\n');
    var m = media.toString();
    if (m != '') main.add('  <media>\n$m  </media>\n');
    var inc = includes.toString();
    if (inc != '') main.add('  <symbols>\n$inc  </symbols>\n');
    main.add('  <timelines>\n');
    writeTimeline(main, doc.main, p.symbols[0].name == null || p.symbols[0].name == '' ? 'Scene 1' : p.symbols[0].name, '    ', true);
    main.add('  </timelines>\n</DOMDocument>\n');

    var docName = AnimIO.fileId(p.name);
    var out:Array<{name:String, data:Bytes}> = [
      {name: 'mimetype', data: Bytes.ofString('application/vnd.adobe.xfl')},
      {name: '$docName.xfl', data: Bytes.ofString('PROXY-CS5')},
      {name: 'DOMDocument.xml', data: Bytes.ofString(main.toString())},
      {name: 'META-INF/metadata.xml', data: Bytes.ofString(metadata())}
    ];
    for (f in files)
      out.push(f);
    return QOLZip.write(out, true);
  }

  function usedCanvas(id:String):Bool
  {
    for (s in doc.project.symbols)
      for (l in s.layers)
        if (l.kind == 'bitmap') for (k in l.frames)
          if (k.bitmap == id) return true;
    return false;
  }

  function uniqueName(name:String):String
  {
    var base = name == null || StringTools.trim(name) == '' ? 'Item' : StringTools.trim(name);
    for (c in ['/', '\\', ':', '*', '?', '"', '<', '>', '|'])
      base = StringTools.replace(base, c, '_');
    var n = base;
    var i = 2;
    while (usedNames.exists(n.toLowerCase()))
      n = '$base ${i++}';
    usedNames.set(n.toLowerCase(), true);
    return n;
  }

  function itemId():String
  {
    itemCount++;
    return StringTools.hex(stamp, 8).toLowerCase() + '-' + StringTools.hex(itemCount, 8).toLowerCase();
  }

  function datName():String
  {
    datCount++;
    return 'M $datCount $stamp.dat';
  }

  //
  // Library items
  //

  function writeBitmap(info:AnimBitmapInfo):Void
  {
    var bmp = doc.getBitmap(info.id);
    if (bmp == null) return;
    var name = bitmapNames.get(info.id);
    var dat = datName();
    files.push({name: 'bin/$dat', data: losslessDat(bmp)});
    media.add('    <DOMBitmapItem');
    media.add(attr('name', name));
    media.add(attr('itemID', itemId()));
    media.add(attr('sourceLastImported', '$stamp'));
    if (info.smooth != false) media.add(' allowSmoothing="true"');
    media.add(' originalCompressionType="lossless" quality="50"');
    media.add(attr('href', name + '.png'));
    media.add(attr('bitmapDataHRef', dat));
    media.add(attr('frameRight', '${bmp.width * 20}'));
    media.add(attr('frameBottom', '${bmp.height * 20}'));
    media.add('/>\n');
  }

  /**
   * Animate's lossless image data: a small header, then premultiplied ARGB rows as a zlib stream cut into chunks.
   */
  public static function losslessDat(bmp:BitmapData):Bytes
  {
    var w = bmp.width, h = bmp.height;
    var argb = AnimIO.argbBytes(bmp);
    var hasAlpha = false;
    for (i in 0...w * h)
    {
      var p = i * 4;
      var a = argb.get(p);
      if (a == 255) continue;
      hasAlpha = true;
      // Straight -> premultiplied.
      for (k in 1...4)
        argb.set(p + k, Std.int((argb.get(p + k) * a + 127) / 255));
    }
    var z = QOLDeflate.zlib(argb);
    var out = new haxe.io.BytesOutput();
    out.bigEndian = false;
    out.writeByte(0x03);
    out.writeByte(0x05);
    out.writeUInt16(Std.int(Math.min(0xFFFF, w * 4)));
    out.writeUInt16(w);
    out.writeUInt16(h);
    out.writeInt32(0);
    out.writeInt32(w * 20);
    out.writeInt32(0);
    out.writeInt32(h * 20);
    out.writeByte(hasAlpha ? 1 : 0);
    out.writeByte(1);
    var pos = 0;
    while (pos < z.length)
    {
      var n = Std.int(Math.min(2048, z.length - pos));
      out.writeUInt16(n);
      out.writeBytes(z, pos, n);
      pos += n;
    }
    out.writeUInt16(0);
    return out.getBytes();
  }

  function writeSound(info:AnimSoundInfo):Void
  {
    var snd = doc.getSound(info.id);
    if (snd == null) return;
    var name = soundNames.get(info.id);
    var pcm = stereo44(snd);
    var dat = datName();
    files.push({name: 'bin/$dat', data: pcm});
    media.add('    <DOMSoundItem');
    media.add(attr('name', name));
    media.add(attr('itemID', itemId()));
    media.add(attr('sourceLastImported', '$stamp'));
    media.add(attr('href', name));
    media.add(attr('soundDataHRef', dat));
    media.add(' format="44kHz 16bit Stereo"');
    media.add(attr('sampleCount', '${Std.int(pcm.length / 4)}'));
    media.add(' exportFormat="1" exportBits="13"');
    media.add(attr('dataLength', '${pcm.length}'));
    media.add('/>\n');
  }

  /**
   * A sound as 44.1 kHz stereo 16-bit samples (what Animate keeps for uncompressed sounds).
   */
  static function stereo44(snd:AnimSound):Bytes
  {
    if (snd.rate == 44100 && snd.channels == 2) return snd.pcm;
    var frames = Std.int(snd.length * 44100);
    var out = Bytes.alloc(frames * 4);
    for (i in 0...frames)
    {
      var src = Std.int(Math.min(snd.frames - 1, i * snd.rate / 44100));
      var l = snd.sample(src, 0);
      var r = snd.channels > 1 ? snd.sample(src, 1) : l;
      out.set(i * 4, l & 0xFF);
      out.set(i * 4 + 1, (l >> 8) & 0xFF);
      out.set(i * 4 + 2, r & 0xFF);
      out.set(i * 4 + 3, (r >> 8) & 0xFF);
    }
    return out;
  }

  function writeSymbol(sym:AnimSymbol):Void
  {
    var name = symbolNames.get(sym.id);
    var graphic = sym.kind != 'movieclip';
    var x = new StringBuf();
    x.add('<DOMSymbolItem xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://ns.adobe.com/xfl/2008/"');
    x.add(attr('name', name));
    var id = itemId();
    x.add(attr('itemID', id));
    if (graphic) x.add(' symbolType="graphic"');
    x.add(attr('lastModified', '$stamp'));
    x.add('>\n  <timeline>\n');
    writeTimeline(x, sym, name, '    ', false);
    x.add('  </timeline>\n</DOMSymbolItem>\n');
    files.push({name: 'LIBRARY/$name.xml', data: Bytes.ofString(x.toString())});
    includes.add('    <Include');
    includes.add(attr('href', '$name.xml'));
    if (graphic) includes.add(' itemIcon="1"');
    includes.add(' loadImmediate="false"');
    includes.add(attr('itemID', id));
    includes.add(attr('lastModified', '$stamp'));
    includes.add('/>\n');
  }

  //
  // Timelines
  //

  function writeTimeline(x:StringBuf, sym:AnimSymbol, name:String, ind:String, isMain:Bool):Void
  {
    // Animate keeps the camera layer first, and parent indexes don't count it.
    var order:Array<Int> = [];
    var camera = -1;
    for (i in 0...sym.layers.length)
    {
      if (isMain && sym.layers[i].kind == 'camera' && camera < 0) camera = i;
      else
        order.push(i);
    }
    x.add('$ind<DOMTimeline');
    x.add(attr('name', name));
    if (camera >= 0) x.add(' cameraLayerEnabled="true"');
    x.add('>\n$ind  <layers>\n');
    var indexOf = new Map<Int, Int>();
    for (k in 0...order.length)
      indexOf.set(order[k], k);
    if (camera >= 0) writeCameraLayer(x, sym.layers[camera], ind + '    ');
    for (k in 0...order.length)
    {
      var li = order[k];
      var parent = AnimData.parentOf(sym, li);
      writeLayer(x, sym, li, parent >= 0 && indexOf.exists(parent) ? indexOf.get(parent) : -1, ind + '    ');
    }
    x.add('$ind  </layers>\n$ind</DOMTimeline>\n');
  }

  function layerAttrs(x:StringBuf, l:AnimLayer):Void
  {
    x.add(attr('name', l.name ?? 'Layer'));
    x.add(attr('color', hex(l.color)));
    if (!l.visible) x.add(' visible="false"');
    if (l.locked) x.add(' locked="true"');
    if (l.outline == true) x.add(' outline="true" useOutlineView="true"');
    if (l.fixed == true) x.add(' attachedToCamera="true"');
    x.add(' autoNamed="false"');
  }

  function writeCameraLayer(x:StringBuf, l:AnimLayer, ind:String):Void
  {
    x.add('$ind<DOMLayer');
    layerAttrs(x, l);
    x.add(' layerType="camera">\n$ind  <frames>\n');
    var last = AnimData.defaultCamera(doc.project);
    for (k in contiguous(l))
    {
      openFrame(x, k, ind + '    ');
      // Gaps hold the camera where it was.
      var cam = k.camera ?? last;
      last = cam;
      var s = 1 / Math.max(0.0001, cam.zoom);
      var r = cam.rotation * Math.PI / 180;
      x.add('$ind      <elements>\n');
      x.add('$ind        <DOMSymbolInstance libraryItemName="__Camera__" name="___camera___instance" isVisible="false">\n');
      x.add('$ind          <matrix>\n$ind            <Matrix');
      matrixAttrs(x, Math.cos(r) * s, Math.sin(r) * s, -Math.sin(r) * s, Math.cos(r) * s, cam.x, cam.y);
      x.add('/>\n$ind          </matrix>\n');
      x.add('$ind          <transformationPoint>\n$ind            <Point/>\n$ind          </transformationPoint>\n');
      x.add('$ind        </DOMSymbolInstance>\n$ind      </elements>\n');
      x.add('$ind    </DOMFrame>\n');
    }
    x.add('$ind  </frames>\n$ind</DOMLayer>\n');
  }

  /**
   * Keyframes from frame 0 with no gaps (Animate's timelines have none).
   */
  static function contiguous(l:AnimLayer):Array<AnimKeyframe>
  {
    var keys = l.frames.copy();
    keys.sort((a, b) -> a.start - b.start);
    var out:Array<AnimKeyframe> = [];
    var at = 0;
    for (k in keys)
    {
      if (k.duration <= 0 || k.start + k.duration <= at) continue;
      if (k.start > at) out.push({start: at, duration: k.start - at, elements: []});
      if (k.start < at)
      {
        var trimmed:AnimKeyframe = Reflect.copy(k);
        trimmed.duration = k.start + k.duration - at;
        trimmed.start = at;
        out.push(trimmed);
      }
      else
        out.push(k);
      at = out[out.length - 1].start + out[out.length - 1].duration;
    }
    if (out.length == 0) out.push({start: 0, duration: 1, elements: []});
    return out;
  }

  function writeLayer(x:StringBuf, sym:AnimSymbol, li:Int, parentIndex:Int, ind:String):Void
  {
    var l = sym.layers[li];
    x.add('$ind<DOMLayer');
    layerAttrs(x, l);
    if (parentIndex >= 0) x.add(attr('parentLayerIndex', '$parentIndex'));
    if (l.kind == 'folder')
    {
      x.add(' layerType="folder"');
      if (l.collapsed == true) x.add(' open="false"');
      x.add('/>\n');
      return;
    }
    if (l.mask == true) x.add(' layerType="mask"');
    else if (l.guide == true) x.add(' layerType="guide"');
    if (l.mask == true && l.collapsed == true) x.add(' open="false"');
    x.add('>\n$ind  <frames>\n');
    var keys = contiguous(l);
    for (ki in 0...keys.length)
    {
      var k = keys[ki];
      var fi = ind + '    ';
      openFrame(x, k, fi);
      if (l.kind == 'audio')
      {
        x.add('$fi  <elements/>\n$fi</DOMFrame>\n');
        continue;
      }
      x.add('$fi  <elements>\n');
      if (l.kind == 'bitmap')
      {
        var name = bitmapNames.get(k.bitmap ?? '');
        if (name != null)
        {
          x.add('$fi    <DOMBitmapInstance');
          x.add(attr('libraryItemName', name));
          x.add('>\n');
          writeMatrix(x, 1, 0, 0, 1, k.bx ?? 0, k.by ?? 0, fi + '      ');
          x.add('$fi    </DOMBitmapInstance>\n');
        }
      }
      else
      {
        for (el in k.elements)
          writeElement(x, el, fi + '    ');
      }
      x.add('$fi  </elements>\n$fi</DOMFrame>\n');
    }
    x.add('$ind  </frames>\n$ind</DOMLayer>\n');
  }

  function openFrame(x:StringBuf, k:AnimKeyframe, ind:String):Void
  {
    x.add('$ind<DOMFrame');
    x.add(attr('index', '${k.start}'));
    if (k.duration > 1) x.add(attr('duration', '${k.duration}'));
    var tw = k.tween;
    if (tw != null)
    {
      x.add(tw.shape == true ? ' tweenType="shape" keyMode="17922"' : ' tweenType="motion" motionTweenSnap="true" keyMode="22017"');
      if (tw.accel != null && tw.accel != 0 && tw.curve == null) x.add(attr('acceleration', num(Math.max(-100, Math.min(100, tw.accel)))));
      var spins = tw.spins ?? 0;
      if (spins > 0) x.add(attr('motionTweenRotate', 'clockwise') + attr('motionTweenRotateTimes', '$spins'));
      else if (spins < 0) x.add(attr('motionTweenRotate', 'counter-clockwise') + attr('motionTweenRotateTimes', '${-spins}'));
    }
    else
      x.add(' keyMode="9728"');
    if (k.label != null && k.label != '') x.add(attr('name', k.label) + ' labelType="name"');
    if (k.blend != null && k.blend != 'normal') x.add(attr('blendMode', k.blend));
    if (k.sound != null && soundNames.exists(k.sound))
    {
      x.add(attr('soundName', soundNames.get(k.sound)));
      x.add(' soundSync="stream"');
      if ((k.soundStart ?? 0) > 0) x.add(attr('inPoint44', '${Std.int(k.soundStart * 44100)}'));
    }
    var ease = tw != null ? easeXml(tw, ind + '  ') : null;
    if (ease != null && ease.custom) x.add(' hasCustomEase="true"');
    if (ease != null && ease.method != null) x.add(attr('easeMethodName', ease.method));
    x.add('>\n');
    if (ease != null) x.add(ease.xml);
  }

  /**
   * Animate's own eases for the ones it has; everything else as a custom ease curve.
   */
  static function easeXml(tw:AnimTween, ind:String):Null<{xml:String, custom:Bool, method:Null<String>}>
  {
    var curve = tw.curve;
    if (curve == null)
    {
      if (tw.accel != null && tw.accel != 0) return null;
      var e = tw.ease ?? 'linear';
      if (e == 'linear') return null;
      for (fam in ['quad', 'cube', 'quart', 'quint', 'sine'])
      {
        if (StringTools.startsWith(e, fam))
        {
          var method = AnimEase.toAnimate(e);
          return {xml: '$ind<tweens>\n$ind  <Ease target="all"${attr('method', method)}/>\n$ind</tweens>\n', custom: false, method: method};
        }
      }
      curve = curveOf(funkin.qol.util.QOLEase.get(e), e.indexOf('elastic') >= 0 || e.indexOf('bounce') >= 0 ? 16 : 6);
    }
    var b = new StringBuf();
    b.add('$ind<tweens>\n$ind  <CustomEase target="all">\n');
    var i = 0;
    while (i + 1 < curve.length)
    {
      b.add('$ind    <Point');
      if (curve[i] != 0) b.add(attr('x', num(curve[i])));
      if (curve[i + 1] != 0) b.add(attr('y', num(curve[i + 1])));
      b.add('/>\n');
      i += 2;
    }
    b.add('$ind  </CustomEase>\n$ind</tweens>\n');
    return {xml: b.toString(), custom: true, method: null};
  }

  /**
   * An ease function as Bezier pieces (Hermite curves through samples).
   */
  static function curveOf(f:Float->Float, pieces:Int):Array<Float>
  {
    var out:Array<Float> = [0, f(0)];
    var h = 1e-3;
    inline function slope(t:Float):Float
      return (f(Math.min(1, t + h)) - f(Math.max(0, t - h))) / (Math.min(1, t + h) - Math.max(0, t - h));
    for (i in 0...pieces)
    {
      var t0 = i / pieces, t1 = (i + 1) / pieces;
      var dt = t1 - t0;
      var y0 = f(t0), y1 = f(t1);
      out.push(t0 + dt / 3);
      out.push(y0 + slope(t0) * dt / 3);
      out.push(t1 - dt / 3);
      out.push(y1 - slope(t1) * dt / 3);
      out.push(t1);
      out.push(y1);
    }
    return out;
  }

  //
  // Elements
  //

  function writeElement(x:StringBuf, el:AnimElement, ind:String):Void
  {
    switch (el.type)
    {
      case 'shape':
        writeShape(x, el, ind);
      case 'symbol':
        var name = symbolNames.get(el.symbol ?? '');
        if (name == null) return;
        var sym = doc.symbol(el.symbol);
        var graphic = sym == null || sym.kind != 'movieclip';
        x.add('$ind<DOMSymbolInstance');
        x.add(attr('libraryItemName', name));
        if (graphic)
        {
          x.add(' symbolType="graphic"');
          x.add(attr('loop', switch (el.loop ?? 'loop')
          {
            case 'once': 'play once';
            case 'single': 'single frame';
            case 'loopReverse': 'loop reverse';
            case 'onceReverse': 'play once reverse';
            default: 'loop';
          }));
          if ((el.firstFrame ?? 0) > 0) x.add(attr('firstFrame', '${el.firstFrame}'));
          if (el.lastFrame != null) x.add(attr('lastFrame', '${el.lastFrame}'));
        }
        if (el.name != null && el.name != '') x.add(attr('name', el.name));
        if (el.hidden == true) x.add(' isVisible="false"');
        if (el.blend != null && el.blend != 'normal') x.add(attr('blendMode', el.blend));
        x.add('>\n');
        writeMatrix(x, el.a, el.b, el.c, el.d, el.tx, el.ty, ind + '  ');
        if (el.px != null || el.py != null)
          x.add('$ind  <transformationPoint>\n$ind    <Point${attr('x', num(el.px ?? 0))}${attr('y', num(el.py ?? 0))}/>\n$ind  </transformationPoint>\n');
        writeColor(x, el, ind + '  ');
        writeFilters(x, el.filters, ind + '  ');
        x.add('$ind</DOMSymbolInstance>\n');
      case 'bitmap':
        var name = bitmapNames.get(el.bitmap ?? '');
        if (name == null) return;
        x.add('$ind<DOMBitmapInstance');
        x.add(attr('libraryItemName', name));
        x.add('>\n');
        writeMatrix(x, el.a, el.b, el.c, el.d, el.tx, el.ty, ind + '  ');
        x.add('$ind</DOMBitmapInstance>\n');
      case 'text':
        x.add('$ind<DOMStaticText');
        if (el.boxWidth != null && el.boxWidth > 0) x.add(attr('width', num(el.boxWidth)));
        else
          x.add(' autoExpand="true"');
        x.add(' isSelectable="false">\n');
        writeMatrix(x, el.a, el.b, el.c, el.d, el.tx, el.ty, ind + '  ');
        x.add('$ind  <textRuns>\n$ind    <DOMTextRun>\n');
        x.add('$ind      <characters>${QOLXml.escape(StringTools.replace(el.text ?? '', '\n', '\r'))}</characters>\n');
        x.add('$ind      <textAttrs>\n$ind        <DOMTextAttrs');
        x.add(attr('face', el.font ?? '_sans'));
        x.add(attr('size', num(el.size ?? 32)));
        x.add(attr('fillColor', hex(el.color ?? 0xFF000000)));
        var a = ((el.color ?? 0xFF000000) >>> 24) / 255;
        if (a < 1) x.add(attr('alpha', num(a)));
        x.add('/>\n$ind      </textAttrs>\n$ind    </DOMTextRun>\n$ind  </textRuns>\n$ind</DOMStaticText>\n');
      default:
    }
  }

  static function writeMatrix(x:StringBuf, a:Float, b:Float, c:Float, d:Float, tx:Float, ty:Float, ind:String):Void
  {
    if (a == 1 && b == 0 && c == 0 && d == 1 && tx == 0 && ty == 0) return;
    x.add('$ind<matrix>\n$ind  <Matrix');
    matrixAttrs(x, a, b, c, d, tx, ty);
    x.add('/>\n$ind</matrix>\n');
  }

  static function matrixAttrs(x:StringBuf, a:Float, b:Float, c:Float, d:Float, tx:Float, ty:Float):Void
  {
    if (a != 1) x.add(attr('a', num(a)));
    if (b != 0) x.add(attr('b', num(b)));
    if (c != 0) x.add(attr('c', num(c)));
    if (d != 1) x.add(attr('d', num(d)));
    if (tx != 0) x.add(attr('tx', num(tx)));
    if (ty != 0) x.add(attr('ty', num(ty)));
  }

  static function writeColor(x:StringBuf, el:AnimElement, ind:String):Void
  {
    var c = new StringBuf();
    if (el.ct != null && el.ct.length >= 8)
    {
      var names = ['redMultiplier', 'greenMultiplier', 'blueMultiplier', 'alphaMultiplier', 'redOffset', 'greenOffset', 'blueOffset', 'alphaOffset'];
      for (i in 0...8)
        if (el.ct[i] != (i < 4 ? 1 : 0)) c.add(attr(names[i], num(el.ct[i])));
    }
    else
    {
      if ((el.alpha ?? 1) != 1) c.add(attr('alphaMultiplier', num(el.alpha)));
      if ((el.brightness ?? 0) != 0) c.add(attr('brightness', num(el.brightness)));
      if (el.tint != null && (el.tintAmount ?? 0) != 0) c.add(attr('tintMultiplier', num(el.tintAmount)) + attr('tintColor', hex(el.tint)));
    }
    var s = c.toString();
    if (s != '') x.add('$ind<color>\n$ind  <Color$s/>\n$ind</color>\n');
  }

  static function writeFilters(x:StringBuf, filters:Null<Array<AnimFilter>>, ind:String):Void
  {
    if (filters == null || filters.length == 0) return;
    x.add('$ind<filters>\n');
    for (f in filters)
    {
      var q = attr('quality', '${f.quality ?? 1}');
      var blur = attr('blurX', num(f.blurX ?? 5)) + attr('blurY', num(f.blurY ?? 5));
      switch (f.type)
      {
        case 'blur':
          x.add('$ind  <BlurFilter$blur$q/>\n');
        case 'glow':
          x.add('$ind  <GlowFilter$blur${attr('color', hex(f.color ?? 0xFF0000))}${attr('alpha', num(f.alpha ?? 1))}${attr('strength', num(f.strength ?? 1))}');
          if (f.inner == true) x.add(' inner="true"');
          if (f.knockout == true) x.add(' knockout="true"');
          x.add('$q/>\n');
        case 'shadow':
          x.add('$ind  <DropShadowFilter$blur${attr('color', hex(f.color ?? 0))}${attr('alpha', num(f.alpha ?? 1))}${attr('strength', num(f.strength ?? 1))}');
          x.add(attr('distance', num(f.distance ?? 5)) + attr('angle', num(f.angle ?? 45)));
          if (f.inner == true) x.add(' inner="true"');
          if (f.knockout == true) x.add(' knockout="true"');
          x.add('$q/>\n');
        case 'adjust':
          x.add('$ind  <AdjustColorFilter${attr('brightness', num(f.brightness ?? 0))}${attr('contrast', num(f.contrast ?? 0))}');
          x.add('${attr('saturation', num(f.saturation ?? 0))}${attr('hue', num(f.hue ?? 0))}/>\n');
        case 'bevel':
          var hi = f.highlight ?? 0xFFFFFFFF, sh = f.shadowColor ?? 0xFF000000;
          x.add('$ind  <BevelFilter$blur${attr('highlightColor', hex(hi))}${attr('highlightAlpha', num(((hi >>> 24) & 0xFF) / 255))}');
          x.add('${attr('shadowColor', hex(sh))}${attr('shadowAlpha', num(((sh >>> 24) & 0xFF) / 255))}');
          x.add('${attr('strength', num(f.strength ?? 1))}${attr('distance', num(f.distance ?? 5))}${attr('angle', num(f.angle ?? 45))}$q/>\n');
        default:
      }
    }
    x.add('$ind</filters>\n');
  }

  //
  // Shapes
  //

  function writeShape(x:StringBuf, el:AnimElement, ind:String):Void
  {
    if (el.paths == null || el.paths.length == 0) return;
    var fills = new StringBuf(), strokes = new StringBuf(), edges = new StringBuf();
    var fillCount = 0, strokeCount = 0;
    for (p in el.paths)
    {
      var filled = p.fill != null || p.gradient != null || p.bitmapFill != null;
      if (filled)
      {
        fillCount++;
        fills.add('$ind    <FillStyle index="$fillCount">\n');
        fills.add(fillXml(p, ind + '      '));
        fills.add('$ind    </FillStyle>\n');
        for (c in fillContours(p))
          edges.add('$ind    <Edge' + c.side + '="$fillCount" edges="${edgeString(c.contour)}"/>\n');
      }
      if (p.stroke != null && (p.width ?? 1) > 0)
      {
        strokeCount++;
        strokes.add('$ind    <StrokeStyle index="$strokeCount">\n$ind      <SolidStroke');
        strokes.add(attr('scaleMode', p.hairline == true ? 'none' : 'normal'));
        strokes.add(attr('weight', num(p.width ?? 1)));
        if (p.caps == 'none' || p.caps == 'square') strokes.add(attr('caps', p.caps));
        if (p.joints == 'miter' || p.joints == 'bevel') strokes.add(attr('joints', p.joints));
        strokes.add('>\n$ind        <fill>\n$ind          <SolidColor${colorAttrs(p.stroke)}/>\n$ind        </fill>\n');
        strokes.add('$ind      </SolidStroke>\n$ind    </StrokeStyle>\n');
        for (c in contoursOf(p.d))
          edges.add('$ind    <Edge strokeStyle="$strokeCount" edges="${edgeString(c)}"/>\n');
      }
    }
    var e = edges.toString();
    if (e == '') return;
    x.add('$ind<DOMShape isDrawingObject="true">\n');
    writeMatrix(x, el.a, el.b, el.c, el.d, el.tx, el.ty, ind + '  ');
    var f = fills.toString();
    if (f != '') x.add('$ind  <fills>\n$f$ind  </fills>\n');
    var s = strokes.toString();
    if (s != '') x.add('$ind  <strokes>\n$s$ind  </strokes>\n');
    x.add('$ind  <edges>\n$e$ind  </edges>\n$ind</DOMShape>\n');
  }

  function fillXml(p:AnimPath, ind:String):String
  {
    if (p.gradient != null && p.gradient.colors.length > 0)
    {
      var g = p.gradient;
      var tag = g.type == 'radial' ? 'RadialGradient' : 'LinearGradient';
      var b = new StringBuf();
      b.add('$ind<$tag');
      if (g.spread == 'reflect' || g.spread == 'repeat') b.add(attr('spreadMethod', g.spread));
      if (g.linearRGB == true) b.add(' interpolationMethod="linearRGB"');
      if (g.focal != null && g.focal != 0) b.add(attr('focalPointRatio', num(g.focal)));
      b.add('>\n');
      var m = g.matrix;
      b.add('$ind  <matrix>\n$ind    <Matrix');
      matrixAttrs(b, m[0], m[1], m[2], m[3], m[4], m[5]);
      b.add('/>\n$ind  </matrix>\n');
      for (i in 0...g.colors.length)
        b.add('$ind  <GradientEntry${colorAttrs(g.colors[i])}${attr('ratio', num((g.ratios[i] ?? 0) / 255))}/>\n');
      b.add('$ind</$tag>\n');
      return b.toString();
    }
    if (p.bitmapFill != null && bitmapNames.exists(p.bitmapFill.bitmap))
    {
      var bf = p.bitmapFill;
      var m = bf.matrix;
      var b = new StringBuf();
      b.add('$ind<BitmapFill');
      b.add(attr('bitmapPath', bitmapNames.get(bf.bitmap)));
      if (bf.clip == true) b.add(' bitmapIsClipped="true"');
      b.add('>\n$ind  <matrix>\n$ind    <Matrix');
      // Image fill matrices are in twips per pixel.
      matrixAttrs(b, m[0] * 20, m[1] * 20, m[2] * 20, m[3] * 20, m[4], m[5]);
      b.add('/>\n$ind  </matrix>\n$ind</BitmapFill>\n');
      return b.toString();
    }
    return '$ind<SolidColor${colorAttrs(p.fill ?? 0xFF000000)}/>\n';
  }

  static function colorAttrs(argb:Int):String
  {
    var s = attr('color', hex(argb));
    var a = ((argb >>> 24) & 0xFF) / 255;
    if (a < 1) s += attr('alpha', num(a));
    return s;
  }

  /**
   * A path's outlines as Animate edges, each with the fill on the correct side (Animate fills the area to the right
   * of fillStyle1 edges and to the left of fillStyle0 ones). Brush strokes that cross themselves are tidied into
   * outlines that don't first.
   */
  function fillContours(p:AnimPath):Array<{contour:XFLOutContour, side:String}>
  {
    var contours = contoursOf(p.d);
    var polys = [for (c in contours) flatPoly(c)];
    var nonZero = AnimGeom.usesNonZero(p);
    if (nonZero && contours.length == 1 && crossesItself(polys))
    {
      contours = untangle(polys);
      polys = [for (c in contours) flatPoly(c)];
      nonZero = false;
    }
    var out:Array<{contour:XFLOutContour, side:String}> = [];
    for (ci in 0...contours.length)
    {
      var c = contours[ci];
      // Look just to the right of the outline's longest piece: is that inside the fill?
      var probe = rightProbe(polys[ci]);
      if (probe == null) continue;
      var inside = insideFill(polys, nonZero, probe.x, probe.y);
      out.push({contour: c, side: inside ? ' fillStyle1' : ' fillStyle0'});
    }
    return out;
  }

  static function flatPoly(c:XFLOutContour):Array<Float>
  {
    var out:Array<Float> = [c.x0, c.y0];
    var px = c.x0, py = c.y0;
    for (s in c.segs)
    {
      if (s.curve)
      {
        for (k in 1...9)
        {
          var t = k / 8, u = 1 - t;
          out.push(u * u * px + 2 * u * t * s.cx + t * t * s.x);
          out.push(u * u * py + 2 * u * t * s.cy + t * t * s.y);
        }
      }
      else
      {
        out.push(s.x);
        out.push(s.y);
      }
      px = s.x;
      py = s.y;
    }
    return out;
  }

  static function rightProbe(poly:Array<Float>):Null<{x:Float, y:Float}>
  {
    var best:Null<{x:Float, y:Float}> = null;
    var bestLen = 0.0;
    var n = poly.length >> 1;
    for (i in 0...n - 1)
    {
      var px = poly[i * 2], py = poly[i * 2 + 1], qx = poly[i * 2 + 2], qy = poly[i * 2 + 3];
      var dx = qx - px, dy = qy - py;
      var len = Math.sqrt(dx * dx + dy * dy);
      if (len > bestLen)
      {
        bestLen = len;
        // Right of the direction of travel (y points down): (-dy, dx).
        var e = Math.min(0.05, len / 4);
        best = {x: (px + qx) / 2 - dy / len * e, y: (py + qy) / 2 + dx / len * e};
      }
    }
    return best;
  }

  static function insideFill(polys:Array<Array<Float>>, nonZero:Bool, px:Float, py:Float):Bool
  {
    var inside = false;
    var winding = 0;
    for (poly in polys)
    {
      var n = poly.length >> 1;
      if (n < 2) continue;
      var j = n - 1;
      for (i in 0...n)
      {
        var xi = poly[i * 2], yi = poly[i * 2 + 1];
        var xj = poly[j * 2], yj = poly[j * 2 + 1];
        if (((yi > py) != (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi + 1e-12) + xi))
        {
          inside = !inside;
          winding += yi > yj ? 1 : -1;
        }
        j = i;
      }
    }
    return nonZero ? winding != 0 : inside;
  }

  /**
   * Whether an outline crosses itself (checked on its flattened lines; very long ones are assumed to).
   */
  static function crossesItself(polys:Array<Array<Float>>):Bool
  {
    if (polys.length == 0) return false;
    var p = polys[0];
    var n = p.length >> 1;
    if (n > 3000) return true;
    for (i in 0...n - 1)
    {
      var ax = p[i * 2], ay = p[i * 2 + 1], bx = p[i * 2 + 2], by = p[i * 2 + 3];
      var minX = Math.min(ax, bx), maxX = Math.max(ax, bx), minY = Math.min(ay, by), maxY = Math.max(ay, by);
      var j = i + 2;
      while (j < n - 1)
      {
        // The first and last pieces of a closed outline touch at its start.
        if (i == 0 && j == n - 2)
        {
          j++;
          continue;
        }
        var cx = p[j * 2], cy = p[j * 2 + 1], dx = p[j * 2 + 2], dy = p[j * 2 + 3];
        if (Math.max(cx, dx) >= minX && Math.min(cx, dx) <= maxX && Math.max(cy, dy) >= minY && Math.min(cy, dy) <= maxY)
        {
          var d1 = (dx - cx) * (ay - cy) - (dy - cy) * (ax - cx);
          var d2 = (dx - cx) * (by - cy) - (dy - cy) * (bx - cx);
          var d3 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
          var d4 = (bx - ax) * (dy - ay) - (by - ay) * (dx - ax);
          if (((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0))) return true;
        }
        j++;
      }
    }
    return false;
  }

  /**
   * The area a self-crossing outline covers, as outlines that don't cross (outer edges and holes).
   */
  static function untangle(polys:Array<Array<Float>>):Array<XFLOutContour>
  {
    var scale = 4.0;
    var subject:Paths = [];
    for (poly in polys)
    {
      var path:Path = [];
      var i = 0;
      while (i + 1 < poly.length)
      {
        path.push(new IntPoint(Math.round(poly[i] * scale), Math.round(poly[i + 1] * scale)));
        i += 2;
      }
      if (path.length >= 3) subject.push(path);
    }
    var c = new Clipper();
    c.addPaths(subject, PolyType.PT_SUBJECT, true);
    var solution:Paths = [];
    c.executePaths(ClipType.CT_UNION, solution, PolyFillType.PFT_NON_ZERO, PolyFillType.PFT_NON_ZERO);
    var out:Array<XFLOutContour> = [];
    for (poly in solution)
    {
      if (poly.length < 3) continue;
      var segs:Array<XFLOutSeg> = [];
      for (i in 1...poly.length + 1)
      {
        var pt = poly[i % poly.length];
        segs.push({curve: false, cx: 0, cy: 0, x: pt.x / scale, y: pt.y / scale});
      }
      out.push({x0: poly[0].x / scale, y0: poly[0].y / scale, segs: segs, closed: true});
    }
    return out;
  }

  /**
   * A path's subpaths as lines and quadratic curves (Animate's edges have no cubic curves: those are split).
   */
  static function contoursOf(d:Array<Float>):Array<XFLOutContour>
  {
    var out:Array<XFLOutContour> = [];
    var cur:Null<XFLOutContour> = null;
    var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
    function start()
    {
      if (cur == null)
      {
        cur = {x0: x, y0: y, segs: [], closed: false};
        out.push(cur);
      }
    }
    var i = 0;
    while (i < d.length)
    {
      switch (Std.int(d[i]))
      {
        case 0:
          x = sx = d[i + 1];
          y = sy = d[i + 2];
          cur = null;
          i += 3;
        case 1:
          start();
          cur.segs.push({curve: false, cx: 0, cy: 0, x: d[i + 1], y: d[i + 2]});
          x = d[i + 1];
          y = d[i + 2];
          i += 3;
        case 2:
          start();
          cur.segs.push({curve: true, cx: d[i + 1], cy: d[i + 2], x: d[i + 3], y: d[i + 4]});
          x = d[i + 3];
          y = d[i + 4];
          i += 5;
        case 3:
          start();
          // Cubic -> 4 quadratics (close enough for drawings).
          var x0 = x, y0 = y, c1x = d[i + 1], c1y = d[i + 2], c2x = d[i + 3], c2y = d[i + 4], x3 = d[i + 5], y3 = d[i + 6];
          inline function at(t:Float, a:Float, b:Float, c:Float, e:Float):Float
          {
            var u = 1 - t;
            return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * e;
          }
          inline function slope(t:Float, a:Float, b:Float, c:Float, e:Float):Float
          {
            var u = 1 - t;
            return 3 * u * u * (b - a) + 6 * u * t * (c - b) + 3 * t * t * (e - c);
          }
          var parts = 4;
          var px = x0, py = y0;
          for (k in 1...parts + 1)
          {
            var t0 = (k - 1) / parts, t1 = k / parts;
            var ex = at(t1, x0, c1x, c2x, x3), ey = at(t1, y0, c1y, c2y, y3);
            // Control point: where the tangents at both ends meet (midpoint of the two estimates).
            var h = (t1 - t0) / 2;
            var qx = (px + slope(t0, x0, c1x, c2x, x3) * h + ex - slope(t1, x0, c1x, c2x, x3) * h) / 2;
            var qy = (py + slope(t0, y0, c1y, c2y, y3) * h + ey - slope(t1, y0, c1y, c2y, y3) * h) / 2;
            cur.segs.push({curve: true, cx: qx, cy: qy, x: ex, y: ey});
            px = ex;
            py = ey;
          }
          x = x3;
          y = y3;
          i += 7;
        case 4:
          if (cur != null)
          {
            if (Math.abs(x - sx) > 1e-6 || Math.abs(y - sy) > 1e-6) cur.segs.push({curve: false, cx: 0, cy: 0, x: sx, y: sy});
            cur.closed = true;
          }
          cur = null;
          x = sx;
          y = sy;
          i += 1;
        default:
          i = d.length;
      }
    }
    return [for (c in out) if (c.segs.length > 0) c];
  }

  /**
   * Animate's edge commands, in twips: "!x y" moves, "|x y" lines, "[cx cy x y" curves.
   */
  static function edgeString(c:XFLOutContour):String
  {
    var b = new StringBuf();
    var px = tw(c.x0), py = tw(c.y0);
    for (s in c.segs)
    {
      b.add('!$px $py');
      var nx = tw(s.x), ny = tw(s.y);
      if (s.curve) b.add('[${tw(s.cx)} ${tw(s.cy)} $nx $ny');
      else
        b.add('|$nx $ny');
      px = nx;
      py = ny;
    }
    return b.toString();
  }

  static inline function tw(px:Float):String
    return num(Math.round(px * 200) / 10);

  //
  // Text
  //

  static function attr(name:String, value:String):String
    return ' $name="${QOLXml.escape(value)}"';

  static function hex(argb:Int):String
    return '#' + StringTools.hex(argb & 0xFFFFFF, 6);

  /**
   * A number the way Animate writes them (no exponents, at most 4 decimals).
   */
  static function num(v:Float):String
  {
    if (Math.isNaN(v) || !Math.isFinite(v)) return '0';
    var r = Math.round(v * 10000) / 10000;
    if (r == Math.ffloor(r) && Math.abs(r) < 2147483647) return Std.string(Std.int(r));
    var neg = r < 0;
    var a = Math.abs(r);
    var whole = Math.ffloor(a);
    var frac = Std.int(Math.round((a - whole) * 10000));
    if (frac >= 10000)
    {
      whole += 1;
      frac -= 10000;
    }
    var fs = StringTools.lpad(Std.string(frac), '0', 4);
    while (StringTools.endsWith(fs, '0'))
      fs = fs.substr(0, fs.length - 1);
    var ws = whole < 2147483647 ? Std.string(Std.int(whole)) : Std.string(whole);
    return (neg ? '-' : '') + ws + (fs == '' ? '' : '.' + fs);
  }

  static function metadata():String
  {
    return '<?xml version="1.0" encoding="UTF-8"?>\n<x:xmpmeta xmlns:x="adobe:ns:meta/">\n'
      + ' <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n'
      + '  <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:CreatorTool="QOL Slice Animator"/>\n'
      + ' </rdf:RDF>\n</x:xmpmeta>\n';
  }
}
#end
