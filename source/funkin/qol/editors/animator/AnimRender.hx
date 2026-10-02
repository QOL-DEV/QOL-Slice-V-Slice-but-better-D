package funkin.qol.editors.animator;

import funkin.qol.editors.animator.AnimData;
import funkin.qol.util.QOLEase;
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
    var root = renderSymbol(sym, frame, opts, 0, true);
    var cam = opts.camera;
    if (cam == null && opts.forExport == true && opts.noCamera != true && sym == doc.main) cam = cameraMatrix(sym, frame);
    if (cam == null) return root;
    var wrap = new Sprite();
    wrap.addChild(root);
    wrap.transform.matrix = cam;
    return wrap;
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
      // After the camera layer ends, it holds its last keyframe.
      key = layer.frames.length > 0 ? layer.frames[layer.frames.length - 1] : null;
      if (key == null || key.camera == null) return null;
      return key.camera;
    }
    var cam = key.camera ?? AnimData.defaultCamera(doc.project);
    if (key.tween == null || frame <= key.start) return cam;
    var idx = layer.frames.indexOf(key);
    if (idx < 0 || idx + 1 >= layer.frames.length || layer.frames[idx + 1].camera == null) return cam;
    var next = layer.frames[idx + 1].camera;
    var t = QOLEase.get(key.tween.ease)((frame - key.start) / key.duration);
    var dr = next.rotation - cam.rotation;
    return {
      x: lerp(cam.x, next.x, t),
      y: lerp(cam.y, next.y, t),
      zoom: lerp(cam.zoom, next.zoom, t),
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
    // Layers are listed top first (like the timeline), so draw them bottom first.
    var i = sym.layers.length - 1;
    while (i >= 0)
    {
      var layer = sym.layers[i];
      var li = i;
      i--;
      if (!layer.visible) continue;
      if (opts.forExport == true && layer.guide == true) continue;
      if (layer.kind == 'camera' || layer.kind == 'audio') continue;
      var key = AnimData.keyAt(layer, frame);
      if (key == null) continue;
      var layerSprite = new Sprite();
      layerSprite.alpha = layer.alpha;
      if (layer.blend != null) layerSprite.blendMode = blendOf(layer.blend);
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
      root.addChild(layerSprite);
    }
    return root;
  }

  /**
   * A keyframe's elements at a frame, with its classic tween applied.
   */
  public function tweenedElements(layer:AnimLayer, key:AnimKeyframe, frame:Int):Array<AnimElement>
  {
    if (key.tween == null || frame <= key.start) return key.elements;
    var idx = layer.frames.indexOf(key);
    if (idx < 0 || idx + 1 >= layer.frames.length) return key.elements;
    var next = layer.frames[idx + 1];
    var t = (frame - key.start) / key.duration;
    t = QOLEase.get(key.tween.ease)(t);
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
    var m = AnimGeom.compose({
      x: lerp(da.x, db.x, t),
      y: lerp(da.y, db.y, t),
      scaleX: lerp(da.scaleX, db.scaleX, t),
      scaleY: lerp(da.scaleY, db.scaleY, t),
      rotation: da.rotation + dr * t,
      skew: lerp(da.skew, db.skew, t)
    });
    var out:AnimElement = Reflect.copy(a);
    AnimGeom.setMatrix(out, m);
    out.alpha = lerp(a.alpha ?? 1, b.alpha ?? 1, t);
    out.brightness = lerp(a.brightness ?? 0, b.brightness ?? 0, t);
    out.tintAmount = lerp(a.tintAmount ?? 0, b.tintAmount ?? 0, t);
    if (b.tint != null && (b.tintAmount ?? 0) > 0) out.tint = a.tint == null ? b.tint : lerpColor(a.tint, b.tint, t);
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
    var obj:Null<DisplayObject> = null;
    switch (el.type)
    {
      case 'shape':
        var shape = new Shape();
        if (el.paths != null) for (p in el.paths)
          AnimGeom.drawPath(shape.graphics, p, outline, outlineColor);
        obj = shape;
      case 'bitmap':
        var bmp = doc.getBitmap(el.bitmap);
        if (bmp == null) return null;
        var b = new Bitmap(bmp, PixelSnapping.NEVER, true);
        if (outline) b.alpha = 0.35;
        obj = b;
      case 'symbol':
        var sym = el.symbol == null ? null : doc.symbol(el.symbol);
        if (sym == null) return null;
        var len = AnimData.symbolLength(sym);
        var first = el.firstFrame ?? 0;
        var f = switch (el.loop ?? 'loop')
        {
          case 'single': first;
          case 'once': Std.int(Math.min(first + localFrame, len - 1));
          default: (first + localFrame) % len;
        };
        var child = renderSymbol(sym, f, outline ? {forExport: opts.forExport, allOutlines: true} : opts, depth + 1, false);
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
    return obj;
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
    if (el.filters != null && el.filters.length > 0) obj.filters = [for (f in el.filters) filterOf(f)];
  }

  public static function colorTransformOf(el:AnimElement):Null<ColorTransform>
  {
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
