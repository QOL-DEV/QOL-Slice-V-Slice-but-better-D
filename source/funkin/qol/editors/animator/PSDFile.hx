package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import funkin.qol.editors.animator.AnimData;
import funkin.qol.editors.animator.PSDCodec;
import haxe.io.Bytes;
import openfl.display.BitmapData;
import openfl.geom.Matrix;

private typedef LeafUse =
{
  var leaf:PSDLayer;
  var key:String;
  var ox:Int;
  var oy:Int;
  var alpha:Float;
  var hidden:Bool;
}

private typedef Span =
{
  var duration:Int;

  /**
   * Top first.
   */
  var uses:Array<LeafUse>;
}

private typedef Track =
{
  var key:String;
  var name:String;
  var uses:Array<Null<LeafUse>>;
}

/**
 * Photoshop files in and out of the Animator.
 *
 * Import:
 * - Photoshop frame animations (Timeline > Frame Animation, also what ToonSquid's "Frame Timeline" PSDs use): every
 *   frame keeps its timing; layers that are shown one frame at a time (like ToonSquid's frame groups) turn into
 *   keyframes on shared layers.
 * - PSDs with a group per frame: each top-level group can become one frame.
 * - Several PSDs at once (or a ZIP of them, like ToonSquid's "PSD Sequence"): one file per frame.
 * - Shape layers become vector shapes; everything else becomes paintable bitmap layers (masks and clipping applied).
 *
 * Export: an animated PSD with one group per frame plus frame animation data (Photoshop and ToonSquid play it), or a
 * layered PSD of a single frame (ibisPaint, Krita, GIMP...).
 */
class PSDFile
{
  public static inline final MODE_TIMELINE:String = 'timeline';
  public static inline final MODE_GROUPS:String = 'groups';
  public static inline final MODE_LAYERS:String = 'layers';
  public static inline final MODE_FILES:String = 'files';

  //
  // Import
  //

  /**
   * Top-level groups (when there are several, each could be a frame).
   */
  public static function topGroups(psd:PSDDocument):Int
  {
    var n = 0;
    for (node in psd.root)
      if (node.children != null) n++;
    return n;
  }

  public static function suggestedMode(psds:Array<PSDDocument>):String
  {
    if (psds.length > 1) return MODE_FILES;
    if (psds[0].frames.length > 1) return MODE_TIMELINE;
    return MODE_LAYERS;
  }

  public static function read(bytes:Bytes, name:String, fps:Float):AnimDoc
  {
    var psd = PSDCodec.read(bytes);
    return toDoc([psd], name, fps, suggestedMode([psd]));
  }

  public static function toDoc(psds:Array<PSDDocument>, name:String, fps:Float, mode:String):AnimDoc
  {
    var width = 1, height = 1;
    for (p in psds)
    {
      if (p.width > width) width = p.width;
      if (p.height > height) height = p.height;
    }
    var spans:Array<Span> = [];
    var psd = psds[0];
    switch (mode)
    {
      case MODE_TIMELINE:
        var delays = [for (f in psd.frames) f.delay];
        var base = 0;
        for (d in delays)
          if (d > 0 && (base == 0 || d < base)) base = d;
        if (base > 0) fps = Math.max(1, Math.min(60, Math.round(100 / base)));
        var activeId = psd.frames[Std.int(Math.min(psd.activeFrame, psd.frames.length - 1))].id;
        var varying = varyingTopGroups(psd, activeId);
        for (f in psd.frames)
        {
          var uses:Array<LeafUse> = [];
          collect(psd.root, [], 1, 0, 0, f.id, activeId, null, varying, uses, false);
          spans.push({duration: base > 0 && f.delay > 0 ? Std.int(Math.max(1, Math.round(f.delay / base))) : 1, uses: uses});
        }
      case MODE_GROUPS:
        var groups = [for (n in psd.root) if (n.children != null) n];
        if (Lambda.foreach(groups, g -> ~/[0-9]/.match(g.layer.name)))
          groups.sort((a, b) -> naturalCompare(a.layer.name, b.layer.name));
        var statics:Array<LeafUse> = [];
        var others = [for (n in psd.root) if (n.children == null) n];
        collect(others, [], 1, 0, 0, -1, -1, 'G', null, statics, false);
        for (g in groups)
        {
          var uses:Array<LeafUse> = [];
          collect(g.children, [], g.layer.opacity / 255, 0, 0, -1, -1, 'G', null, uses, false);
          // Layers outside the groups show on every frame.
          var all = uses.concat(statics);
          spans.push({duration: 1, uses: all});
        }
      case MODE_FILES:
        for (p in psds)
        {
          var uses:Array<LeafUse> = [];
          collect(p.root, [], 1, 0, 0, -1, -1, 'G', null, uses, false);
          spans.push({duration: 1, uses: uses});
        }
      default:
        var uses:Array<LeafUse> = [];
        collect(psd.root, [], 1, 0, 0, -1, -1, null, null, uses, true);
        spans.push({duration: 1, uses: uses});
    }

    var project = AnimData.newProject(name, width, height, fps);
    var doc = new AnimDoc(project);
    var tracks = buildTracks(spans, mode == MODE_LAYERS);
    var layers:Array<AnimLayer> = [];
    var bitmapIds = new Map<PSDLayer, String>();
    for (ti in 0...tracks.length)
    {
      var t = tracks[ti];
      var first:Null<LeafUse> = null;
      var allShapes = true;
      for (u in t.uses)
      {
        if (u == null) continue;
        if (first == null) first = u;
        if (u.leaf.path == null || (u.leaf.fill == null && u.leaf.stroke == null)) allShapes = false;
      }
      if (first == null) continue;
      var layer = AnimData.newLayer(t.name, allShapes ? 'vector' : 'bitmap', ti);
      layer.alpha = Math.round(first.alpha * 100) / 100;
      var blend = blendFromPsd(first.leaf.blend);
      if (blend != null) layer.blend = blend;
      if (first.hidden) layer.visible = false;
      layer.frames = [];
      var t0 = 0;
      for (si in 0...spans.length)
      {
        var u = t.uses[si];
        var d = spans[si].duration;
        var prev = layer.frames.length > 0 ? layer.frames[layer.frames.length - 1] : null;
        var prevUse = si > 0 ? t.uses[si - 1] : null;
        if (prev != null && sameUse(prevUse, u))
        {
          prev.duration += d;
        }
        else
        {
          var k:AnimKeyframe = {start: t0, duration: d, elements: []};
          if (u != null)
          {
            if (allShapes)
            {
              var el = AnimData.identity('shape');
              el.tx = u.ox;
              el.ty = u.oy;
              var p:AnimPath = {d: u.leaf.path};
              if (u.leaf.fill != null) p.fill = u.leaf.fill;
              if (u.leaf.stroke != null)
              {
                p.stroke = u.leaf.stroke;
                p.width = u.leaf.strokeWidth ?? 1;
              }
              el.paths = [p];
              k.elements.push(el);
            }
            else if (u.leaf.argb != null)
            {
              var id = bitmapIds.get(u.leaf);
              if (id == null)
              {
                var w = u.leaf.right - u.leaf.left, h = u.leaf.bottom - u.leaf.top;
                id = doc.addBitmap(AnimIO.fromARGB(u.leaf.argb, w, h), 'canvas', false);
                bitmapIds.set(u.leaf, id);
              }
              k.bitmap = id;
              k.bx = u.leaf.left + u.ox;
              k.by = u.leaf.top + u.oy;
            }
          }
          layer.frames.push(k);
        }
        t0 += d;
      }
      layers.push(layer);
    }
    if (layers.length == 0 && psd.composite != null)
    {
      // No layers: use the flattened image.
      var layer = AnimData.newLayer(name, 'bitmap', 0);
      layer.frames[0].bitmap = doc.addBitmap(AnimIO.fromARGB(psd.composite, psd.width, psd.height), 'canvas', false);
      layers.push(layer);
    }
    if (layers.length == 0) layers.push(AnimData.newLayer('Layer 1', 'vector', 0));
    project.symbols[0].layers = layers;
    doc.clearHistory();
    return doc;
  }

  static function sameUse(a:Null<LeafUse>, b:Null<LeafUse>):Bool
  {
    if (a == null || b == null) return a == b;
    return a.leaf == b.leaf && a.ox == b.ox && a.oy == b.oy;
  }

  /**
   * Top-level groups that are shown in some frames but not others (ToonSquid/Photoshop frame groups).
   */
  static function varyingTopGroups(psd:PSDDocument, activeId:Int):Map<PSDNode, Bool>
  {
    var out = new Map<PSDNode, Bool>();
    for (n in psd.root)
    {
      if (n.children == null) continue;
      var shown = false, hidden = false;
      for (f in psd.frames)
      {
        if (stateAt(n.layer, f.id, activeId).visible) shown = true;
        else
          hidden = true;
      }
      if (shown && hidden) out.set(n, true);
    }
    return out;
  }

  static function stateAt(l:PSDLayer, frameId:Int, activeId:Int):{visible:Bool, ox:Int, oy:Int}
  {
    var base = !l.hidden;
    if (frameId < 0 || l.states.length == 0) return {visible: base, ox: 0, oy: 0};
    var st:Null<PSDFrameState> = null;
    var activeSt:Null<PSDFrameState> = null;
    for (s in l.states)
    {
      if (s.frames.contains(frameId)) st = s;
      if (s.frames.contains(activeId)) activeSt = s;
    }
    var ax = activeSt != null ? activeSt.ox : 0, ay = activeSt != null ? activeSt.oy : 0;
    if (st == null) return {visible: base, ox: 0, oy: 0};
    var vis = st.enab != null ? st.enab : (st.frames.contains(activeId) ? base : true);
    return {visible: vis, ox: st.ox - ax, oy: st.oy - ay};
  }

  /**
   * The visible leaf layers (top first) at a frame. `trackPrefix` names layers inside a frame group by their path in
   * the group, so the same layer in every frame group lands on the same Animator layer.
   */
  static function collect(nodes:Array<PSDNode>, path:Array<String>, alpha:Float, ox:Int, oy:Int, frameId:Int, activeId:Int, groupKey:Null<String>,
      varying:Null<Map<PSDNode, Bool>>, out:Array<LeafUse>, includeHidden:Bool, parentHidden:Bool = false):Void
  {
    var i = nodes.length - 1;
    while (i >= 0)
    {
      var n = nodes[i--];
      var st = stateAt(n.layer, frameId, activeId);
      if (!st.visible && !includeHidden) continue;
      var a = alpha * n.layer.opacity / 255;
      if (n.children != null)
      {
        var key = groupKey;
        if (key == null && varying != null && varying.exists(n)) key = 'G';
        collect(n.children, key == 'G' && groupKey == null ? [] : path.concat([n.layer.name]), a, ox + st.ox, oy + st.oy, frameId, activeId, key, varying,
          out, includeHidden, parentHidden || !st.visible);
        continue;
      }
      if (n.layer.argb == null && n.layer.path == null) continue;
      var key = groupKey != null ? 'G:' + path.concat([n.layer.name]).join('/') : 'L:' + n.layer.id + ':' + n.layer.name + ':' + n.layer.left + ','
        + n.layer.top;
      out.push({
        leaf: n.layer,
        key: key,
        ox: ox + st.ox,
        oy: oy + st.oy,
        alpha: a,
        hidden: parentHidden || !st.visible
      });
    }
  }

  static function buildTracks(spans:Array<Span>, unique:Bool):Array<Track>
  {
    var order:Array<String> = [];
    var byKey = new Map<String, Track>();
    for (si in 0...spans.length)
    {
      var counts = new Map<String, Int>();
      var prev:Null<String> = null;
      for (u in spans[si].uses)
      {
        // The same name twice in one frame: number them.
        var base = unique ? u.key + '#' + spans[si].uses.indexOf(u) : u.key;
        var c = counts.exists(base) ? counts.get(base) + 1 : 1;
        counts.set(base, c);
        var key = c > 1 ? base + '#' + c : base;
        var t = byKey.get(key);
        if (t == null)
        {
          t = {key: key, name: u.leaf.name, uses: [for (i in 0...spans.length) null]};
          byKey.set(key, t);
          var at = prev == null ? 0 : order.indexOf(prev) + 1;
          order.insert(at, key);
        }
        t.uses[si] = u;
        prev = key;
      }
    }
    return [for (k in order) byKey.get(k)];
  }

  static function naturalCompare(a:String, b:String):Int
  {
    var ra = ~/([0-9]+)/;
    var na = ra.match(a) ? Std.parseInt(ra.matched(1)) : 0;
    var rb = ~/([0-9]+)/;
    var nb = rb.match(b) ? Std.parseInt(rb.matched(1)) : 0;
    if (na != nb) return na - nb;
    return a < b ? -1 : (a > b ? 1 : 0);
  }

  public static function blendFromPsd(key:String):Null<String>
  {
    return switch (key)
    {
      case 'mul ': 'multiply';
      case 'scrn': 'screen';
      case 'lddg': 'add';
      case 'lite': 'lighten';
      case 'dark': 'darken';
      case 'diff': 'difference';
      case 'fsub': 'subtract';
      case 'over': 'overlay';
      case 'hLit': 'hardlight';
      default: null;
    }
  }

  public static function blendToPsd(name:Null<String>):String
  {
    return switch (name)
    {
      case 'multiply': 'mul ';
      case 'screen': 'scrn';
      case 'add': 'lddg';
      case 'lighten': 'lite';
      case 'darken': 'dark';
      case 'difference': 'diff';
      case 'subtract': 'fsub';
      case 'overlay': 'over';
      case 'hardlight': 'hLit';
      default: 'norm';
    }
  }

  //
  // Export
  //

  /**
   * One layer drawn alone at a frame (full opacity, normal blend: those go in the PSD layer's own settings).
   */
  static function renderLayer(doc:AnimDoc, sym:AnimSymbol, layerIndex:Int, frame:Int):BitmapData
  {
    var w = doc.project.width, h = doc.project.height;
    var layer = sym.layers[layerIndex];
    var copy:AnimLayer = Reflect.copy(layer);
    copy.alpha = 1;
    copy.blend = null;
    copy.visible = true;
    copy.guide = false;
    var temp:AnimSymbol = {
      id: sym.id,
      name: sym.name,
      kind: sym.kind,
      layers: [copy]
    };
    var bmp = new BitmapData(w, h, true, 0);
    var r = new AnimRender(doc);
    var spr = r.render(temp, frame, {forExport: true, camera: sym == doc.main ? r.cameraMatrix(sym, frame) : null});
    var m = new Matrix();
    if (sym != doc.main) m.translate(w / 2, h / 2);
    bmp.draw(spr, m, null, null, null, true);
    return bmp;
  }

  /**
   * The whole frame, flattened over the stage color (or white).
   */
  static function renderComposite(doc:AnimDoc, sym:AnimSymbol, frame:Int):Bytes
  {
    var w = doc.project.width, h = doc.project.height;
    var bg = (doc.project.bg >>> 24) == 0 ? 0xFFFFFFFF : (doc.project.bg | 0xFF000000);
    var bmp = new BitmapData(w, h, true, bg);
    var spr = new AnimRender(doc).render(sym, frame, {forExport: true});
    var m = new Matrix();
    if (sym != doc.main) m.translate(w / 2, h / 2);
    bmp.draw(spr, m, null, null, null, true);
    var bytes = AnimIO.argbBytes(bmp);
    bmp.dispose();
    return bytes;
  }

  static function exportLayers(sym:AnimSymbol):Array<Int>
    return [for (i in 0...sym.layers.length) if (sym.layers[i].guide != true && sym.layers[i].kind != 'audio' && sym.layers[i].kind != 'camera') i];

  static function layerAt(doc:AnimDoc, sym:AnimSymbol, li:Int, frame:Int):{layer:PSDWriteLayer, hash:String}
  {
    var src = sym.layers[li];
    var bmp = renderLayer(doc, sym, li, frame);
    var r = AnimPaint.opaqueBounds(bmp);
    var out:PSDWriteLayer = {
      name: src.name,
      opacity: Std.int(Math.round(src.alpha * 255)),
      blend: blendToPsd(src.blend),
      hidden: !src.visible
    };
    var hash = 'empty';
    if (r != null)
    {
      out.left = Std.int(r.x);
      out.top = Std.int(r.y);
      out.width = Std.int(r.width);
      out.height = Std.int(r.height);
      out.argb = AnimIO.argbBytes(bmp, r);
      hash = haxe.crypto.Md5.make(out.argb).toHex() + '@${out.left},${out.top},${out.width}x${out.height}';
    }
    bmp.dispose();
    return {layer: out, hash: hash};
  }

  static function background(doc:AnimDoc):Null<PSDWriteLayer>
  {
    if ((doc.project.bg >>> 24) == 0) return null;
    var w = doc.project.width, h = doc.project.height;
    var c = doc.project.bg | 0xFF000000;
    var px = Bytes.alloc(w * h * 4);
    for (i in 0...w * h)
    {
      px.set(i * 4, 255);
      px.set(i * 4 + 1, (c >> 16) & 0xFF);
      px.set(i * 4 + 2, (c >> 8) & 0xFF);
      px.set(i * 4 + 3, c & 0xFF);
    }
    return {
      name: 'Background',
      left: 0,
      top: 0,
      width: w,
      height: h,
      argb: px
    };
  }

  /**
   * A layered PSD of one frame.
   */
  public static function writeFrame(doc:AnimDoc, sym:AnimSymbol, frame:Int):Bytes
  {
    var layers:Array<PSDWriteLayer> = [for (li in exportLayers(sym)) layerAt(doc, sym, li, frame).layer];
    var bg = background(doc);
    if (bg != null) layers.push(bg);
    return PSDCodec.write(doc.project.width, doc.project.height, layers, renderComposite(doc, sym, frame));
  }

  /**
   * An animated PSD: one layer group per distinct frame (held frames share a group), with Photoshop frame animation
   * data so Photoshop and ToonSquid play it on their timelines.
   */
  public static function writeAnimated(doc:AnimDoc, sym:AnimSymbol):Bytes
  {
    var len = AnimData.symbolLength(sym);
    var indexes = exportLayers(sym);
    var groups:Array<PSDWriteLayer> = [];
    var bySig = new Map<String, PSDWriteLayer>();
    var prevSig = '';
    for (f in 0...len)
    {
      var rendered = [for (li in indexes) layerAt(doc, sym, li, f)];
      var sig = [for (r in rendered) r.hash].join('|');
      var g = bySig.get(sig);
      if (g == null)
      {
        g = {
          name: 'Frame ${f + 1}',
          hidden: f != 0,
          visibleFrames: [],
          children: [for (r in rendered) r.layer]
        };
        bySig.set(sig, g);
        groups.push(g);
      }
      else if (sig == prevSig && g.visibleFrames[g.visibleFrames.length - 1] == f - 1)
      {
        // Held frames: name the group "Frame 3-5".
        var firstFrame = g.visibleFrames[0];
        var run = true;
        for (i in 0...g.visibleFrames.length)
          if (g.visibleFrames[i] != firstFrame + i) run = false;
        if (run) g.name = 'Frame ${firstFrame + 1}-${f + 1}';
      }
      g.visibleFrames.push(f);
      prevSig = sig;
    }
    // Top first: the last frame's group on top.
    var layers:Array<PSDWriteLayer> = [];
    var i = groups.length - 1;
    while (i >= 0)
      layers.push(groups[i--]);
    var bg = background(doc);
    if (bg != null) layers.push(bg);
    var delay = Std.int(Math.max(1, Math.round(100 / doc.project.fps)));
    return PSDCodec.write(doc.project.width, doc.project.height, layers, renderComposite(doc, sym, 0), len, delay);
  }
}
#end
