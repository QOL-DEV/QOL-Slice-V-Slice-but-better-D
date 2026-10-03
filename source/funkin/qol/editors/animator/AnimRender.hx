package funkin.qol.editors.animator;

import funkin.qol.editors.animator.AnimData;
import openfl.display.Bitmap;
import openfl.display.BlendMode;
import openfl.display.DisplayObject;
import openfl.display.PixelSnapping;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.filters.BitmapFilter;
import openfl.filters.BlurFilter;
import openfl.filters.ColorMatrixFilter;
import openfl.filters.DropShadowFilter;
import openfl.filters.GlowFilter;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.text.TextField;
import openfl.text.TextFormat;

typedef AnimRenderOptions =
{
  /**
   * Leave out guide layers and hidden layers (for exports).
   */
  var ?forExport:Bool;

  /**
   * Record which display object belongs to which layer/element (for clicking things on the canvas).
   */
  var ?collectHits:Bool;

  /**
   * Show every layer as outlines.
   */
  var ?allOutlines:Bool;

  /**
   * Draw through this camera (world -> stage). Exports of the main timeline use its camera automatically.
   */
  var ?camera:Matrix;

  /**
   * Leave the camera out (exports).
   */
  var ?noCamera:Bool;

  /**
   * A camera applied outside the render (the editor's camera view): layers attached to the camera cancel it out.
   */
  var ?outerCamera:Matrix;
}

typedef CachedShape =
{
  var shape:Shape;
  var sig:Float;
  var used:Int;
}

typedef AnimHit =
{
  var obj:DisplayObject;
  var layer:Int;
  var element:Int;
}

/**
 * Turns Animator documents into OpenFL display objects (shapes, bitmaps, nested symbols with tweens, color effects,
 * filters and blend modes), exactly like Animate draws them.
 */
class AnimRender
{
  public var doc:AnimDoc;

  /**
   * Filled by `render` when `collectHits` is on.
   */
  public var hits:Array<AnimHit> = [];

  public function new(doc:AnimDoc)
  {
    this.doc = doc;
  }

  /**
   * Draw a symbol's timeline at a frame.
   */
  public function render(sym:AnimSymbol, frame:Int, ?opts:AnimRenderOptions):Sprite
  {
    hits = [];
    opts = opts ?? {};
    rendering = true;
    renderCount++;
    shapeUse = new haxe.ds.ObjectMap();
    var cam = opts.camera;
    if (cam == null && opts.forExport == true && opts.noCamera != true && sym == doc.main) cam = cameraMatrix(sym, frame);
    // Layers attached to the camera cancel it out.
    var outer = cam ?? opts.outerCamera;
    fixedMatrix = null;
    if (outer != null && sym == doc.main)
    {
      fixedMatrix = outer.clone();
      fixedMatrix.invert();
    }
    var root = renderSymbol(sym, frame, opts, 0, true);
    rendering = false;
    if (renderCount % 16 == 0) sweepShapes();
    if (cam == null) return root;
    var wrap = new Sprite();
    wrap.addChild(root);
    wrap.transform.matrix = cam;
    return wrap;
  }

  var rendering:Bool = false;
  var renderCount:Int = 0;
  var fixedMatrix:Null<Matrix> = null;

  /**
   * Drawn shapes kept between renders (drawing big shapes again every frame is slow), by their paths.
   */
  var shapeCache = new haxe.ds.ObjectMap<Array<AnimPath>, Array<CachedShape>>();

  var shapeUse = new haxe.ds.ObjectMap<Array<AnimPath>, Int>();

  function sweepShapes():Void
  {
    for (key in [for (k in shapeCache.keys()) k])
    {
      var list = shapeCache.get(key);
      var keep = [for (c in list) if (renderCount - c.used < 48) c];
      for (c in list)
        if (renderCount - c.used >= 48) c.shape.graphics.clear();
      if (keep.length == 0) shapeCache.remove(key);
      else
        shapeCache.set(key, keep);
    }
  }

  /**
   * Forget every kept shape.
   */
  public function clearCache():Void
  {
    for (list in shapeCache)
      for (c in list)
        c.shape.graphics.clear();
    shapeCache = new haxe.ds.ObjectMap();
  }

  static function pathsSignature(paths:Array<AnimPath>, outline:Bool, color:Int):Float
  {
    var s:Float = outline ? color + 7 : 3;
    for (p in paths)
    {
      var d = p.d;
      s = s * 1.0001 + d.length * 31 + (p.fill ?? 5) * 1e-7 + (p.stroke ?? 9) * 3e-7 + (p.width ?? 0) * 13;
      if (p.gradient != null) for (c in p.gradient.colors)
        s += c * 1e-8;
      if (p.gradient != null) for (m in p.gradient.matrix)
        s += m * 17;
      if (p.bitmapFill != null) s += p.bitmapFill.bitmap.length * 0.37 + p.bitmapFill.matrix[0] * 7 + p.bitmapFill.matrix[4] * 11;
      var i = 0;
      while (i < d.length)
      {
        s += d[i] * ((i % 13) + 1);
        i += 2;
      }
    }
    return s;
  }

  function shapeFor(paths:Array<AnimPath>, outline:Bool, outlineColor:Int):Shape
  {
    if (!rendering)
    {
      var shape = new Shape();
      for (p in paths)
        AnimGeom.drawPath(shape.graphics, p, outline, outlineColor, doc.getBitmap);
      return shape;
    }
    var sig = pathsSignature(paths, outline, outlineColor);
    var list = shapeCache.get(paths);
    if (list == null)
    {
      list = [];
      shapeCache.set(paths, list);
    }
    var idx = shapeUse.exists(paths) ? shapeUse.get(paths) : 0;
    shapeUse.set(paths, idx + 1);
    var c:CachedShape;
    if (idx < list.length)
    {
      c = list[idx];
      resetLook(c.shape);
      if (c.sig != sig)
      {
        c.shape.graphics.clear();
        for (p in paths)
          AnimGeom.drawPath(c.shape.graphics, p, outline, outlineColor, doc.getBitmap);
        c.sig = sig;
      }
    }
    else
    {
      var shape = new Shape();
      for (p in paths)
        AnimGeom.drawPath(shape.graphics, p, outline, outlineColor, doc.getBitmap);
      c = {shape: shape, sig: sig, used: renderCount};
      list.push(c);
    }
    c.used = renderCount;
    return c.shape;
  }

  static function resetLook(obj:DisplayObject):Void
  {
    if (obj.parent != null) obj.parent.removeChild(obj);
    obj.transform.colorTransform = new ColorTransform();
    obj.blendMode = BlendMode.NORMAL;
    obj.filters = null;
    obj.alpha = 1;
    obj.visible = true;
    obj.mask = null;
  }

  /**
   * The camera at a frame (with its tween), or null if the timeline has no camera.
   */
  public function cameraAt(sym:AnimSymbol, frame:Int):Null<AnimCamera>
  {
    var layer = AnimData.cameraLayer(sym);
    if (layer == null || !layer.visible) return null;
    var key = AnimData.keyAt(layer, frame);
    if (key == null)
    {
      // Between and after keyframes, the camera holds the last keyframe before this frame.
      var prev:Null<AnimKeyframe> = null;
      for (k in layer.frames)
        if (k.start <= frame && (prev == null || k.start > prev.start)) prev = k;
      if (prev == null || prev.camera == null) return null;
      return prev.camera;
    }
    var cam = key.camera ?? AnimData.defaultCamera(doc.project);
    if (key.tween == null || frame <= key.start) return cam;
    var idx = layer.frames.indexOf(key);
    if (idx < 0 || idx + 1 >= layer.frames.length || layer.frames[idx + 1].camera == null) return cam;
    var next = layer.frames[idx + 1].camera;
    var t = AnimEase.apply(key.tween, (frame - key.start) / key.duration);
    var dr = next.rotation - cam.rotation;
    while (dr > 180)
      dr -= 360;
    while (dr < -180)
      dr += 360;
    // Like any tweened object, the camera's size changes evenly (so zooming in speeds up toward the end).
    var size = lerp(1 / Math.max(0.0001, cam.zoom), 1 / Math.max(0.0001, next.zoom), t);
    return {
      x: lerp(cam.x, next.x, t),
      y: lerp(cam.y, next.y, t),
      zoom: 1 / Math.max(0.0001, size),
      rotation: cam.rotation + (dr + (key.tween.spins ?? 0) * 360) * t
    };
  }

  /**
   * World -> stage for a camera.
   */
  public function matrixOf(cam:AnimCamera):Matrix
  {
    var m = new Matrix();
    m.translate(-cam.x, -cam.y);
    m.rotate(-cam.rotation * Math.PI / 180);
    m.scale(cam.zoom, cam.zoom);
    m.translate(doc.project.width / 2, doc.project.height / 2);
    return m;
  }

  public function cameraMatrix(sym:AnimSymbol, frame:Int):Null<Matrix>
  {
    var cam = cameraAt(sym, frame);
    return cam == null ? null : matrixOf(cam);
  }

  function renderSymbol(sym:AnimSymbol, frame:Int, opts:AnimRenderOptions, depth:Int, top:Bool):Sprite
  {
    var root = new Sprite();
    if (depth > 12) return root;
    renderLayers(sym, frame, opts, depth, top, 0, sym.layers.length, root);
    return root;
  }

  /**
   * Draw layers `start`..`end` (one nesting level, with their folders' and masks' children) into `into`.
   */
  function renderLayers(sym:AnimSymbol, frame:Int, opts:AnimRenderOptions, depth:Int, top:Bool, start:Int, end:Int, into:Sprite):Void
  {
    // Each item is a layer and the layers nested under it.
    var items:Array<{at:Int, end:Int}> = [];
    var i = start;
    while (i < end)
    {
      var level = sym.layers[i].depth ?? 0;
      var j = i + 1;
      while (j < end && (sym.layers[j].depth ?? 0) > level)
        j++;
      items.push({at: i, end: j});
      i = j;
    }
    // Layers are listed top first (like the timeline), so draw them bottom first.
    var k = items.length - 1;
    while (k >= 0)
    {
      var item = items[k--];
      var layer = sym.layers[item.at];
      if (!layer.visible) continue;
      if (opts.forExport == true && layer.guide == true) continue;
      var hasChildren = item.end > item.at + 1;
      if (layer.kind == 'folder')
      {
        if (hasChildren) renderLayers(sym, frame, opts, depth, top, item.at + 1, item.end, into);
        continue;
      }
      var own = layerObject(sym, item.at, frame, opts, depth, top);
      if (layer.mask == true && hasChildren)
      {
        var group = new Sprite();
        renderLayers(sym, frame, opts, depth, top, item.at + 1, item.end, group);
        // Like Animate, masks show while editing only when the mask layer is locked.
        var masking = own != null && (opts.forExport == true || layer.locked) && layer.outline != true && opts.allOutlines != true;
        into.addChild(group);
        if (own != null)
        {
          into.addChild(own);
          if (masking) group.mask = own;
        }
        continue;
      }
      if (hasChildren) renderLayers(sym, frame, opts, depth, top, item.at + 1, item.end, into);
      if (own != null) into.addChild(own);
    }
  }

  /**
   * One layer's contents at a frame (null if it has nothing there).
   */
  function layerObject(sym:AnimSymbol, li:Int, frame:Int, opts:AnimRenderOptions, depth:Int, top:Bool):Null<Sprite>
  {
    var layer = sym.layers[li];
    if (layer.kind == 'camera' || layer.kind == 'audio' || layer.kind == 'folder') return null;
    var key = AnimData.keyAt(layer, frame);
    if (key == null) return null;
    var layerSprite = new Sprite();
    layerSprite.alpha = layer.alpha;
    var blend = key.blend ?? layer.blend;
    if (blend != null && blend != 'normal') layerSprite.blendMode = blendOf(blend);
    if (key.filters != null && key.filters.length > 0) layerSprite.filters = filtersOf(key.filters);
    if (top && depth == 0 && layer.fixed == true && fixedMatrix != null) layerSprite.transform.matrix = fixedMatrix.clone();
    var outline = (layer.outline == true || opts.allOutlines == true) && opts.forExport != true;

    if (layer.kind == 'bitmap')
    {
      var bmp = doc.getBitmap(key.bitmap);
      if (bmp != null)
      {
        var b = new Bitmap(bmp, PixelSnapping.NEVER, true);
        b.x = key.bx ?? 0;
        b.y = key.by ?? 0;
        if (outline) b.alpha = 0.35;
        layerSprite.addChild(b);
      }
    }
    else
    {
      var elements = tweenedElements(layer, key, frame);
      for (ei in 0...elements.length)
      {
        var el = elements[ei];
        var obj = elementObject(el, frame - key.start, opts, depth, outline, layer.color);
        if (obj == null) continue;
        layerSprite.addChild(obj);
        if (top && opts.collectHits == true) hits.push({obj: obj, layer: li, element: ei});
      }
    }
    return layerSprite;
  }

  /**
   * A keyframe's elements at a frame, with its tween applied.
   */
  public function tweenedElements(layer:AnimLayer, key:AnimKeyframe, frame:Int):Array<AnimElement>
  {
    if (key.tween == null || frame <= key.start) return key.elements;
    var idx = layer.frames.indexOf(key);
    if (idx < 0 || idx + 1 >= layer.frames.length) return key.elements;
    var next = layer.frames[idx + 1];
    if (next.start != key.start + key.duration) return key.elements;
    var t = AnimEase.apply(key.tween, (frame - key.start) / key.duration);
    if (key.tween.shape == true) return AnimMorph.elements(key, next, t);
    var out:Array<AnimElement> = [];
    for (i in 0...key.elements.length)
    {
      var a = key.elements[i];
      var b = i < next.elements.length ? next.elements[i] : null;
      if (b == null || b.type != a.type || a.type == 'shape' || (a.type == 'symbol' && a.symbol != b.symbol)
        || (a.type == 'bitmap' && a.bitmap != b.bitmap))
      {
        out.push(a);
        continue;
      }
      out.push(lerpElement(a, b, t, key.tween.spins ?? 0));
    }
    return out;
  }

  public static function lerpElement(a:AnimElement, b:AnimElement, t:Float, spins:Int):AnimElement
  {
    var da = AnimGeom.decomposeEl(a);
    var db = AnimGeom.decomposeEl(b);
    // Shortest way round, plus any extra turns.
    var dr = db.rotation - da.rotation;
    while (dr > 180)
      dr -= 360;
    while (dr < -180)
      dr += 360;
    dr += spins * 360;
    var ds = db.skew - da.skew;
    while (ds > 180)
      ds -= 360;
    while (ds < -180)
      ds += 360;
    var m = AnimGeom.compose({
      x: 0,
      y: 0,
      scaleX: lerp(da.scaleX, db.scaleX, t),
      scaleY: lerp(da.scaleY, db.scaleY, t),
      rotation: da.rotation + dr * t,
      skew: da.skew + ds * t
    });
    // Like Animate, the transformation point moves in a straight line and everything turns and scales around it.
    var pxA = a.px ?? 0, pyA = a.py ?? 0, pxB = b.px ?? pxA, pyB = b.py ?? pyA;
    var px = lerp(pxA, pxB, t), py = lerp(pyA, pyB, t);
    var ax = a.a * pxA + a.c * pyA + a.tx, ay = a.b * pxA + a.d * pyA + a.ty;
    var bx = b.a * pxB + b.c * pyB + b.tx, by = b.b * pxB + b.d * pyB + b.ty;
    var wx = lerp(ax, bx, t), wy = lerp(ay, by, t);
    m.tx = wx - (m.a * px + m.c * py);
    m.ty = wy - (m.b * px + m.d * py);
    var out:AnimElement = Reflect.copy(a);
    AnimGeom.setMatrix(out, m);
    if (a.px != null || b.px != null)
    {
      out.px = px;
      out.py = py;
    }
    // Color effects blend as color transforms (so alpha can tween into a tint, like Animate).
    var ca = colorArray(a), cb = colorArray(b);
    if (ca != null || cb != null)
    {
      ca = ca ?? IDENTITY_CT;
      cb = cb ?? IDENTITY_CT;
      var simple = a.ct == null && b.ct == null && sameKind(a, b);
      if (simple)
      {
        out.alpha = lerp(a.alpha ?? 1, b.alpha ?? 1, t);
        out.brightness = lerp(a.brightness ?? 0, b.brightness ?? 0, t);
        out.tintAmount = lerp(a.tintAmount ?? 0, b.tintAmount ?? 0, t);
        if (b.tint != null && (b.tintAmount ?? 0) > 0) out.tint = a.tint == null ? b.tint : lerpColor(a.tint, b.tint, t);
      }
      else
      {
        out.ct = [for (i in 0...8) lerp(ca[i], cb[i], t)];
        out.alpha = null;
        out.tint = null;
        out.tintAmount = null;
        out.brightness = null;
      }
    }
    if (a.filters != null && b.filters != null && a.filters.length == b.filters.length)
    {
      out.filters = [];
      for (i in 0...a.filters.length)
      {
        var fa = a.filters[i], fb = b.filters[i];
        if (fa.type != fb.type)
        {
          out.filters.push(fa);
          continue;
        }
        var f:AnimFilter = Reflect.copy(fa);
        for (field in ['blurX', 'blurY', 'strength', 'alpha', 'distance', 'angle', 'brightness', 'contrast', 'saturation', 'hue'])
        {
          var va:Null<Float> = Reflect.field(fa, field);
          var vb:Null<Float> = Reflect.field(fb, field);
          if (va != null && vb != null) Reflect.setField(f, field, lerp(va, vb, t));
        }
        if (fa.color != null && fb.color != null) f.color = lerpColor(fa.color, fb.color, t);
        out.filters.push(f);
      }
    }
    return out;
  }

  static final IDENTITY_CT:Array<Float> = [1, 1, 1, 1, 0, 0, 0, 0];

  /**
   * Both use only alpha, or only brightness, or only tint (then the simple values can tween directly).
   */
  static function sameKind(a:AnimElement, b:AnimElement):Bool
  {
    inline function kind(e:AnimElement):Int
    {
      var k = 0;
      if ((e.alpha ?? 1) != 1) k |= 1;
      if ((e.brightness ?? 0) != 0) k |= 2;
      if (e.tint != null && (e.tintAmount ?? 0) != 0) k |= 4;
      return k;
    }
    var ka = kind(a), kb = kind(b);
    return ka == 0 || kb == 0 || ka == kb;
  }

  /**
   * An element's color effect as multipliers and offsets (null if it has none).
   */
  public static function colorArray(el:AnimElement):Null<Array<Float>>
  {
    var ct = colorTransformOf(el);
    if (ct == null) return null;
    return [
      ct.redMultiplier, ct.greenMultiplier, ct.blueMultiplier, ct.alphaMultiplier, ct.redOffset, ct.greenOffset, ct.blueOffset, ct.alphaOffset
    ];
  }

  static inline function lerp(a:Float, b:Float, t:Float):Float
    return a + (b - a) * t;

  public static function lerpColor(a:Int, b:Int, t:Float):Int
  {
    var r = Std.int(lerp((a >> 16) & 0xFF, (b >> 16) & 0xFF, t));
    var g = Std.int(lerp((a >> 8) & 0xFF, (b >> 8) & 0xFF, t));
    var bl = Std.int(lerp(a & 0xFF, b & 0xFF, t));
    var al = Std.int(lerp((a >>> 24) & 0xFF, (b >>> 24) & 0xFF, t));
    return (al << 24) | (r << 16) | (g << 8) | bl;
  }

  /**
   * One element as a display object (with its matrix, color effect, filters and blend mode applied).
   */
  public function elementObject(el:AnimElement, localFrame:Int, opts:AnimRenderOptions, depth:Int, outline:Bool, outlineColor:Int):Null<DisplayObject>
  {
    if (el.hidden == true && opts.forExport == true) return null;
    var obj:Null<DisplayObject> = null;
    switch (el.type)
    {
      case 'shape':
        if (el.paths == null || el.paths.length == 0) return null;
        obj = shapeFor(el.paths, outline, outlineColor);
      case 'bitmap':
        var bmp = doc.getBitmap(el.bitmap);
        if (bmp == null) return null;
        var info = doc.bitmapInfo(el.bitmap);
        var b = new Bitmap(bmp, PixelSnapping.NEVER, info == null || info.smooth != false);
        if (outline) b.alpha = 0.35;
        obj = b;
      case 'symbol':
        var sym = el.symbol == null ? null : doc.symbol(el.symbol);
        if (sym == null) return null;
        var child = renderSymbol(sym, symbolFrame(el, sym, localFrame), outline ? {forExport: opts.forExport, allOutlines: true} : opts, depth + 1, false);
        obj = child;
      case 'text':
        var tf = new TextField();
        tf.selectable = false;
        tf.multiline = true;
        tf.wordWrap = el.boxWidth != null && el.boxWidth > 0;
        if (tf.wordWrap) tf.width = el.boxWidth;
        tf.defaultTextFormat = new TextFormat(el.font ?? '_sans', Std.int(el.size ?? 32), (el.color ?? 0xFF000000) & 0xFFFFFF);
        tf.text = el.text ?? '';
        if (!tf.wordWrap) tf.width = tf.textWidth + 6;
        tf.height = tf.textHeight + 6;
        obj = tf;
      default:
        return null;
    }
    applyLook(obj, el);
    // Hidden instances stay faintly visible while editing so they can still be found.
    if (el.hidden == true) obj.alpha *= 0.25;
    return obj;
  }

  /**
   * Which frame of a symbol an instance shows, `localFrame` frames after its keyframe.
   */
  public static function symbolFrame(el:AnimElement, sym:AnimSymbol, localFrame:Int):Int
  {
    var len = AnimData.symbolLength(sym);
    var first = Std.int(Math.max(0, Math.min(len - 1, el.firstFrame ?? 0)));
    var last = el.lastFrame != null ? Std.int(Math.max(0, Math.min(len - 1, el.lastFrame))) : -1;
    return switch (el.loop ?? 'loop')
    {
      case 'single': first;
      case 'once':
        Std.int(Math.min(first + localFrame, last >= first ? last : len - 1));
      case 'loopReverse':
        if (last >= 0 && last <= first) first - (localFrame % (first - last + 1));
        else
          ((first - localFrame) % len + len) % len;
      case 'onceReverse':
        Std.int(Math.max(first - localFrame, last >= 0 && last <= first ? last : 0));
      default:
        if (last > first) first + (localFrame % (last - first + 1));
        else
          (first + localFrame) % len;
    };
  }

  /**
   * Matrix, color effect, blend and filters.
   */
  public static function applyLook(obj:DisplayObject, el:AnimElement):Void
  {
    obj.transform.matrix = new Matrix(el.a, el.b, el.c, el.d, el.tx, el.ty);
    var ct = colorTransformOf(el);
    if (ct != null) obj.transform.colorTransform = ct;
    if (el.blend != null && el.blend != 'normal') obj.blendMode = blendOf(el.blend);
    if (el.filters != null && el.filters.length > 0) obj.filters = filtersOf(el.filters);
  }

  public static function filtersOf(list:Array<AnimFilter>):Array<BitmapFilter>
  {
    var out:Array<BitmapFilter> = [];
    for (f in list)
    {
      if (f.type == 'bevel')
      {
        // OpenFL has no bevel filter: a light inner shadow on one side and a dark one on the other look the same.
        var q = f.quality ?? 2;
        var hi = f.highlight ?? 0xFFFFFFFF, sh = f.shadowColor ?? 0xFF000000;
        var dist = f.distance ?? 4, angle = f.angle ?? 45;
        out.push(new DropShadowFilter(dist, angle + 180, hi & 0xFFFFFF, ((hi >>> 24) & 0xFF) / 255, f.blurX ?? 4, f.blurY ?? 4, f.strength ?? 1, q, true));
        out.push(new DropShadowFilter(dist, angle, sh & 0xFFFFFF, ((sh >>> 24) & 0xFF) / 255, f.blurX ?? 4, f.blurY ?? 4, f.strength ?? 1, q, true));
      }
      else
        out.push(filterOf(f));
    }
    return out;
  }

  public static function colorTransformOf(el:AnimElement):Null<ColorTransform>
  {
    if (el.ct != null && el.ct.length >= 8)
    {
      var c = el.ct;
      return new ColorTransform(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]);
    }
    var alpha = el.alpha ?? 1;
    var tintAmt = el.tint != null ? (el.tintAmount ?? 0) : 0;
    var bright = el.brightness ?? 0;
    if (alpha == 1 && tintAmt == 0 && bright == 0) return null;
    var ct = new ColorTransform(1, 1, 1, alpha);
    if (tintAmt != 0)
    {
      var c = el.tint;
      ct.redMultiplier = ct.greenMultiplier = ct.blueMultiplier = 1 - tintAmt;
      ct.redOffset = ((c >> 16) & 0xFF) * tintAmt;
      ct.greenOffset = ((c >> 8) & 0xFF) * tintAmt;
      ct.blueOffset = (c & 0xFF) * tintAmt;
    }
    if (bright > 0)
    {
      ct.redOffset = ct.redOffset * (1 - bright) + 255 * bright;
      ct.greenOffset = ct.greenOffset * (1 - bright) + 255 * bright;
      ct.blueOffset = ct.blueOffset * (1 - bright) + 255 * bright;
      ct.redMultiplier *= 1 - bright;
      ct.greenMultiplier *= 1 - bright;
      ct.blueMultiplier *= 1 - bright;
    }
    else if (bright < 0)
    {
      var k = 1 + bright;
      ct.redMultiplier *= k;
      ct.greenMultiplier *= k;
      ct.blueMultiplier *= k;
      ct.redOffset *= k;
      ct.greenOffset *= k;
      ct.blueOffset *= k;
    }
    return ct;
  }

  public static function blendOf(name:String):BlendMode
  {
    return switch (name)
    {
      case 'add': BlendMode.ADD;
      case 'multiply': BlendMode.MULTIPLY;
      case 'screen': BlendMode.SCREEN;
      case 'lighten': BlendMode.LIGHTEN;
      case 'darken': BlendMode.DARKEN;
      case 'difference': BlendMode.DIFFERENCE;
      case 'subtract': BlendMode.SUBTRACT;
      case 'invert': BlendMode.INVERT;
      case 'overlay': BlendMode.OVERLAY;
      case 'hardlight': BlendMode.HARDLIGHT;
      case 'alpha': BlendMode.ALPHA;
      case 'erase': BlendMode.ERASE;
      case 'layer': BlendMode.LAYER;
      default: BlendMode.NORMAL;
    }
  }

  public static final BLEND_NAMES:Array<String> = [
    'normal', 'layer', 'multiply', 'screen', 'add', 'lighten', 'darken', 'difference', 'subtract', 'overlay', 'hardlight', 'invert', 'alpha', 'erase'
  ];

  public static function filterOf(f:AnimFilter):BitmapFilter
  {
    var q = f.quality ?? 2;
    return switch (f.type)
    {
      case 'glow':
        new GlowFilter((f.color ?? 0xFFFFFF) & 0xFFFFFF, f.alpha ?? 1, f.blurX ?? 8, f.blurY ?? 8, f.strength ?? 2, q, f.inner == true, f.knockout == true);
      case 'shadow':
        new DropShadowFilter(f.distance ?? 6, f.angle ?? 45, (f.color ?? 0) & 0xFFFFFF, f.alpha ?? 0.6, f.blurX ?? 6, f.blurY ?? 6, f.strength ?? 1, q,
          f.inner == true, f.knockout == true);
      case 'adjust':
        new ColorMatrixFilter(adjustMatrix(f.brightness ?? 0, f.contrast ?? 0, f.saturation ?? 0, f.hue ?? 0));
      default:
        new BlurFilter(f.blurX ?? 6, f.blurY ?? 6, q);
    }
  }

  /**
   * Flash's "Adjust Color" filter (each value -100..100, hue -180..180).
   */
  public static function adjustMatrix(brightness:Float, contrast:Float, saturation:Float, hue:Float):Array<Float>
  {
    var m:Array<Float> = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
    function concat(b:Array<Float>)
    {
      var out:Array<Float> = [];
      for (row in 0...4)
      {
        for (col in 0...5)
        {
          var v = 0.0;
          for (k in 0...4)
            v += b[row * 5 + k] * m[k * 5 + col];
          if (col == 4) v += b[row * 5 + 4];
          out.push(v);
        }
      }
      m = out;
    }
    if (brightness != 0)
    {
      var o = brightness * 2.55;
      concat([1, 0, 0, 0, o, 0, 1, 0, 0, o, 0, 0, 1, 0, o, 0, 0, 0, 1, 0]);
    }
    if (contrast != 0)
    {
      var s = 1 + contrast / 100;
      var o = 128 * (1 - s);
      concat([s, 0, 0, 0, o, 0, s, 0, 0, o, 0, 0, s, 0, o, 0, 0, 0, 1, 0]);
    }
    if (saturation != 0)
    {
      var s = 1 + saturation / 100;
      var lr = 0.3086, lg = 0.6094, lb = 0.0820;
      var sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
      concat([sr + s, sg, sb, 0, 0, sr, sg + s, sb, 0, 0, sr, sg, sb + s, 0, 0, 0, 0, 0, 1, 0]);
    }
    if (hue != 0)
    {
      var a = hue * Math.PI / 180;
      var cos = Math.cos(a), sin = Math.sin(a);
      var lr = 0.213, lg = 0.715, lb = 0.072;
      concat([
        lr + cos * (1 - lr) + sin * (-lr), lg + cos * (-lg) + sin * (-lg), lb + cos * (-lb) + sin * (1 - lb), 0, 0,
        lr + cos * (-lr) + sin * 0.143, lg + cos * (1 - lg) + sin * 0.140, lb + cos * (-lb) + sin * (-0.283), 0, 0,
        lr + cos * (-lr) + sin * (-(1 - lr)), lg + cos * (-lg) + sin * lg, lb + cos * (1 - lb) + sin * lb, 0, 0,
        0, 0, 0, 1, 0
      ]);
    }
    return m;
  }
}
