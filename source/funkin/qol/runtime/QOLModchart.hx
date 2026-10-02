package funkin.qol.runtime;

import flixel.FlxCamera;
import flixel.FlxObject;
import flixel.FlxSprite;
import funkin.play.notes.NoteSprite;
import funkin.play.notes.Strumline;
import funkin.play.notes.SustainTrail;
import funkin.qol.util.QOLEase;
import funkin.qol.util.QOLJson;
import funkin.util.GRhythmUtil;

/**
 * One keyframe on a modchart track.
 */
typedef QOLModKey =
{
  /**
   * Time in beats.
   */
  var t:Float;

  /**
   * Value at this key.
   */
  var v:Float;

  /**
   * Ease used to tween INTO this key from the previous one (any ease name, or `INSTANT`). Defaults to linear.
   */
  var ?e:String;
}

/**
 * A property of one target animated over time, like an animator's tween layer.
 */
typedef QOLModTrack =
{
  /**
   * What is animated: `strum:0` (player strumline), `strum:1:2` (opponent's up arrow), `camGame`, `healthBar`, `char:gf`, `prop:<name>`...
   */
  var target:String;

  /**
   * Which property or modifier (see `QOLModchart.PROPS`).
   */
  var prop:String;

  var keys:Array<QOLModKey>;

  /**
   * Muted tracks are kept but not applied.
   */
  var ?muted:Bool;
}

/**
 * A whole modchart: `data/qol/modcharts/<song>.json` (or `<song>-<variation>.json`).
 */
typedef QOLModchartData =
{
  var version:String;
  var ?song:String;
  var tracks:Array<QOLModTrack>;
}

/**
 * Describes a modchart property / modifier.
 */
typedef QOLModProp =
{
  var id:String;
  var name:String;
  var group:String;
  var neutral:Float;

  /**
   * How a strumline value and an arrow value combine: `add`, `mul` or `param` (the arrow's value overrides).
   */
  var combine:String;

  var min:Float;
  var max:Float;
  var step:Float;

  /**
   * Which kinds of targets have it: `strum`, `lane`, `object`, `camera`.
   */
  var kinds:Array<String>;

  var desc:String;
}

/**
 * What the runtime animates. PlayState and the Modchart Editor's preview each provide one.
 */
typedef QOLModHost =
{
  var strumlines:Map<Int, Strumline>;
  var objects:String->Null<Array<FlxObject>>;
  var cameras:Map<String, FlxCamera>;

  /**
   * Screen pixels per game pixel for camera x/y offsets (the editor's preview is shown smaller).
   */
  var ?cameraOffsetScale:Float;
}

/**
 * Modchart data helpers: the catalog of every modchart feature, target names, sampling and loading.
 */
class QOLModchart
{
  public static final VERSION:String = '1.0.0';

  public static final LANE_NAMES:Array<String> = ['Left', 'Down', 'Up', 'Right'];

  static final SL:Array<String> = ['strum', 'lane'];
  static final S:Array<String> = ['strum'];

  /**
   * Every modchart feature.
   */
  public static final PROPS:Array<QOLModProp> = [
    // Strumlines & arrows: movement.
    p('x', 'X offset', 'Move', 0, 'add', -1500, 1500, 1, SL, 'Moves the arrows and their notes left or right (pixels).'),
    p('y', 'Y offset', 'Move', 0, 'add', -1000, 1000, 1, SL, 'Moves the arrows and their notes up or down (pixels).'),
    p('angle', 'Arrow angle', 'Move', 0, 'add', -1440, 1440, 1, SL, 'Rotates the arrows (receptors), in degrees.'),
    p('rotate', 'Field rotation', 'Move', 0, 'add', -1440, 1440, 1, S,
      'Rotates the whole strumline around its centre. Notes fly in from the rotated direction (90 = notes come from the side).'),
    p('spacing', 'Arrow spacing', 'Move', 1, 'mul', 0, 4, 0.05, S, 'Distance between the four arrows (1 = normal, 0 = all on top of each other).'),
    p('centered', 'Centered', 'Move', 0, 'add', -1, 2, 0.05, S, 'Slides the strumline to the middle of the screen (1 = middlescroll).'),
    p('invert', 'Invert', 'Lanes', 0, 'add', -1, 2, 0.05, SL, 'Swaps neighbouring lanes: left with down, up with right (1 = fully swapped).'),
    p('flip', 'Flip', 'Lanes', 0, 'add', -1, 2, 0.05, SL, 'Mirrors the lanes: left with right, down with up (1 = fully mirrored).'),
    p('tipsy', 'Tipsy', 'Waves', 0, 'add', -5, 5, 0.05, SL, 'Arrows and notes bob up and down.'),
    p('tipsySpeed', 'Tipsy speed', 'Waves', 1, 'param', -10, 10, 0.05, SL, 'How fast Tipsy bobs.'),
    p('drunk', 'Drunk', 'Waves', 0, 'add', -5, 5, 0.05, SL, 'Arrows and notes sway left and right in a wave.'),
    p('drunkSpeed', 'Drunk speed', 'Waves', 1, 'param', -10, 10, 0.05, SL, 'How fast Drunk sways.'),
    p('tornado', 'Tornado', 'Waves', 0, 'add', -5, 5, 0.05, SL, 'Notes swirl across the lanes as they approach.'),
    p('beat', 'Beat', 'Waves', 0, 'add', -5, 5, 0.05, SL, 'Arrows and notes bounce sideways on every beat.'),
    p('wave', 'Wave', 'Waves', 0, 'add', -5, 5, 0.05, SL, 'Notes speed up and slow down in waves as they scroll.'),
    p('bumpy', 'Bumpy', 'Waves', 0, 'add', -5, 5, 0.05, SL, 'Notes pulse bigger and smaller as they scroll.'),
    // Scrolling.
    p('reverse', 'Reverse', 'Scroll', 0, 'add', -1, 2, 0.05, SL, 'Flips the scroll direction (1 = downscroll on upscroll). 0.5 squashes the notes onto the arrows.'),
    p('speed', 'Scroll speed', 'Scroll', 1, 'mul', 0, 10, 0.05, SL, 'Multiplies the scroll speed (only how fast notes look, not when to hit them).'),
    p('boost', 'Boost', 'Scroll', 0, 'add', -0.9, 5, 0.05, SL, 'Notes accelerate as they approach the arrows.'),
    p('brake', 'Brake', 'Scroll', 0, 'add', -0.9, 5, 0.05, SL, 'Notes slow down as they approach the arrows.'),
    // Visibility.
    p('alpha', 'Opacity', 'Look', 1, 'mul', 0, 1, 0.05, SL, 'Opacity of the arrows and their notes.'),
    p('scale', 'Size', 'Look', 1, 'mul', 0, 4, 0.05, SL, 'Size of the arrows and their notes.'),
    p('dark', 'Dark', 'Look', 0, 'add', 0, 1, 0.05, SL, 'Fades out the arrows only (the notes stay).'),
    p('stealth', 'Stealth', 'Look', 0, 'add', 0, 1, 0.05, SL, 'Fades out the notes only (the arrows stay).'),
    p('hidden', 'Hidden', 'Look', 0, 'add', 0, 1, 0.05, SL, 'Notes vanish as they get close to the arrows.'),
    p('hiddenOffset', 'Hidden offset', 'Look', 0, 'param', -720, 720, 5, SL, 'Where Hidden starts fading (pixels from the arrows).'),
    p('sudden', 'Sudden', 'Look', 0, 'add', 0, 1, 0.05, SL, 'Notes only appear when they get close to the arrows.'),
    p('suddenOffset', 'Sudden offset', 'Look', 0, 'param', -720, 720, 5, SL, 'Where Sudden notes appear (pixels from the arrows).'),
    // Spin.
    p('confusion', 'Confusion', 'Spin', 0, 'add', -1440, 1440, 1, SL, 'Rotates the notes, in degrees.'),
    p('dizzy', 'Dizzy', 'Spin', 0, 'add', -10, 10, 0.05, SL, 'Notes spin as they scroll.'),
    // HUD objects, characters and stage props.
    p('x', 'X offset', 'Object', 0, 'add', -2000, 2000, 1, ['object'], 'Moves it left or right (pixels).'),
    p('y', 'Y offset', 'Object', 0, 'add', -2000, 2000, 1, ['object'], 'Moves it up or down (pixels).'),
    p('angle', 'Angle', 'Object', 0, 'add', -1440, 1440, 1, ['object'], 'Rotates it, in degrees.'),
    p('alpha', 'Opacity', 'Object', 1, 'mul', 0, 1, 0.05, ['object'], 'How visible it is (0 = invisible).'),
    p('scale', 'Size', 'Object', 1, 'mul', 0, 5, 0.05, ['object'], 'Multiplies its size.'),
    // Cameras.
    p('x', 'X offset', 'Camera', 0, 'add', -2000, 2000, 1, ['camera'], 'Slides the whole camera view left or right (pixels).'),
    p('y', 'Y offset', 'Camera', 0, 'add', -2000, 2000, 1, ['camera'], 'Slides the whole camera view up or down (pixels).'),
    p('zoom', 'Zoom', 'Camera', 0, 'add', -5, 5, 0.01, ['camera'], 'Added to the camera zoom (0.1 = 10% closer). Works on top of camera bops.'),
    p('angle', 'Angle', 'Camera', 0, 'add', -1440, 1440, 1, ['camera'], 'Tilts the camera, in degrees.'),
    p('alpha', 'Opacity', 'Camera', 1, 'mul', 0, 1, 0.05, ['camera'], 'Fades everything the camera shows.'),
  ];

  static function p(id:String, name:String, group:String, neutral:Float, combine:String, min:Float, max:Float, step:Float, kinds:Array<String>,
      desc:String):QOLModProp
  {
    return {
      id: id,
      name: name,
      group: group,
      neutral: neutral,
      combine: combine,
      min: min,
      max: max,
      step: step,
      kinds: kinds,
      desc: desc
    };
  }

  /**
   * The properties a kind of target has.
   */
  public static function propsFor(kind:String):Array<QOLModProp>
    return [for (prop in PROPS) if (prop.kinds.contains(kind)) prop];

  public static function getProp(id:String, kind:String):Null<QOLModProp>
  {
    for (prop in PROPS)
      if (prop.id == id && prop.kinds.contains(kind)) return prop;
    for (prop in PROPS)
      if (prop.id == id) return prop;
    return null;
  }

  public static function neutralOf(target:String, prop:String):Float
    return getProp(prop, targetKind(target))?.neutral ?? 0;

  /**
   * `strum`, `lane`, `camera` or `object`.
   */
  public static function targetKind(target:String):String
  {
    if (target == 'camGame' || target == 'camHUD') return 'camera';
    if (target.startsWith('strum:')) return target.split(':').length >= 3 ? 'lane' : 'strum';
    return 'object';
  }

  public static function strumIndexOf(target:String):Int
    return Std.parseInt(target.split(':')[1]) ?? 0;

  public static function laneIndexOf(target:String):Int
    return Std.parseInt(target.split(':')[2] ?? '0') ?? 0;

  public static function strumName(index:Int):String
  {
    return switch (index)
    {
      case 0: 'Player';
      case 1: 'Opponent';
      default: 'Strumline ${index + 1}';
    }
  }

  /**
   * A readable name for a target.
   */
  public static function targetName(target:String):String
  {
    return switch (targetKind(target))
    {
      case 'camera': target == 'camGame' ? 'Game camera' : 'HUD camera';
      case 'strum': '${strumName(strumIndexOf(target))} strumline';
      case 'lane': '${strumName(strumIndexOf(target))} · ${LANE_NAMES[laneIndexOf(target) % 4]} arrow';
      default:
        switch (target)
        {
          case 'healthBar': 'Health bar';
          case 'iconP1': 'Player icon';
          case 'iconP2': 'Opponent icon';
          case 'scoreText': 'Score text';
          case 'char:bf': 'Boyfriend (player)';
          case 'char:dad': 'Opponent (dad)';
          case 'char:gf': 'Girlfriend';
          default: target.startsWith('prop:') ? 'Prop: ${target.substr(5)}' : target;
        }
    };
  }

  /**
   * Value of a track at a time (in beats). Before the first key the first value holds, after the last key the last one holds.
   */
  public static function sample(track:QOLModTrack, beat:Float, neutral:Float):Float
  {
    var keys = track.keys;
    if (keys == null || keys.length == 0) return neutral;
    if (beat <= keys[0].t) return keys[0].v;
    var last = keys[keys.length - 1];
    if (beat >= last.t) return last.v;
    var lo = 0;
    var hi = keys.length - 1;
    while (hi - lo > 1)
    {
      var mid = (lo + hi) >> 1;
      if (keys[mid].t <= beat) lo = mid;
      else
        hi = mid;
    }
    var a = keys[lo];
    var b = keys[hi];
    if (b.e == 'INSTANT' || b.t <= a.t) return a.v;
    var r = (beat - a.t) / (b.t - a.t);
    return a.v + (b.v - a.v) * QOLEase.get(b.e)(r);
  }

  public static function empty(?songId:String):QOLModchartData
    return {version: VERSION, song: songId, tracks: []};

  /**
   * Sort keys and fill in missing fields.
   */
  public static function normalize(data:QOLModchartData):QOLModchartData
  {
    if (data.version == null) data.version = VERSION;
    if (data.tracks == null) data.tracks = [];
    for (t in data.tracks)
    {
      if (t.keys == null) t.keys = [];
      sortKeys(t);
    }
    return data;
  }

  public static function sortKeys(track:QOLModTrack):Void
    track.keys.sort((a, b) -> a.t < b.t ? -1 : (a.t > b.t ? 1 : 0));

  /**
   * File name (without `.json`) for a song + variation.
   */
  public static function fileId(songId:String, ?variation:String):String
    return (variation == null || variation == '' || variation == Constants.DEFAULT_VARIATION) ? songId : '$songId-$variation';

  /**
   * Load a song's modchart (variation-specific first, then the song's).
   */
  public static function load(songId:Null<String>, ?variation:String):Null<QOLModchartData>
  {
    if (songId == null) return null;
    var ids = [fileId(songId, variation)];
    if (!ids.contains(songId)) ids.push(songId);
    for (id in ids)
    {
      try
      {
        var path = Paths.json('qol/modcharts/$id');
        if (Assets.exists(path))
        {
          var parsed:QOLModchartData = QOLJson.tryParse(Assets.getText(path));
          if (parsed != null) return normalize(parsed);
        }
      }
      catch (e) {}
    }
    return null;
  }
}

/**
 * Per-arrow modifier values for one frame.
 */
@:allow(funkin.qol.runtime.QOLModchartRuntime)
private class LaneMods
{
  public var x:Float = 0;
  public var y:Float = 0;
  public var angle:Float = 0;
  public var rotate:Float = 0;
  public var spacing:Float = 1;
  public var centered:Float = 0;
  public var invert:Float = 0;
  public var flip:Float = 0;
  public var tipsy:Float = 0;
  public var tipsySpeed:Float = 1;
  public var drunk:Float = 0;
  public var drunkSpeed:Float = 1;
  public var tornado:Float = 0;
  public var beat:Float = 0;
  public var wave:Float = 0;
  public var bumpy:Float = 0;
  public var reverse:Float = 0;
  public var speed:Float = 1;
  public var boost:Float = 0;
  public var brake:Float = 0;
  public var alpha:Float = 1;
  public var scale:Float = 1;
  public var dark:Float = 0;
  public var stealth:Float = 0;
  public var hidden:Float = 0;
  public var hiddenOffset:Float = 0;
  public var sudden:Float = 0;
  public var suddenOffset:Float = 0;
  public var confusion:Float = 0;
  public var dizzy:Float = 0;

  // Computed each frame.
  public var dx:Float = 0;
  public var dy:Float = 0;
  public var dirSign:Float = 1;
  public var rotCos:Float = 1;
  public var rotSin:Float = 0;
  public var pathX0:Float = 0;

  public function new() {}

  public function reset():Void
  {
    x = y = angle = rotate = centered = invert = flip = tipsy = drunk = tornado = beat = wave = bumpy = 0;
    reverse = boost = brake = dark = stealth = hidden = hiddenOffset = sudden = suddenOffset = confusion = dizzy = 0;
    spacing = tipsySpeed = drunkSpeed = speed = alpha = scale = 1;
  }

  /**
   * Combine a value in. `lane` = the value comes from the arrow's own track (vs. the whole strumline's).
   */
  public function set(id:String, v:Float, lane:Bool):Void
  {
    switch (id)
    {
      case 'x': x += v;
      case 'y': y += v;
      case 'angle': angle += v;
      case 'rotate': rotate += v;
      case 'spacing': spacing *= v;
      case 'centered': centered += v;
      case 'invert': invert += v;
      case 'flip': flip += v;
      case 'tipsy': tipsy += v;
      case 'tipsySpeed': tipsySpeed = v;
      case 'drunk': drunk += v;
      case 'drunkSpeed': drunkSpeed = v;
      case 'tornado': tornado += v;
      case 'beat': beat += v;
      case 'wave': wave += v;
      case 'bumpy': bumpy += v;
      case 'reverse': reverse += v;
      case 'speed': speed *= v;
      case 'boost': boost += v;
      case 'brake': brake += v;
      case 'alpha': alpha *= v;
      case 'scale': scale *= v;
      case 'dark': dark += v;
      case 'stealth': stealth += v;
      case 'hidden': hidden += v;
      case 'hiddenOffset': hiddenOffset = v;
      case 'sudden': sudden += v;
      case 'suddenOffset': suddenOffset = v;
      case 'confusion': confusion += v;
      case 'dizzy': dizzy += v;
      default:
    }
  }
}

private typedef LedgerEntry =
{
  var o:Dynamic;
  var f:Int;
  var base:Float;
  var applied:Float;
}

/**
 * Plays a modchart: every frame it samples all tracks and applies them to the strumlines, notes (including bending hold
 * trails), HUD objects, characters, stage props and cameras.
 *
 * Values the game itself animates (camera bops, icons following the health bar...) are handled by restoring them before
 * the game updates (`preUpdate`) and re-applying after (`update`), so modchart offsets never drift.
 */
@:access(funkin.play.notes.Strumline)
@:access(funkin.play.notes.SustainTrail)
class QOLModchartRuntime
{
  static inline final F_X:Int = 0;
  static inline final F_Y:Int = 1;
  static inline final F_ANGLE:Int = 2;
  static inline final F_ALPHA:Int = 3;
  static inline final F_SX:Int = 4;
  static inline final F_SY:Int = 5;
  static inline final F_ZOOM:Int = 6;

  static inline final BOOST_RANGE:Float = 600;
  static inline final HOLD_SEGMENT:Float = 16;

  public var data(default, null):QOLModchartData;

  var host:QOLModHost;
  var tracks:Array<QOLModTrack> = [];
  var values:Map<String, Map<String, Float>> = [];
  var modded:Map<Int, Bool> = [];
  var lanes:Map<Int, Array<LaneMods>> = [];
  var ledger:Array<LedgerEntry> = [];

  var vbuf:Array<Float> = [];
  var ubuf:Array<Float> = [];
  var ibuf:Array<Int> = [];

  public function new(data:QOLModchartData, host:QOLModHost)
  {
    this.host = host;
    setData(data);
  }

  /**
   * Swap in new data (the editor calls this after every change).
   */
  public function setData(data:QOLModchartData):Void
  {
    this.data = data;
    tracks = [];
    values.clear();
    var want = new Map<Int, Bool>();
    for (t in data.tracks)
    {
      if (t.muted == true || t.keys == null || t.keys.length == 0) continue;
      tracks.push(t);
      var kind = QOLModchart.targetKind(t.target);
      if (kind == 'strum' || kind == 'lane') want.set(QOLModchart.strumIndexOf(t.target), true);
    }
    for (s in modded.keys())
      if (!want.exists(s)) releaseStrumline(s);
    modded = want;
  }

  /**
   * Call before the game updates: puts back everything the modchart changed last frame.
   */
  public function preUpdate():Void
  {
    var i = ledger.length - 1;
    while (i >= 0)
    {
      var e = ledger[i];
      if (alive(e.o) && getF(e.o, e.f) == e.applied) setF(e.o, e.f, e.base);
      i--;
    }
    ledger.resize(0);
  }

  /**
   * Call after the game (and the strumlines) updated.
   * @param beat Song time in beats.
   */
  public function update(beat:Float):Void
  {
    // Sample every track.
    for (t in tracks)
    {
      var m = values.get(t.target);
      if (m == null)
      {
        m = new Map<String, Float>();
        values.set(t.target, m);
      }
      m.set(t.prop, QOLModchart.sample(t, beat, QOLModchart.neutralOf(t.target, t.prop)));
    }

    for (target => props in values)
    {
      switch (QOLModchart.targetKind(target))
      {
        case 'camera':
          var cam = host.cameras.get(target);
          if (cam != null) applyCamera(cam, props);
        case 'object':
          var objs = host.objects(target);
          if (objs != null) for (o in objs)
            if (o != null) applyObject(o, props);
        default:
      }
    }

    for (s in modded.keys())
    {
      var strum = host.strumlines.get(s);
      if (strum != null && strum.exists) applyStrumline(s, strum, beat);
    }
  }

  /**
   * Restore everything and hand the strumlines back to the game.
   */
  public function destroy():Void
  {
    preUpdate();
    for (s in modded.keys())
      releaseStrumline(s);
    modded.clear();
  }

  //
  // Objects & cameras
  //

  function applyObject(o:FlxObject, props:Map<String, Float>):Void
  {
    for (k => v in props)
    {
      switch (k)
      {
        case 'x': if (v != 0) add(o, F_X, v);
        case 'y': if (v != 0) add(o, F_Y, v);
        case 'angle': if (v != 0) add(o, F_ANGLE, v);
        case 'alpha': if (v != 1) mul(o, F_ALPHA, v);
        case 'scale':
          if (v != 1)
          {
            mul(o, F_SX, v);
            mul(o, F_SY, v);
          }
        default:
      }
    }
  }

  function applyCamera(cam:FlxCamera, props:Map<String, Float>):Void
  {
    var s = host.cameraOffsetScale ?? 1.0;
    for (k => v in props)
    {
      switch (k)
      {
        case 'x': if (v != 0) add(cam, F_X, v * s);
        case 'y': if (v != 0) add(cam, F_Y, v * s);
        case 'zoom': if (v != 0) add(cam, F_ZOOM, v);
        case 'angle': if (v != 0) add(cam, F_ANGLE, v);
        case 'alpha': if (v != 1) mul(cam, F_ALPHA, v);
        default:
      }
    }
  }

  //
  // Strumlines
  //

  function laneMods(s:Int):Array<LaneMods>
  {
    var arr = lanes.get(s);
    if (arr == null)
    {
      arr = [for (_ in 0...Strumline.KEY_COUNT) new LaneMods()];
      lanes.set(s, arr);
    }
    return arr;
  }

  function applyStrumline(s:Int, strum:Strumline, beat:Float):Void
  {
    strum.customPositionData = true;
    var mods = laneMods(s);
    var sv = values.get('strum:$s');
    for (i in 0...mods.length)
    {
      var m = mods[i];
      m.reset();
      if (sv != null) for (k => v in sv)
        m.set(k, v, false);
      var lv = values.get('strum:$s:$i');
      if (lv != null) for (k => v in lv)
        m.set(k, v, true);
    }

    var sc:Float = strum.strumlineScale.x;
    var size:Float = Strumline.STRUMLINE_SIZE * sc;
    var spacingPx:Float = Strumline.NOTE_SPACING * sc * strum.noteSpacingScale;
    var offs = strum.noteStyle.getStrumlineOffsets();
    var io:Float = Strumline.INITIAL_OFFSET;
    var baseDir:Float = strum.isDownscroll ? -1 : 1;
    var cx:Float = strum.x + (strum.getXPos(Strumline.DIRECTIONS[0]) + strum.getXPos(Strumline.DIRECTIONS[3])) / 2 + io + offs[0] + size / 2;
    var cy:Float = strum.y + offs[1] + size / 2;

    // Receptors.
    for (i in 0...mods.length)
    {
      var m = mods[i];
      var bx = strum.x + strum.getXPos(Strumline.DIRECTIONS[i]) + io + offs[0] + size / 2;
      var by = strum.y + offs[1] + size / 2;
      var px = cx + (bx - cx) * m.spacing;
      var py = by;
      px += m.invert * ((i % 2 == 0) ? 1 : -1) * spacingPx;
      px += m.flip * (3 - 2 * i) * spacingPx;
      var shift = m.centered * (FlxG.width / 2 - cx);
      px += shift;
      var rad = m.rotate * Math.PI / 180;
      m.rotCos = Math.cos(rad);
      m.rotSin = Math.sin(rad);
      if (m.rotate != 0)
      {
        var ox = px - (cx + shift);
        var oy = py - cy;
        px = cx + shift + ox * m.rotCos - oy * m.rotSin;
        py = cy + ox * m.rotSin + oy * m.rotCos;
      }
      if (m.reverse != 0) py = py + (FlxG.height - 2 * py) * m.reverse;
      m.pathX0 = pathX(m, 0, beat, i, size, spacingPx);
      px += m.x + m.pathX0;
      py += m.y;
      if (m.tipsy != 0) py += m.tipsy * size * 0.4 * Math.cos(beat * Math.PI * 0.6 * m.tipsySpeed + i * 1.8);
      m.dx = px - bx;
      m.dy = py - by;
      m.dirSign = baseDir * (1 - 2 * m.reverse);

      var r = strum.getByIndex(i);
      if (r == null) continue;
      if (m.dx != 0) add(r, F_X, m.dx);
      if (m.dy != 0) add(r, F_Y, m.dy);
      var ang = m.angle + m.rotate;
      if (ang != 0) add(r, F_ANGLE, ang);
      var a = m.alpha * (1 - m.dark);
      if (a != 1) mul(r, F_ALPHA, a);
      if (m.scale != 1)
      {
        mul(r, F_SX, m.scale);
        mul(r, F_SY, m.scale);
      }
    }

    // Notes.
    var conductor = strum.conductorInUse;
    var songPos = conductor.getTimeWithDelta();
    for (note in strum.notes.members)
    {
      if (note == null || !note.alive) continue;
      var i = note.direction % Strumline.KEY_COUNT;
      var m = mods[i];
      var d = GRhythmUtil.getNoteY(note.strumTime, strum.scrollSpeed, strum.isDownscroll, conductor) * baseDir;
      var dm = modDist(m, d, size);
      var xo = pathX(m, dm, beat, i, size, spacingPx) - m.pathX0;
      var along = dm * m.dirSign + note.yOffset;
      var vx = xo * m.rotCos - along * m.rotSin;
      var vy = xo * m.rotSin + along * m.rotCos;
      note.x = strum.x + strum.getXPos(Strumline.DIRECTIONS[i]) - (note.width - Strumline.STRUMLINE_SIZE) / 2 - Strumline.NUDGE + m.dx + vx;
      note.y = strum.y - io + m.dy + vy;

      var ang = m.confusion + m.rotate + m.dizzy * (dm / size) * 30;
      if (ang != 0) add(note, F_ANGLE, ang);
      var a = m.alpha * (1 - m.stealth) * visibility(m, d);
      if (a != 1) mul(note, F_ALPHA, a);
      var ns = m.scale * (m.bumpy != 0 ? 1 + m.bumpy * 0.3 * Math.sin(dm / (size * 0.6)) : 1);
      if (ns != 1)
      {
        mul(note, F_SX, ns);
        mul(note, F_SY, ns);
      }

      // Missed notes may never leave the screen when the field is moved around; clean them up.
      if (note.handledMiss && songPos - note.strumTime > 1500) strum.killNote(note);
    }

    // Hold notes (bent along the same path as the notes).
    for (hold in strum.holdNotes.members)
    {
      if (hold == null || !hold.alive) continue;
      renderHold(strum, hold, mods[hold.noteDirection % Strumline.KEY_COUNT], hold.noteDirection % Strumline.KEY_COUNT, beat, size, spacingPx, io,
        baseDir, songPos);
    }

    // Splashes and hold covers follow their arrow.
    for (splash in strum.noteSplashes.members)
    {
      if (splash == null || !splash.alive) continue;
      var m = mods[splash.direction % Strumline.KEY_COUNT];
      if (m.dx != 0) add(splash, F_X, m.dx);
      if (m.dy != 0) add(splash, F_Y, m.dy);
      if (m.alpha != 1) mul(splash, F_ALPHA, m.alpha);
    }
    for (cover in strum.noteHoldCovers.members)
    {
      if (cover == null || !cover.alive || cover.holdNote == null) continue;
      var m = mods[cover.holdNote.noteDirection % Strumline.KEY_COUNT];
      if (m.dx != 0) add(cover, F_X, m.dx);
      if (m.dy != 0) add(cover, F_Y, m.dy);
      if (m.alpha != 1) mul(cover, F_ALPHA, m.alpha);
    }
  }

  /**
   * Distance along the scroll after speed / boost / brake / wave (`d` = pixels until the note reaches the arrow).
   */
  inline function modDist(m:LaneMods, d:Float, size:Float):Float
  {
    var r = d * m.speed;
    if (m.boost != 0 && r > 0) r = BOOST_RANGE * Math.pow(r / BOOST_RANGE, 1 / (1 + Math.max(-0.9, m.boost)));
    if (m.brake != 0 && r > 0) r = BOOST_RANGE * Math.pow(r / BOOST_RANGE, 1 + Math.max(-0.9, m.brake));
    if (m.wave != 0) r += m.wave * size * 0.4 * Math.sin(r / (size * 0.6));
    return r;
  }

  /**
   * Sideways offset along the note path (drunk, tornado, beat).
   */
  function pathX(m:LaneMods, d:Float, beat:Float, lane:Int, size:Float, spacingPx:Float):Float
  {
    var x = 0.0;
    if (m.drunk != 0) x += m.drunk * size * 0.5 * Math.cos(beat * Math.PI * 0.5 * m.drunkSpeed + lane * 0.2 + d * 10 / 720);
    if (m.tornado != 0)
    {
      var pos = lane / (Strumline.KEY_COUNT - 1) * 2 - 1;
      var rads = Math.acos(pos) + d * 6 / 720;
      x += (Math.cos(rads) - pos) * 1.5 * spacingPx * m.tornado;
    }
    if (m.beat != 0)
    {
      var whole = Math.floor(beat);
      var phase = beat - whole;
      var amount = phase < 0.15 ? phase / 0.15 : Math.max(0, 1 - (phase - 0.15) / 0.5);
      amount *= amount;
      var sign = (whole % 2 == 0) ? 1 : -1;
      x += m.beat * size * 0.4 * amount * sign * Math.cos(d / (size * 0.5));
    }
    return x;
  }

  inline function visibility(m:LaneMods, d:Float):Float
  {
    var a = 1.0;
    if (m.hidden != 0)
    {
      var f = Math.min(1, Math.max(0, (d - (120 + m.hiddenOffset)) / 150));
      a *= 1 - m.hidden * (1 - f);
    }
    if (m.sudden != 0)
    {
      var f = Math.min(1, Math.max(0, ((420 + m.suddenOffset) - d) / 150));
      a *= 1 - m.sudden * (1 - f);
    }
    return Math.max(0, a);
  }

  /**
   * Draw a hold trail as a strip that follows the (possibly curved) note path.
   */
  function renderHold(strum:Strumline, hold:SustainTrail, m:LaneMods, lane:Int, beat:Float, size:Float, spacingPx:Float, io:Float, baseDir:Float,
      songPos:Float):Void
  {
    hold.customVertexData = true;
    if (!hold.visible || hold.graphic == null) return;

    var ppms = Constants.PIXELS_PER_MS * strum.scrollSpeed;
    var tEnd = hold.strumTime + hold.fullSustainLength;
    var tHead = hold.strumTime;
    if (hold.hitNote && !hold.missedNote && songPos > hold.strumTime) tHead = songPos;
    else if (hold.missedNote && hold.fullSustainLength > hold.sustainLength) tHead = tEnd - hold.sustainLength;
    var clipLen = ppms * (tEnd - tHead);
    if (clipLen <= 0.1)
    {
      hold.visible = false;
      return;
    }

    var gh = hold.graphic.height * hold.zoom;
    var bottomHeight = gh * hold.endOffset;
    var partHeight = clipLen - bottomHeight;
    var capEnd = clipLen + gh * (hold.bottomClip - hold.endOffset);
    var halfW = hold.graphicWidth * m.scale / 2;

    hold.x = strum.x + strum.getXPos(Strumline.DIRECTIONS[lane]) + Strumline.STRUMLINE_SIZE / 2;
    hold.y = strum.y;
    var ax = hold.x - hold.offset.x;
    var ay = hold.y - hold.offset.y;
    var cx0 = ax + hold.graphicWidth / 2 + m.dx;
    var cy0 = strum.y - io + Strumline.STRUMLINE_SIZE / 2 - hold.offset.y + m.dy;

    var u0 = 1 / 4 * (hold.noteDirection % 4);
    var u1 = u0 + 1 / 8;

    vbuf.resize(0);
    ubuf.resize(0);
    ibuf.resize(0);

    // Position of the trail's centre line `u` pixels (straight) after its head.
    inline function pointX(u:Float):Float
    {
      var t = tHead + u / ppms;
      var dm = modDist(m, ppms * (t - songPos), size);
      var xo = pathX(m, dm, beat, lane, size, spacingPx) - m.pathX0;
      var along = dm * m.dirSign + hold.yOffset;
      return cx0 + xo * m.rotCos - along * m.rotSin;
    }
    inline function pointY(u:Float):Float
    {
      var t = tHead + u / ppms;
      var dm = modDist(m, ppms * (t - songPos), size);
      var xo = pathX(m, dm, beat, lane, size, spacingPx) - m.pathX0;
      var along = dm * m.dirSign + hold.yOffset;
      return cy0 + xo * m.rotSin + along * m.rotCos;
    }
    function pushEdge(u:Float, uvL:Float, uvR:Float, v:Float):Void
    {
      var px = pointX(u);
      var py = pointY(u);
      var tx = pointX(u + 2) - pointX(u - 2);
      var ty = pointY(u + 2) - pointY(u - 2);
      var len = Math.sqrt(tx * tx + ty * ty);
      if (len < 0.0001)
      {
        // The trail is squashed to a point (e.g. reverse 0.5): use the field's sideways axis.
        tx = -m.rotSin * m.dirSign;
        ty = m.rotCos * m.dirSign;
        len = 1;
        if (m.dirSign == 0) ty = 1;
      }
      var nx = -ty / len * halfW;
      var ny = tx / len * halfW;
      vbuf.push(px + nx - ax);
      vbuf.push(py + ny - ay);
      vbuf.push(px - nx - ax);
      vbuf.push(py - ny - ay);
      ubuf.push(uvL);
      ubuf.push(v);
      ubuf.push(uvR);
      ubuf.push(v);
    }

    if (partHeight > 0)
    {
      var n = Std.int(Math.min(64, Math.max(1, Math.ceil(partHeight / HOLD_SEGMENT))));
      for (k in 0...n + 1)
      {
        var u = partHeight * k / n;
        pushEdge(u, u0, u1, -(partHeight - u) / gh);
      }
      for (k in 0...n)
      {
        var a = k * 2;
        ibuf.push(a);
        ibuf.push(a + 1);
        ibuf.push(a + 2);
        ibuf.push(a + 1);
        ibuf.push(a + 2);
        ibuf.push(a + 3);
      }
    }

    // End cap.
    var capBase = Std.int(vbuf.length / 2);
    var capStart = Math.max(0, partHeight);
    pushEdge(capStart, u1, u1 + 1 / 8, partHeight > 0 ? 0 : (bottomHeight - clipLen) / gh);
    pushEdge(capEnd, u1, u1 + 1 / 8, hold.bottomClip);
    ibuf.push(capBase);
    ibuf.push(capBase + 1);
    ibuf.push(capBase + 2);
    ibuf.push(capBase + 1);
    ibuf.push(capBase + 2);
    ibuf.push(capBase + 3);

    hold.setVertices(vbuf);
    hold.setUVTData(ubuf);
    hold.setIndices(ibuf);

    var dHead = ppms * (tHead - songPos);
    var a = m.alpha * (1 - m.stealth) * visibility(m, dHead);
    if (a != 1) mul(hold, F_ALPHA, a);
  }

  function releaseStrumline(s:Int):Void
  {
    var strum = host.strumlines.get(s);
    if (strum == null || !strum.exists) return;
    strum.customPositionData = false;
    for (hold in strum.holdNotes.members)
    {
      if (hold == null || !hold.customVertexData) continue;
      hold.customVertexData = false;
      hold.setVertices([for (_ in 0...16) 0.0]);
      hold.setUVTData([for (_ in 0...16) 0.0]);
      hold.setIndices(SustainTrail.TRIANGLE_VERTEX_INDICES);
      hold.triggerRedraw();
    }
  }

  //
  // Ledger: remembers what was changed so it can be put back next frame.
  //

  function add(o:Dynamic, f:Int, delta:Float):Void
  {
    var base = getF(o, f);
    setF(o, f, base + delta);
    ledger.push({o: o, f: f, base: base, applied: getF(o, f)});
  }

  function mul(o:Dynamic, f:Int, factor:Float):Void
  {
    var base = getF(o, f);
    setF(o, f, base * factor);
    ledger.push({o: o, f: f, base: base, applied: getF(o, f)});
  }

  static function alive(o:Dynamic):Bool
  {
    if (o == null) return false;
    if (Std.isOfType(o, FlxSprite)) return (o : FlxSprite).scale != null;
    return true;
  }

  static function getF(o:Dynamic, f:Int):Float
  {
    if (Std.isOfType(o, FlxCamera))
    {
      var c:FlxCamera = cast o;
      return switch (f)
      {
        case F_X: c.x;
        case F_Y: c.y;
        case F_ANGLE: c.angle;
        case F_ALPHA: c.alpha;
        case F_ZOOM: c.zoom;
        default: 0;
      }
    }
    var obj:FlxObject = cast o;
    switch (f)
    {
      case F_X:
        return obj.x;
      case F_Y:
        return obj.y;
      case F_ANGLE:
        return obj.angle;
      default:
    }
    if (!Std.isOfType(o, FlxSprite)) return f == F_ALPHA || f == F_SX || f == F_SY ? 1 : 0;
    var spr:FlxSprite = cast o;
    return switch (f)
    {
      case F_ALPHA: spr.alpha;
      case F_SX: spr.scale.x;
      case F_SY: spr.scale.y;
      default: 0;
    }
  }

  static function setF(o:Dynamic, f:Int, v:Float):Void
  {
    if (Std.isOfType(o, FlxCamera))
    {
      var c:FlxCamera = cast o;
      switch (f)
      {
        case F_X: c.x = v;
        case F_Y: c.y = v;
        case F_ANGLE: c.angle = v;
        case F_ALPHA: c.alpha = v;
        case F_ZOOM: c.zoom = v;
        default:
      }
      return;
    }
    var obj:FlxObject = cast o;
    switch (f)
    {
      case F_X:
        obj.x = v;
        return;
      case F_Y:
        obj.y = v;
        return;
      case F_ANGLE:
        obj.angle = v;
        return;
      default:
    }
    if (!Std.isOfType(o, FlxSprite)) return;
    var spr:FlxSprite = cast o;
    switch (f)
    {
      case F_ALPHA: spr.alpha = v;
      case F_SX: spr.scale.x = v;
      case F_SY: spr.scale.y = v;
      default:
    }
  }
}
