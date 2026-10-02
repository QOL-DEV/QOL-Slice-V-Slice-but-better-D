package funkin.qol.editors.animator;

/**
 * The QOL Animator's document format (saved as JSON in `data/qol/animations/<name>.json`, with each bitmap saved as a
 * PNG next to it).
 *
 * Works like Adobe Animate: a project has symbols, each symbol has a timeline of layers, each layer is a row of
 * keyframes that hold elements (vector shapes, symbol instances, bitmaps). Symbol 0 is the main timeline ("Scene").
 */
typedef AnimProject =
{
  var version:Int;
  var name:String;
  var width:Int;
  var height:Int;
  var fps:Float;

  /**
   * Stage color (ARGB). Alpha 0 = transparent (shown as a checkerboard; exports keep transparency).
   */
  var bg:Int;

  var symbols:Array<AnimSymbol>;
  var bitmaps:Array<AnimBitmapInfo>;

  /**
   * Sounds used by audio layers (saved as WAV files next to the animation).
   */
  var ?sounds:Array<AnimSoundInfo>;
}

typedef AnimSoundInfo =
{
  var id:String;
  var name:String;
  var rate:Int;
  var channels:Int;

  /**
   * Seconds.
   */
  var length:Float;
}

typedef AnimSymbol =
{
  var id:String;
  var name:String;

  /**
   * 'graphic' (plays in sync with the timeline it's placed on) or 'movieclip' (shown the same way here).
   */
  var kind:String;

  var layers:Array<AnimLayer>;
}

typedef AnimBitmapInfo =
{
  var id:String;
  var name:String;
  var width:Int;
  var height:Int;

  /**
   * True for images in the library (placed as elements); false for the canvases of bitmap layers.
   */
  var ?library:Bool;

  /**
   * Smooth when scaled (default true).
   */
  var ?smooth:Bool;
}

typedef AnimLayer =
{
  var name:String;

  /**
   * 'vector' (shapes, symbols and placed bitmaps), 'bitmap' (a paintable canvas per keyframe), 'camera' (the main
   * timeline's camera), 'audio' (sounds) or 'folder' (holds the layers below it that are nested deeper).
   */
  var kind:String;

  /**
   * How deeply nested the layer is (0 = top level). A folder or mask layer holds the layers right below it that are
   * nested deeper than it.
   */
  var ?depth:Int;

  /**
   * Mask layer: its shapes cut out the layers nested under it (only their parts inside the mask show).
   */
  var ?mask:Bool;

  /**
   * Folders and masks: children hidden in the timeline.
   */
  var ?collapsed:Bool;

  /**
   * Stays put when the camera moves (like a HUD).
   */
  var ?fixed:Bool;

  var visible:Bool;
  var locked:Bool;

  /**
   * Shown only as outlines on the canvas (Flash's outline mode).
   */
  var ?outline:Bool;

  /**
   * Guide layers are visible while editing but left out of exports.
   */
  var ?guide:Bool;

  var color:Int;
  var alpha:Float;
  var ?blend:String;

  /**
   * Audio layers: volume (0..1, default 1).
   */
  var ?volume:Float;
  var frames:Array<AnimKeyframe>;
}

typedef AnimKeyframe =
{
  var start:Int;
  var duration:Int;
  var elements:Array<AnimElement>;

  /**
   * Bitmap layers: id of this keyframe's canvas (same size as the stage).
   */
  var ?bitmap:String;

  /**
   * Bitmap layers: where the canvas's top-left corner is (inside symbols canvases are centered on the symbol's origin).
   */
  var ?bx:Float;

  var ?by:Float;

  /**
   * Classic tween to the next keyframe (null = no tween).
   */
  var ?tween:AnimTween;

  var ?label:String;

  /**
   * Audio layers: the sound that starts playing at this keyframe.
   */
  var ?sound:String;

  /**
   * Audio layers: seconds into the sound where this keyframe starts.
   */
  var ?soundStart:Float;

  /**
   * Camera layers: where the camera looks at this keyframe.
   */
  var ?camera:AnimCamera;

  /**
   * Layer effects from this keyframe on: blend mode and filters for the whole layer.
   */
  var ?blend:String;

  var ?filters:Array<AnimFilter>;
}

/**
 * An Animate-style camera: the stage shows what the camera sees.
 */
typedef AnimCamera =
{
  /**
   * The point (in stage coordinates) at the middle of the camera's view.
   */
  var x:Float;

  var y:Float;

  /**
   * 1 = 100%.
   */
  var zoom:Float;

  /**
   * Degrees, clockwise.
   */
  var rotation:Float;
}

typedef AnimTween =
{
  /**
   * A named ease (see QOLEase), used when there's no `curve` or `accel`.
   */
  var ease:String;

  /**
   * Extra full turns while tweening (positive = clockwise).
   */
  var ?spins:Int;

  /**
   * Animate's classic ease: -100 (ease in) to 100 (ease out).
   */
  var ?accel:Float;

  /**
   * A custom ease curve: cubic Bezier points x0 y0 x1 y1 ... from (0, 0) to (1, 1) (control, control, point...).
   */
  var ?curve:Array<Float>;

  /**
   * Shape tween: shapes morph into the next keyframe's shapes.
   */
  var ?shape:Bool;
}

typedef AnimElement =
{
  /**
   * 'shape', 'symbol', 'bitmap' or 'text'.
   */
  var type:String;

  // Transform (a b c d tx ty), like Flash.
  var a:Float;
  var b:Float;
  var c:Float;
  var d:Float;
  var tx:Float;
  var ty:Float;

  /**
   * Transformation point (pivot) in the element's own coordinates.
   */
  var ?px:Float;

  var ?py:Float;

  // Color effect.
  var ?alpha:Float;

  /**
   * Advanced color: red, green, blue, alpha multipliers then offsets (overrides alpha, tint and brightness).
   */
  var ?ct:Array<Float>;

  var ?tint:Int;
  var ?tintAmount:Float;
  var ?brightness:Float;
  var ?blend:String;
  var ?filters:Array<AnimFilter>;

  // type == 'shape'
  var ?paths:Array<AnimPath>;

  // type == 'symbol'
  var ?symbol:String;

  /**
   * 'loop', 'once', 'single', 'loopReverse' or 'onceReverse'.
   */
  var ?loop:String;

  var ?firstFrame:Int;

  /**
   * Last frame to play (inclusive; null = the symbol's end).
   */
  var ?lastFrame:Int;

  // type == 'bitmap'
  var ?bitmap:String;

  // type == 'text'
  var ?text:String;
  var ?font:String;
  var ?size:Float;
  var ?color:Int;
  var ?boxWidth:Float;

  var ?name:String;

  /**
   * Hidden instances aren't drawn (Animate's "Visible" box).
   */
  var ?hidden:Bool;
}

typedef AnimPath =
{
  /**
   * Fill color (ARGB) or null.
   */
  var ?fill:Null<Int>;

  /**
   * Stroke color (ARGB) or null.
   */
  var ?stroke:Null<Int>;

  var ?width:Float;

  /**
   * Stroke ends ('round', 'square' or 'none') and corners ('round', 'miter' or 'bevel'). Default round.
   */
  var ?caps:String;

  var ?joints:String;

  /**
   * Stroke width doesn't change when scaled.
   */
  var ?hairline:Bool;

  /**
   * 'nonzero' or 'evenodd' (how overlapping outlines fill). Default: nonzero for one outline, evenodd for several.
   */
  var ?winding:String;

  /**
   * Gradient fill (instead of `fill`).
   */
  var ?gradient:AnimGradient;

  /**
   * Image fill (instead of `fill`).
   */
  var ?bitmapFill:AnimBitmapFill;

  /**
   * Commands: 0 x y = move, 1 x y = line, 2 cx cy x y = quadratic curve, 3 c1x c1y c2x c2y x y = cubic curve,
   * 4 = close.
   */
  var d:Array<Float>;
}

typedef AnimGradient =
{
  /**
   * 'linear' or 'radial'.
   */
  var type:String;

  /**
   * ARGB colors and their positions (0..255).
   */
  var colors:Array<Int>;

  var ratios:Array<Int>;

  /**
   * Maps the gradient box (-819.2..819.2 on both axes, like Flash) into the shape: a b c d tx ty.
   */
  var matrix:Array<Float>;

  /**
   * 'pad', 'reflect' or 'repeat'.
   */
  var ?spread:String;

  /**
   * Radial gradients: where the center is (-1..1).
   */
  var ?focal:Float;

  var ?linearRGB:Bool;
}

typedef AnimBitmapFill =
{
  var bitmap:String;

  /**
   * Image pixels -> shape: a b c d tx ty.
   */
  var matrix:Array<Float>;

  var ?clip:Bool;
  var ?smooth:Bool;
}

typedef AnimFilter =
{
  /**
   * 'blur', 'glow', 'shadow', 'adjust' or 'bevel'.
   */
  var type:String;

  var ?blurX:Float;
  var ?blurY:Float;
  var ?strength:Float;
  var ?color:Int;
  var ?alpha:Float;
  var ?distance:Float;
  var ?angle:Float;
  var ?inner:Bool;
  var ?knockout:Bool;
  var ?quality:Int;

  // 'bevel'
  var ?highlight:Int;
  var ?shadowColor:Int;

  // 'adjust'
  var ?brightness:Float;
  var ?contrast:Float;
  var ?saturation:Float;
  var ?hue:Float;
}

class AnimData
{
  public static inline final VERSION:Int = 1;
  public static final LAYER_COLORS:Array<Int> = [0xFF5CE1FF, 0xFFFF5C9D, 0xFF7CE38B, 0xFFFFD84A, 0xFFB59BFF, 0xFFFF9F43, 0xFF4DD0E1, 0xFFE57373];

  public static function newProject(name:String, width:Int = 1024, height:Int = 1024, fps:Float = 24):AnimProject
  {
    return {
      version: VERSION,
      name: name,
      width: width,
      height: height,
      fps: fps,
      bg: 0x00FFFFFF,
      symbols: [newSymbol('scene', 'Scene')],
      bitmaps: []
    };
  }

  public static function newSymbol(id:String, name:String, kind:String = 'graphic'):AnimSymbol
  {
    return {
      id: id,
      name: name,
      kind: kind,
      layers: [newLayer('Layer 1', 'vector', 0)]
    };
  }

  public static function newLayer(name:String, kind:String, index:Int):AnimLayer
  {
    return {
      name: name,
      kind: kind,
      visible: true,
      locked: false,
      color: LAYER_COLORS[index % LAYER_COLORS.length],
      alpha: 1,
      frames: [{start: 0, duration: 1, elements: []}]
    };
  }

  public static function identity(type:String):AnimElement
  {
    return {
      type: type,
      a: 1,
      b: 0,
      c: 0,
      d: 1,
      tx: 0,
      ty: 0
    };
  }

  public static function defaultCamera(project:AnimProject):AnimCamera
    return {
      x: project.width / 2,
      y: project.height / 2,
      zoom: 1,
      rotation: 0
    };

  public static function cameraLayer(sym:AnimSymbol):Null<AnimLayer>
  {
    for (l in sym.layers)
      if (l.kind == 'camera') return l;
    return null;
  }

  /**
   * Last frame (exclusive) of a layer.
   */
  public static function layerLength(layer:AnimLayer):Int
  {
    var end = 0;
    for (k in layer.frames)
      if (k.start + k.duration > end) end = k.start + k.duration;
    return end;
  }

  public static function symbolLength(symbol:AnimSymbol):Int
  {
    var end = 1;
    for (l in symbol.layers)
    {
      var e = layerLength(l);
      if (e > end) end = e;
    }
    return end;
  }

  /**
   * The keyframe covering `frame`, or null if the layer ends before it.
   */
  public static function keyAt(layer:AnimLayer, frame:Int):Null<AnimKeyframe>
  {
    for (k in layer.frames)
      if (frame >= k.start && frame < k.start + k.duration) return k;
    return null;
  }

  public static function keyIndexAt(layer:AnimLayer, frame:Int):Int
  {
    for (i in 0...layer.frames.length)
    {
      var k = layer.frames[i];
      if (frame >= k.start && frame < k.start + k.duration) return i;
    }
    return -1;
  }

  /**
   * Deep copy through JSON (elements, keyframes...).
   */
  public static inline function copy<T>(value:T):T
    return haxe.Json.parse(haxe.Json.stringify(value));

  static var idCounter:Int = 0;

  public static function makeId(prefix:String):String
  {
    idCounter++;
    return '$prefix-${StringTools.hex(Std.int(Date.now().getTime() / 1000) & 0xFFFFFF, 6)}${StringTools.hex(idCounter, 3)}${StringTools.hex(Std.random(0xFFF), 3)}'.toLowerCase();
  }
}
