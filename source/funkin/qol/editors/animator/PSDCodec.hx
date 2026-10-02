package funkin.qol.editors.animator;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;

/**
 * One layer of a PSD (pixel layer, shape layer, or a group's start/end record).
 */
typedef PSDLayer =
{
  var name:String;
  var top:Int;
  var left:Int;
  var bottom:Int;
  var right:Int;

  /**
   * 0-255.
   */
  var opacity:Int;

  /**
   * Photoshop blend key ('norm', 'mul ', 'scrn', 'pass'...).
   */
  var blend:String;

  var clipping:Bool;
  var hidden:Bool;

  /**
   * 0 = normal layer, 1/2 = group (open/closed), 3 = end of a group.
   */
  var section:Int;

  var id:Int;

  /**
   * Unpremultiplied ARGB pixels, (right-left) x (bottom-top). Null for empty layers.
   */
  var argb:Null<Bytes>;

  /**
   * Frame animation: this layer's visibility and offset per frame (Photoshop's "mlst" data).
   */
  var states:Array<PSDFrameState>;

  /**
   * Shape layers: the vector outline (Animator path commands, in document pixels).
   */
  var ?path:Array<Float>;

  var ?fill:Null<Int>;
  var ?stroke:Null<Int>;
  var ?strokeWidth:Float;
}

typedef PSDFrameState =
{
  var frames:Array<Int>;
  var enab:Null<Bool>;
  var ox:Int;
  var oy:Int;
}

typedef PSDNode =
{
  var layer:PSDLayer;

  /**
   * Groups only (bottom first, like the file).
   */
  var children:Null<Array<PSDNode>>;
}

typedef PSDFrameInfo =
{
  var id:Int;

  /**
   * In 1/100 seconds (0 = no delay).
   */
  var delay:Int;
}

typedef PSDDocument =
{
  var width:Int;
  var height:Int;

  /**
   * In file order (bottom first), including group records.
   */
  var layers:Array<PSDLayer>;

  /**
   * The layer tree (bottom first).
   */
  var root:Array<PSDNode>;

  /**
   * Frame animation (empty if none).
   */
  var frames:Array<PSDFrameInfo>;

  var activeFrame:Int;

  /**
   * The flattened image (ARGB), if the file has one.
   */
  var composite:Null<Bytes>;
}

/**
 * Layers to write. Groups are written with their children inside.
 */
typedef PSDWriteLayer =
{
  var name:String;
  var ?left:Int;
  var ?top:Int;
  var ?width:Int;
  var ?height:Int;

  /**
   * Unpremultiplied ARGB (width x height).
   */
  var ?argb:Bytes;

  var ?opacity:Int;
  var ?blend:String;
  var ?hidden:Bool;

  /**
   * Makes this a group.
   */
  var ?children:Array<PSDWriteLayer>;

  /**
   * Frame animation: frame indexes this layer shows in (null = always).
   */
  var ?visibleFrames:Array<Int>;
}

/**
 * Reads and writes Photoshop files (8-bit RGB/grayscale PSD): layers, groups, layer masks, clipping masks, shape layer
 * outlines and colors, and Photoshop's frame animation (the "Timeline > Frame Animation" data that ToonSquid and
 * Photoshop use for animated PSDs). Pure Haxe, no game dependencies.
 */
class PSDCodec
{
  //
  // Reading
  //

  var b:Bytes;
  var pos:Int = 0;

  function new(bytes:Bytes)
  {
    b = bytes;
  }

  inline function u8():Int
    return b.get(pos++);

  inline function u16():Int
  {
    var v = (b.get(pos) << 8) | b.get(pos + 1);
    pos += 2;
    return v;
  }

  inline function s16():Int
  {
    var v = u16();
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  inline function s32():Int
  {
    var v = (b.get(pos) << 24) | (b.get(pos + 1) << 16) | (b.get(pos + 2) << 8) | b.get(pos + 3);
    pos += 4;
    return v;
  }

  inline function u32():Int
    return s32();

  function f64():Float
  {
    // getDouble is little-endian; PSD is big-endian.
    var tmp = Bytes.alloc(8);
    for (i in 0...8)
      tmp.set(i, b.get(pos + 7 - i));
    pos += 8;
    return tmp.getDouble(0);
  }

  function sig():String
  {
    var s = String.fromCharCode(b.get(pos)) + String.fromCharCode(b.get(pos + 1)) + String.fromCharCode(b.get(pos + 2))
      + String.fromCharCode(b.get(pos + 3));
    pos += 4;
    return s;
  }

  function unicode():String
  {
    var n = u32();
    var buf = new StringBuf();
    for (i in 0...n)
    {
      var c = u16();
      if (c != 0) buf.addChar(c);
    }
    return buf.toString();
  }

  public static function read(bytes:Bytes):PSDDocument
  {
    return new PSDCodec(bytes).readDocument();
  }

  function readDocument():PSDDocument
  {
    if (b.length < 26 || sig() != '8BPS') throw 'This is not a Photoshop (.psd) file.';
    var version = u16();
    if (version != 1) throw 'Large documents (.psb) aren\'t supported. Save it as a regular .psd.';
    pos += 6;
    var channels = u16();
    var height = u32();
    var width = u32();
    var depth = u16();
    var mode = u16();
    if (depth != 8) throw 'This PSD uses $depth bits per channel. Save it with 8 bits per channel.';
    if (mode != 3 && mode != 1) throw 'This PSD isn\'t RGB (color mode $mode). Convert it to RGB color first.';
    var gray = mode == 1;

    var doc:PSDDocument = {
      width: width,
      height: height,
      layers: [],
      root: [],
      frames: [],
      activeFrame: 0,
      composite: null
    };

    // Color mode data.
    var skipLen = u32();
    pos += skipLen;

    // Image resources.
    var resLen = u32();
    var resEnd = pos + resLen;
    while (pos + 12 <= resEnd)
    {
      var s = sig();
      if (s != '8BIM' && s != 'MeSa' && s != 'AgHg' && s != 'PHUT' && s != 'DCSR') break;
      var id = u16();
      var nameLen = u8();
      pos += nameLen;
      if ((nameLen + 1) % 2 == 1) pos++;
      var size = u32();
      var start = pos;
      if (id == 4000) try
      {
        readAnimationResource(doc, start + size);
      }
      catch (e:Dynamic) {}
      pos = start + size + (size % 2);
    }
    pos = resEnd;

    // Layers.
    var lmLen = u32();
    var lmEnd = pos + lmLen;
    if (lmLen > 0)
    {
      var liLen = u32();
      var liEnd = pos + liLen;
      if (liLen > 0) readLayerInfo(doc, gray);
      pos = liEnd;
      // Global layer mask info.
      if (pos + 4 <= lmEnd)
      {
        var gm = u32();
        pos += gm;
      }
      // Extra blocks (some apps put the layers in here).
      while (pos + 12 <= lmEnd)
      {
        var s = sig();
        if (s != '8BIM' && s != '8B64') break;
        var key = sig();
        var len = u32();
        var start = pos;
        if ((key == 'Layr' || key == 'Lr16') && doc.layers.length == 0 && key == 'Layr') readLayerInfo(doc, gray);
        pos = start + len;
        while (pos % 4 != 0 && pos < lmEnd)
          pos++;
      }
    }
    pos = lmEnd;

    // Flattened image.
    if (pos + 2 <= b.length) try
    {
      doc.composite = readComposite(width, height, channels, gray);
    }
    catch (e:Dynamic) {}

    doc.root = buildTree(doc.layers);
    applyClipping(doc.root);
    return doc;
  }

  function readAnimationResource(doc:PSDDocument, end:Int):Void
  {
    if (sig() != 'mani') return;
    if (sig() != 'IRFR') return;
    var len = u32();
    var blockEnd = pos + len;
    while (pos + 12 <= blockEnd)
    {
      sig(); // 8BIM
      var key = sig();
      var l = u32();
      var start = pos;
      if (key == 'AnDs')
      {
        u32(); // descriptor version (16)
        var desc:Dynamic = readDescriptor();
        var frames:Array<Dynamic> = desc.FrIn ?? [];
        var byId = new Map<Int, Int>();
        for (f in frames)
          byId.set(Std.int(f.FrID), Std.int(f.FrDl ?? 0));
        var sets:Array<Dynamic> = desc.FSts ?? [];
        var order:Array<Int> = [];
        if (sets.length > 0 && sets[0].FsFr != null)
        {
          for (id in (sets[0].FsFr : Array<Dynamic>))
            order.push(Std.int(id));
          doc.activeFrame = Std.int(sets[0].AFrm ?? 0);
        }
        else
          for (f in frames)
            order.push(Std.int(f.FrID));
        doc.frames = [for (id in order) {id: id, delay: byId.exists(id) ? byId.get(id) : 0}];
      }
      pos = start + l;
    }
  }

  function readLayerInfo(doc:PSDDocument, gray:Bool):Void
  {
    var count = s16();
    if (count < 0) count = -count;
    var records:Array<{layer:PSDLayer, channels:Array<{id:Int, len:Int}>, mask:Null<{top:Int, left:Int, bottom:Int, right:Int, color:Int, disabled:Bool}>}> = [];
    for (i in 0...count)
    {
      var lt = s32();
      var ll = s32();
      var lb = s32();
      var lr = s32();
      var layer:PSDLayer = {
        name: '',
        top: lt,
        left: ll,
        bottom: lb,
        right: lr,
        opacity: 255,
        blend: 'norm',
        clipping: false,
        hidden: false,
        section: 0,
        id: -1,
        argb: null,
        states: []
      };
      var nch = u16();
      var chans:Array<{id:Int, len:Int}> = [];
      for (c in 0...nch)
      {
        var cid = s16();
        var clen = u32();
        chans.push({id: cid, len: clen});
      }
      sig(); // 8BIM
      layer.blend = sig();
      layer.opacity = u8();
      layer.clipping = u8() != 0;
      var flags = u8();
      layer.hidden = (flags & 2) != 0;
      pos++;
      var extraLen = u32();
      var extraEnd = pos + extraLen;
      // Layer mask.
      var maskLen = u32();
      var maskStart = pos;
      var mask = null;
      if (maskLen >= 18)
      {
        var mt = s32(), ml = s32(), mb = s32(), mr = s32();
        var color = u8();
        var mflags = u8();
        mask = {
          top: mt,
          left: ml,
          bottom: mb,
          right: mr,
          color: color,
          disabled: (mflags & 2) != 0
        };
      }
      pos = maskStart + maskLen;
      // Blending ranges.
      var skipLen = u32();
      pos += skipLen;
      // Name (Pascal string, padded to 4).
      var nameLen = u8();
      layer.name = latin1(pos, nameLen);
      pos += nameLen;
      while ((nameLen + 1) % 4 != 0)
      {
        nameLen++;
        pos++;
      }
      // Additional info.
      while (pos + 12 <= extraEnd)
      {
        var s = sig();
        if (s != '8BIM' && s != '8B64')
        {
          // Some writers pad oddly: look for the next signature.
          pos -= 3;
          continue;
        }
        var key = sig();
        var len = u32();
        var start = pos;
        try
        {
          readLayerBlock(layer, key, start + len, doc);
        }
        catch (e:Dynamic) {}
        pos = start + len;
      }
      pos = extraEnd;
      records.push({layer: layer, channels: chans, mask: mask});
    }

    // Pixel data.
    for (r in records)
    {
      var l = r.layer;
      var w = l.right - l.left, h = l.bottom - l.top;
      var planes = new Map<Int, Bytes>();
      for (c in r.channels)
      {
        var start = pos;
        var cw = w, ch = h;
        if (c.id == -2 && r.mask != null)
        {
          cw = r.mask.right - r.mask.left;
          ch = r.mask.bottom - r.mask.top;
        }
        if (c.id >= -2 && cw > 0 && ch > 0 && c.len > 2)
        {
          try
          {
            planes.set(c.id, readChannel(cw, ch, start + c.len));
          }
          catch (e:Dynamic) {}
        }
        pos = start + c.len;
      }
      if (w > 0 && h > 0 && l.section == 0) l.argb = toArgb(planes, w, h, gray, r.mask, l);
      doc.layers.push(l);
    }
  }

  function latin1(at:Int, len:Int):String
  {
    var buf = new StringBuf();
    for (i in 0...len)
      buf.addChar(b.get(at + i));
    return buf.toString();
  }

  function readLayerBlock(layer:PSDLayer, key:String, end:Int, doc:PSDDocument):Void
  {
    switch (key)
    {
      case 'luni':
        var n = unicode();
        if (n != '') layer.name = n;
      case 'lsct' | 'lsdk':
        layer.section = u32();
        if (pos + 8 <= end)
        {
          if (sig() == '8BIM') layer.blend = sig();
        }
      case 'lyid':
        layer.id = u32();
      case 'shmd':
        var n = u32();
        for (i in 0...n)
        {
          sig();
          var k = sig();
          pos += 4; // copy flag + padding
          var len = u32();
          var start = pos;
          if (k == 'mlst')
          {
            u32();
            var desc:Dynamic = readDescriptor();
            var states:Array<Dynamic> = desc.LaSt ?? [];
            for (st in states)
            {
              var fr:Array<Int> = [for (f in (st.FrLs ?? [] : Array<Dynamic>)) Std.int(f)];
              var ofs:Dynamic = st.Ofst;
              layer.states.push({
                frames: fr,
                enab: st.enab,
                ox: ofs != null ? Std.int(ofs.Hrzn ?? 0) : 0,
                oy: ofs != null ? Std.int(ofs.Vrtc ?? 0) : 0
              });
            }
          }
          pos = start + len;
        }
      case 'vmsk' | 'vsms':
        u32(); // version
        u32(); // flags
        layer.path = readPathRecords(end, doc.width, doc.height);
      case 'SoCo':
        u32();
        var desc:Dynamic = readDescriptor();
        var c = colorOf(Reflect.field(desc, 'Clr '));
        if (c != null && layer.fill == null) layer.fill = c;
      case 'vscg':
        sig(); // fill type key
        u32();
        var desc:Dynamic = readDescriptor();
        var c = colorOf(Reflect.field(desc, 'Clr '));
        if (c != null) layer.fill = c;
      case 'vstk':
        u32();
        var desc:Dynamic = readDescriptor();
        if (desc.strokeEnabled == true)
        {
          var content:Dynamic = desc.strokeStyleContent;
          var c = content != null ? colorOf(Reflect.field(content, 'Clr ')) : null;
          if (c != null)
          {
            layer.stroke = c;
            var w:Dynamic = desc.strokeStyleLineWidth;
            layer.strokeWidth = w != null ? (w : Float) : 1;
          }
        }
        if (desc.fillEnabled == false) layer.fill = null;
      default:
    }
  }

  static function colorOf(c:Dynamic):Null<Int>
  {
    if (c == null) return null;
    var r:Null<Float> = Reflect.field(c, 'Rd  ');
    var g:Null<Float> = Reflect.field(c, 'Grn ');
    var bl:Null<Float> = Reflect.field(c, 'Bl  ');
    if (r == null || g == null || bl == null) return null;
    inline function ch(v:Float):Int
      return Std.int(Math.max(0, Math.min(255, Math.round(v))));
    return 0xFF000000 | (ch(r) << 16) | (ch(g) << 8) | ch(bl);
  }

  /**
   * Vector mask records -> path commands (cubic curves through the knots).
   */
  function readPathRecords(end:Int, w:Int, h:Int):Array<Float>
  {
    var out:Array<Float> = [];
    var knots:Array<Array<Float>> = [];
    var closed = false;
    var remaining = 0;
    function fixed():Float
    {
      var v = s32();
      return v / 16777216.0;
    }
    function flush()
    {
      if (knots.length == 0) return;
      // Each knot: [inX, inY, x, y, outX, outY].
      out.push(0);
      out.push(knots[0][2]);
      out.push(knots[0][3]);
      var n = knots.length;
      var last = closed ? n : n - 1;
      for (i in 0...last)
      {
        var a = knots[i], c = knots[(i + 1) % n];
        out.push(3);
        out.push(a[4]);
        out.push(a[5]);
        out.push(c[0]);
        out.push(c[1]);
        out.push(c[2]);
        out.push(c[3]);
      }
      if (closed) out.push(4);
      knots = [];
    }
    while (pos + 26 <= end)
    {
      var type = u16();
      var start = pos;
      switch (type)
      {
        case 0 | 3:
          flush();
          remaining = u16();
          closed = type == 0;
        case 1 | 2 | 4 | 5:
          var iy = fixed() * h, ix = fixed() * w;
          var ay = fixed() * h, ax = fixed() * w;
          var oy = fixed() * h, ox = fixed() * w;
          knots.push([ix, iy, ax, ay, ox, oy]);
        default:
      }
      pos = start + 24;
    }
    flush();
    return out;
  }

  function readChannel(w:Int, h:Int, end:Int):Bytes
  {
    var comp = u16();
    var out = Bytes.alloc(w * h);
    switch (comp)
    {
      case 0:
        out.blit(0, b, pos, Std.int(Math.min(w * h, end - pos)));
      case 1:
        var counts = [for (r in 0...h) u16()];
        var o = 0;
        for (r in 0...h)
        {
          var rowEnd = pos + counts[r];
          var rowStart = r * w;
          o = rowStart;
          while (pos < rowEnd && o < rowStart + w)
          {
            var n = b.get(pos++);
            if (n < 128)
            {
              var cnt = n + 1;
              for (k in 0...cnt)
                if (o < rowStart + w) out.set(o++, b.get(pos + k));
              pos += cnt;
            }
            else if (n > 128)
            {
              var cnt = 257 - n;
              var v = b.get(pos++);
              for (k in 0...cnt)
                if (o < rowStart + w) out.set(o++, v);
            }
          }
          pos = rowEnd;
        }
      case 2 | 3:
        var data = haxe.zip.InflateImpl.run(new BytesInput(b, pos, end - pos));
        out.blit(0, data, 0, Std.int(Math.min(w * h, data.length)));
        if (comp == 3)
        {
          for (r in 0...h)
            for (x in 1...w)
              out.set(r * w + x, (out.get(r * w + x) + out.get(r * w + x - 1)) & 0xFF);
        }
      default:
        throw 'Unknown compression $comp';
    }
    return out;
  }

  function toArgb(planes:Map<Int, Bytes>, w:Int, h:Int, gray:Bool, mask:Null<{top:Int, left:Int, bottom:Int, right:Int, color:Int, disabled:Bool}>,
      l:PSDLayer):Bytes
  {
    var out = Bytes.alloc(w * h * 4);
    var rr = planes.get(0);
    var gg = gray ? rr : planes.get(1);
    var bb = gray ? rr : planes.get(2);
    var aa = planes.get(-1);
    var mm = mask != null && !mask.disabled ? planes.get(-2) : null;
    var mw = mask != null ? mask.right - mask.left : 0;
    var mh = mask != null ? mask.bottom - mask.top : 0;
    for (y in 0...h)
    {
      for (x in 0...w)
      {
        var i = y * w + x;
        var a = aa != null ? aa.get(i) : 255;
        if (mask != null && !mask.disabled)
        {
          var mx = x + l.left - mask.left, my = y + l.top - mask.top;
          var mv = (mm != null && mx >= 0 && my >= 0 && mx < mw && my < mh) ? mm.get(my * mw + mx) : mask.color;
          a = Std.int(a * mv / 255);
        }
        var o = i * 4;
        out.set(o, a);
        out.set(o + 1, rr != null ? rr.get(i) : 0);
        out.set(o + 2, gg != null ? gg.get(i) : 0);
        out.set(o + 3, bb != null ? bb.get(i) : 0);
      }
    }
    return out;
  }

  function readComposite(w:Int, h:Int, channels:Int, gray:Bool):Null<Bytes>
  {
    var comp = u16();
    var planes:Array<Bytes> = [];
    var n = Std.int(Math.min(channels, gray ? 2 : 4));
    if (comp == 1)
    {
      var counts = [for (i in 0...channels * h) u16()];
      for (c in 0...channels)
      {
        var plane = Bytes.alloc(w * h);
        for (r in 0...h)
        {
          var rowEnd = pos + counts[c * h + r];
          var o = r * w;
          var rowLimit = o + w;
          while (pos < rowEnd)
          {
            var k = b.get(pos++);
            if (k < 128)
            {
              for (j in 0...k + 1)
                if (o < rowLimit) plane.set(o++, b.get(pos + j));
              pos += k + 1;
            }
            else if (k > 128)
            {
              var v = b.get(pos++);
              for (j in 0...257 - k)
                if (o < rowLimit) plane.set(o++, v);
            }
          }
          pos = rowEnd;
        }
        if (c < n) planes.push(plane);
      }
    }
    else if (comp == 0)
    {
      for (c in 0...channels)
      {
        if (pos + w * h > b.length) break;
        if (c < n) planes.push(b.sub(pos, w * h));
        pos += w * h;
      }
    }
    else
      return null;
    if (planes.length == 0) return null;
    var out = Bytes.alloc(w * h * 4);
    for (i in 0...w * h)
    {
      var o = i * 4;
      if (gray)
      {
        out.set(o, planes.length > 1 ? planes[1].get(i) : 255);
        out.set(o + 1, planes[0].get(i));
        out.set(o + 2, planes[0].get(i));
        out.set(o + 3, planes[0].get(i));
      }
      else
      {
        out.set(o, planes.length > 3 ? planes[3].get(i) : 255);
        out.set(o + 1, planes[0].get(i));
        out.set(o + 2, planes.length > 1 ? planes[1].get(i) : 0);
        out.set(o + 3, planes.length > 2 ? planes[2].get(i) : 0);
      }
    }
    return out;
  }

  //
  // Descriptors (Photoshop's typed key/value data)
  //

  function key():String
  {
    var n = u32();
    if (n == 0) n = 4;
    var s = latin1(pos, n);
    pos += n;
    return s;
  }

  function readDescriptor():Dynamic
  {
    unicode(); // name
    var cls = key();
    var n = u32();
    var out:Dynamic = {};
    Reflect.setField(out, '_class', cls);
    for (i in 0...n)
    {
      var k = key();
      var t = sig();
      Reflect.setField(out, k, readValue(t));
    }
    return out;
  }

  function readValue(t:String):Dynamic
  {
    return switch (t)
    {
      case 'long': s32();
      case 'doub': f64();
      case 'bool': u8() != 0;
      case 'TEXT': unicode();
      case 'enum':
        key();
        key();
      case 'Objc' | 'GlbO': readDescriptor();
      case 'VlLs':
        var n = u32();
        [for (i in 0...n) readValue(sig())];
      case 'UntF':
        sig();
        f64();
      case 'UnFl':
        sig();
        var n = u32();
        [for (i in 0...n) f64()];
      case 'tdta' | 'alis':
        var n = u32();
        pos += n;
        null;
      case 'type' | 'GlbC':
        unicode();
        key();
      case 'comp':
        pos += 8;
        null;
      case 'obj ':
        var n = u32();
        for (i in 0...n)
        {
          var rt = sig();
          switch (rt)
          {
            case 'prop':
              unicode();
              key();
              key();
            case 'Clss':
              unicode();
              key();
            case 'Enmr':
              unicode();
              key();
              key();
              key();
            case 'rele':
              unicode();
              key();
              u32();
            case 'Idnt' | 'indx':
              u32();
            case 'name':
              unicode();
              key();
              unicode();
            default:
          }
        }
        null;
      case 'Pth ':
        var n = u32();
        pos += n;
        null;
      default:
        throw 'Unknown descriptor type $t';
    }
  }

  //
  // Tree
  //

  static function buildTree(layers:Array<PSDLayer>):Array<PSDNode>
  {
    var stack:Array<Array<PSDNode>> = [[]];
    for (l in layers)
    {
      if (l.section == 3) stack.push([]);
      else if (l.section == 1 || l.section == 2)
      {
        var children = stack.length > 1 ? stack.pop() : [];
        stack[stack.length - 1].push({layer: l, children: children});
      }
      else
        stack[stack.length - 1].push({layer: l, children: null});
    }
    // Unclosed groups: keep their layers.
    while (stack.length > 1)
    {
      var c = stack.pop();
      for (n in c)
        stack[stack.length - 1].push(n);
    }
    return stack[0];
  }

  /**
   * Clipping masks: a clipped layer only shows where the layer under it has pixels.
   */
  static function applyClipping(nodes:Array<PSDNode>):Void
  {
    var base:Null<PSDLayer> = null;
    for (n in nodes)
    {
      if (n.children != null)
      {
        applyClipping(n.children);
        base = null;
        continue;
      }
      var l = n.layer;
      if (!l.clipping)
      {
        base = l;
        continue;
      }
      if (l.argb == null) continue;
      var w = l.right - l.left, h = l.bottom - l.top;
      var bw = base != null ? base.right - base.left : 0;
      for (y in 0...h)
      {
        for (x in 0...w)
        {
          var o = (y * w + x) * 4;
          var ba = 0;
          if (base != null && base.argb != null)
          {
            var bx = x + l.left - base.left, by = y + l.top - base.top;
            if (bx >= 0 && by >= 0 && bx < bw && by < base.bottom - base.top) ba = base.argb.get((by * bw + bx) * 4);
          }
          l.argb.set(o, Std.int(l.argb.get(o) * ba / 255));
        }
      }
    }
  }

  //
  // Writing
  //

  /**
   * Write a PSD. `frames` (optional) turns on Photoshop frame animation: each frame shows the layers whose
   * `visibleFrames` include it, for `delay` hundredths of a second.
   */
  public static function write(width:Int, height:Int, layers:Array<PSDWriteLayer>, composite:Bytes, ?frameCount:Int = 0, ?delay:Int = 4):Bytes
  {
    var o = out();
    o.writeString('8BPS');
    o.writeUInt16(1);
    for (i in 0...6)
      o.writeByte(0);
    o.writeUInt16(3);
    o.writeInt32(height);
    o.writeInt32(width);
    o.writeUInt16(8);
    o.writeUInt16(3);
    o.writeInt32(0); // color mode data

    // Image resources.
    var res = out();
    // Resolution: 72 dpi.
    var ri = out();
    ri.writeInt32(72 << 16);
    ri.writeUInt16(1);
    ri.writeUInt16(1);
    ri.writeInt32(72 << 16);
    ri.writeUInt16(1);
    ri.writeUInt16(1);
    resource(res, 1005, ri.getBytes());
    var frameIds = [for (i in 0...frameCount) 1000 + i];
    if (frameCount > 0) resource(res, 4000, animationResource(frameIds, delay));
    section(o, res.getBytes(), 1);

    // Layers.
    var flat:Array<{layer:PSDWriteLayer, section:Int}> = [];
    function flatten(list:Array<PSDWriteLayer>)
    {
      // `list` is top first (like a layers panel); the file stores bottom first.
      var i = list.length - 1;
      while (i >= 0)
      {
        var l = list[i--];
        if (l.children != null)
        {
          flat.push({layer: {name: '</Layer group>', hidden: false}, section: 3});
          flatten(l.children);
          flat.push({layer: l, section: 1});
        }
        else
          flat.push({layer: l, section: 0});
      }
    }
    flatten(layers);

    var li = out();
    li.writeInt16(flat.length);
    var channelData = out();
    var nextId = 2;
    for (entry in flat)
    {
      var l = entry.layer;
      var isGroupRec = entry.section != 0;
      var w = isGroupRec ? 0 : (l.width ?? 0);
      var h = isGroupRec ? 0 : (l.height ?? 0);
      var left = isGroupRec ? 0 : (l.left ?? 0);
      var top = isGroupRec ? 0 : (l.top ?? 0);
      var chans = [-1, 0, 1, 2];
      var encoded:Array<Bytes> = [];
      for (c in chans)
        encoded.push(w > 0 && h > 0 && l.argb != null ? encodeChannel(l.argb, w, h, c == -1 ? 0 : c + 1) : emptyChannel());
      li.writeInt32(top);
      li.writeInt32(left);
      li.writeInt32(top + h);
      li.writeInt32(left + w);
      li.writeUInt16(chans.length);
      for (i in 0...chans.length)
      {
        li.writeInt16(chans[i]);
        li.writeInt32(encoded[i].length);
      }
      li.writeString('8BIM');
      li.writeString(isGroupRec ? 'norm' : padKey(l.blend ?? 'norm'));
      li.writeByte(l.opacity ?? 255);
      li.writeByte(0);
      var flags = 8 | (l.hidden == true ? 2 : 0) | (isGroupRec ? 16 : 0);
      li.writeByte(flags);
      li.writeByte(0);

      var extra = out();
      extra.writeInt32(0); // no layer mask
      extra.writeInt32(40); // blending ranges
      for (i in 0...10)
      {
        extra.writeByte(0);
        extra.writeByte(0);
        extra.writeByte(255);
        extra.writeByte(255);
      }
      pascalName(extra, l.name);
      block(extra, 'luni', unicodeBytes(l.name));
      var id = nextId++;
      var idb = out();
      idb.writeInt32(id);
      block(extra, 'lyid', idb.getBytes());
      if (isGroupRec)
      {
        var sb = out();
        sb.writeInt32(entry.section);
        if (entry.section == 1)
        {
          sb.writeString('8BIM');
          sb.writeString(padKey(l.blend ?? 'pass'));
        }
        block(extra, 'lsct', sb.getBytes());
      }
      if (frameCount > 0) block(extra, 'shmd', frameStates(id, l.visibleFrames, frameIds));
      section(li, extra.getBytes(), 1);
      for (e in encoded)
        channelData.write(e);
    }
    li.write(channelData.getBytes());
    var liBytes = li.getBytes();
    var lm = out();
    lm.writeInt32(liBytes.length + (liBytes.length % 2));
    lm.write(liBytes);
    if (liBytes.length % 2 == 1) lm.writeByte(0);
    lm.writeInt32(0); // global layer mask
    section(o, lm.getBytes(), 1);

    // Flattened image (RLE, RGB).
    o.writeUInt16(1);
    var rows = out();
    var data = out();
    for (c in 1...4)
    {
      for (r in 0...height)
      {
        var row = Bytes.alloc(width);
        for (x in 0...width)
          row.set(x, composite.get((r * width + x) * 4 + c));
        var packed = packBits(row);
        rows.writeUInt16(packed.length);
        data.write(packed);
      }
    }
    o.write(rows.getBytes());
    o.write(data.getBytes());
    return o.getBytes();
  }

  static function out():BytesOutput
  {
    var o = new BytesOutput();
    o.bigEndian = true;
    return o;
  }

  static function padKey(k:String):String
    return (k + '    ').substr(0, 4);

  static function section(o:BytesOutput, data:Bytes, pad:Int):Void
  {
    var len = data.length;
    while (len % pad != 0)
      len++;
    o.writeInt32(len);
    o.write(data);
    for (i in data.length...len)
      o.writeByte(0);
  }

  static function resource(o:BytesOutput, id:Int, data:Bytes):Void
  {
    o.writeString('8BIM');
    o.writeUInt16(id);
    o.writeUInt16(0); // empty name, padded
    o.writeInt32(data.length);
    o.write(data);
    if (data.length % 2 == 1) o.writeByte(0);
  }

  static function block(o:BytesOutput, key:String, data:Bytes):Void
  {
    o.writeString('8BIM');
    o.writeString(key);
    section(o, data, 4);
  }

  static function pascalName(o:BytesOutput, name:String):Void
  {
    var ascii = new StringBuf();
    for (i in 0...name.length)
    {
      var c = name.charCodeAt(i);
      ascii.addChar(c != null && c >= 32 && c < 127 ? c : '?'.code);
    }
    var s = ascii.toString();
    if (s.length > 255) s = s.substr(0, 255);
    o.writeByte(s.length);
    o.writeString(s);
    var total = s.length + 1;
    while (total % 4 != 0)
    {
      o.writeByte(0);
      total++;
    }
  }

  static function unicodeBytes(s:String):Bytes
  {
    // Layer names (luni) count characters without a terminator, like Photoshop writes them.
    var o = out();
    o.writeInt32(s.length);
    for (i in 0...s.length)
      o.writeUInt16(StringTools.fastCodeAt(s, i));
    return o.getBytes();
  }

  static function emptyChannel():Bytes
  {
    var b = Bytes.alloc(2);
    b.set(0, 0);
    b.set(1, 0);
    return b;
  }

  /**
   * One channel of ARGB pixels (byte `offset` in each pixel), RLE compressed.
   */
  static function encodeChannel(argb:Bytes, w:Int, h:Int, offset:Int):Bytes
  {
    var o = out();
    o.writeUInt16(1);
    var counts = out();
    var data = out();
    var row = Bytes.alloc(w);
    for (r in 0...h)
    {
      for (x in 0...w)
        row.set(x, argb.get((r * w + x) * 4 + offset));
      var packed = packBits(row);
      counts.writeUInt16(packed.length);
      data.write(packed);
    }
    o.write(counts.getBytes());
    o.write(data.getBytes());
    return o.getBytes();
  }

  public static function packBits(row:Bytes):Bytes
  {
    var o = new BytesBuffer();
    var n = row.length;
    var i = 0;
    while (i < n)
    {
      // A run of 3+ equal bytes?
      var j = i;
      while (j + 1 < n && row.get(j + 1) == row.get(i) && j - i < 127)
        j++;
      var run = j - i + 1;
      if (run >= 3)
      {
        o.addByte(257 - run);
        o.addByte(row.get(i));
        i = j + 1;
        continue;
      }
      // Literal bytes until the next run of 3.
      var start = i;
      while (i < n && i - start < 128)
      {
        if (i + 2 < n && row.get(i) == row.get(i + 1) && row.get(i) == row.get(i + 2)) break;
        i++;
      }
      o.addByte(i - start - 1);
      for (k in start...i)
        o.addByte(row.get(k));
    }
    return o.getBytes();
  }

  //
  // Frame animation data
  //

  static function animationResource(ids:Array<Int>, delay:Int):Bytes
  {
    var desc = out();
    desc.writeInt32(16);
    var frames:Array<DescValue> = [];
    for (i in 0...ids.length)
    {
      var items:Array<DescItem> = [
        {key: 'FrID', value: DLong(ids[i])},
        {key: 'FrDl', value: DLong(delay)},
        {key: 'FrDs', value: DEnum('FrmD', 'None')}
      ];
      if (i == 0) items.push({key: 'FrGA', value: DDouble(30)});
      frames.push(DObj('null', items));
    }
    writeDescriptor(desc, 'null', [
      {key: 'AFSt', value: DLong(0)},
      {key: 'FrIn', value: DList(frames)},
      {
        key: 'FSts',
        value: DList([
          DObj('null', [
            {key: 'FsID', value: DLong(0)},
            {key: 'AFrm', value: DLong(0)},
            {key: 'FsFr', value: DList([for (id in ids) DLong(id)])},
            {key: 'LCnt', value: DLong(0)}
          ])
        ])
      }
    ]);
    var blocks = out();
    blocks.writeString('8BIM');
    blocks.writeString('AnDs');
    section(blocks, desc.getBytes(), 1);
    blocks.writeString('8BIM');
    blocks.writeString('Roll');
    blocks.writeInt32(8);
    blocks.writeInt32(0);
    blocks.writeInt32(0);
    var r = out();
    r.writeString('mani');
    r.writeString('IRFR');
    section(r, blocks.getBytes(), 1);
    return r.getBytes();
  }

  static function frameStates(layerId:Int, visible:Null<Array<Int>>, ids:Array<Int>):Bytes
  {
    var on:Array<DescValue> = [];
    var off:Array<DescValue> = [];
    for (i in 0...ids.length)
    {
      if (visible == null || visible.contains(i)) on.push(DLong(ids[i]));
      else
        off.push(DLong(ids[i]));
    }
    var states:Array<DescValue> = [];
    if (on.length > 0) states.push(DObj('null', [{key: 'enab', value: DBool(true)}, {key: 'FrLs', value: DList(on)}]));
    if (off.length > 0) states.push(DObj('null', [{key: 'enab', value: DBool(false)}, {key: 'FrLs', value: DList(off)}]));
    var desc = out();
    desc.writeInt32(16);
    writeDescriptor(desc, 'null', [{key: 'LaID', value: DLong(layerId)}, {key: 'LaSt', value: DList(states)}]);
    var o = out();
    o.writeInt32(1);
    o.writeString('8BIM');
    o.writeString('mlst');
    o.writeInt32(0); // copy flag + padding
    section(o, desc.getBytes(), 4);
    return o.getBytes();
  }

  static function writeKey(o:BytesOutput, k:String):Void
  {
    if (k.length == 4) o.writeInt32(0);
    else
      o.writeInt32(k.length);
    o.writeString(k);
  }

  static function writeDescriptor(o:BytesOutput, cls:String, items:Array<DescItem>):Void
  {
    o.writeInt32(1);
    o.writeUInt16(0); // empty name
    writeKey(o, cls);
    o.writeInt32(items.length);
    for (it in items)
    {
      writeKey(o, it.key);
      writeValue(o, it.value);
    }
  }

  static function writeValue(o:BytesOutput, v:DescValue):Void
  {
    switch (v)
    {
      case DLong(n):
        o.writeString('long');
        o.writeInt32(n);
      case DDouble(f):
        o.writeString('doub');
        o.writeDouble(f);
      case DBool(x):
        o.writeString('bool');
        o.writeByte(x ? 1 : 0);
      case DEnum(t, e):
        o.writeString('enum');
        writeKey(o, t);
        writeKey(o, e);
      case DObj(cls, items):
        o.writeString('Objc');
        writeDescriptor(o, cls, items);
      case DList(list):
        o.writeString('VlLs');
        o.writeInt32(list.length);
        for (x in list)
          writeValue(o, x);
    }
  }
}

enum DescValue
{
  DLong(v:Int);
  DDouble(v:Float);
  DBool(v:Bool);
  DEnum(type:String, value:String);
  DObj(cls:String, items:Array<DescItem>);
  DList(items:Array<DescValue>);
}

typedef DescItem =
{
  var key:String;
  var value:DescValue;
}
