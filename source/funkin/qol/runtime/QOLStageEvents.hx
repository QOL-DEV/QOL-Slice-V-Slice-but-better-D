package funkin.qol.runtime;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import funkin.audio.FunkinSound;
import funkin.play.stage.Bopper;
import funkin.qol.util.QOLEase;
import funkin.qol.util.QOLJson;

/**
 * One step of a stage event: something that happens to a prop, character or camera at a time.
 */
typedef QOLStageEventStep =
{
  /**
   * When the step starts, in the event's time unit.
   */
  var time:Float;

  /**
   * `tween`, `set`, `tint`, `playAnim`, `show`, `hide`, `sound`, `flash`, `shake`, `zoom`.
   */
  var type:String;

  /**
   * A prop name, `bf`, `gf`, `dad`, `camera` or `hud`.
   */
  var ?target:String;

  /**
   * Property for tween/set: `x`, `y`, `alpha`, `angle`, `scale`, `scaleX`, `scaleY`.
   */
  var ?prop:String;

  var ?value:Float;

  /**
   * If true, `value` is added to the current value instead of replacing it.
   */
  var ?relative:Bool;

  var ?duration:Float;
  var ?ease:String;
  var ?anim:String;
  var ?sound:String;
  var ?volume:Float;
  var ?color:String;
  var ?intensity:Float;
}

/**
 * A named stage event, made in the Background Editor and triggered from charts with the "Stage Event" event.
 */
typedef QOLStageEvent =
{
  var id:String;
  var name:String;

  /**
   * `seconds`, `steps` or `beats`.
   */
  var ?timeUnit:String;

  var steps:Array<QOLStageEventStep>;
}

typedef QOLStageEventFile =
{
  var ?version:String;
  var events:Array<QOLStageEvent>;
}

/**
 * Loads and plays stage events.
 * Files live in `data/qol/stage-events/<stage id>.json`.
 */
class QOLStageEvents
{
  public static final STEP_TYPES:Array<String> = ['tween', 'set', 'tint', 'playAnim', 'show', 'hide', 'sound', 'flash', 'shake', 'zoom'];
  public static final STEP_TYPE_NAMES:Array<String> = [
    'Tween (smooth move)',
    'Set instantly',
    'Tint color',
    'Play animation',
    'Show',
    'Hide',
    'Play sound',
    'Camera flash',
    'Camera shake',
    'Camera zoom'
  ];
  public static final PROPS:Array<String> = ['x', 'y', 'alpha', 'angle', 'scale', 'scaleX', 'scaleY'];
  public static final TIME_UNITS:Array<String> = ['seconds', 'steps', 'beats'];

  public static function load(stageId:String):Null<QOLStageEventFile>
  {
    try
    {
      var path = Paths.json('qol/stage-events/$stageId');
      if (!Assets.exists(path)) return null;
      var parsed:QOLStageEventFile = QOLJson.tryParse(Assets.getText(path));
      if (parsed == null || parsed.events == null) return null;
      return parsed;
    }
    catch (e)
    {
      return null;
    }
  }

  public static function find(stageId:String, eventId:String):Null<QOLStageEvent>
  {
    var file = load(stageId);
    if (file == null) return null;
    for (e in file.events)
      if (e.id == eventId) return e;
    return null;
  }

  /**
   * Every stage event of every stage, as `stage/event` keys (for the chart editor).
   */
  public static function listAll():Array<{key:String, label:String}>
  {
    var result:Array<{key:String, label:String}> = [];
    for (stageId in funkin.data.stage.StageRegistry.instance.listEntryIds())
    {
      var file = load(stageId);
      if (file == null) continue;
      for (e in file.events)
        result.push({key: '$stageId/${e.id}', label: '$stageId: ${e.name}'});
    }
    result.sort((a, b) -> a.label < b.label ? -1 : 1);
    return result;
  }

  /**
   * Length of one time unit in seconds.
   */
  public static function unitSeconds(unit:Null<String>, stepLengthMs:Float):Float
  {
    return switch (unit)
    {
      case 'steps': stepLengthMs / 1000;
      case 'beats': stepLengthMs * 4 / 1000;
      default: 1;
    }
  }

  /**
   * Total length of an event in its own time unit.
   */
  public static function length(event:QOLStageEvent):Float
  {
    var end = 0.0;
    for (s in event.steps)
      end = Math.max(end, s.time + (s.duration ?? 0));
    return end;
  }
}

/**
 * Plays one stage event. Call `update` every frame (it pauses with the game when you stop calling it).
 */
class QOLStageEventPlayer
{
  public var event:QOLStageEvent;
  public var finished(default, null):Bool = false;

  var resolve:String->Null<FlxBasic>;
  var unit:Float;
  var time:Float = 0;
  var done:Array<Bool> = [];
  var tweens:Array<FlxTween> = [];
  var zoomHandler:Null<(Float, Float, Null<Float->Float>) -> Void>;

  /**
   * @param resolve Turns a target name into an object (prop, character, camera).
   * @param stepLengthMs Length of a step in milliseconds (for `steps`/`beats` units).
   * @param zoomHandler Called for `zoom` steps (zoom multiplier, duration in seconds, ease).
   */
  public function new(event:QOLStageEvent, resolve:String->Null<FlxBasic>, stepLengthMs:Float,
      ?zoomHandler:(Float, Float, Null<Float->Float>) -> Void)
  {
    this.event = event;
    this.resolve = resolve;
    this.unit = QOLStageEvents.unitSeconds(event.timeUnit, stepLengthMs);
    this.zoomHandler = zoomHandler;
    update(0);
  }

  public function update(elapsed:Float):Void
  {
    if (finished) return;
    time += elapsed;
    var pending = false;
    for (i in 0...event.steps.length)
    {
      if (done[i] == true) continue;
      var s = event.steps[i];
      if (s.time * unit <= time)
      {
        done[i] = true;
        run(s);
      }
      else
        pending = true;
    }
    if (!pending) finished = true;
  }

  public function cancel():Void
  {
    for (t in tweens)
      if (t != null) t.cancel();
    tweens = [];
    finished = true;
  }

  static function getProp(obj:Dynamic, prop:String):Float
  {
    return switch (prop)
    {
      case 'scale' | 'scaleX': obj.scale.x;
      case 'scaleY': obj.scale.y;
      default: Reflect.getProperty(obj, prop);
    }
  }

  function run(s:QOLStageEventStep):Void
  {
    try
    {
      var target:Null<FlxBasic> = resolve(s.target ?? '');
      var duration = Math.max(0.0001, (s.duration ?? 1) * unit);
      var ease = QOLEase.get(s.ease);
      switch (s.type)
      {
        case 'tween' | 'set':
          if (target == null) return;
          var prop = s.prop ?? 'x';
          var value = s.value ?? 0;
          if (s.relative == true) value += getProp(target, prop);
          if (s.type == 'set')
          {
            switch (prop)
            {
              case 'scale':
                (cast target : FlxSprite).scale.set(value, value);
              case 'scaleX':
                (cast target : FlxSprite).scale.x = value;
              case 'scaleY':
                (cast target : FlxSprite).scale.y = value;
              default:
                Reflect.setProperty(target, prop, value);
            }
            return;
          }
          switch (prop)
          {
            case 'scale':
              tweens.push(FlxTween.tween((cast target : FlxSprite).scale, {x: value, y: value}, duration, {ease: ease}));
            case 'scaleX':
              tweens.push(FlxTween.tween((cast target : FlxSprite).scale, {x: value}, duration, {ease: ease}));
            case 'scaleY':
              tweens.push(FlxTween.tween((cast target : FlxSprite).scale, {y: value}, duration, {ease: ease}));
            default:
              var props:Dynamic = {};
              Reflect.setField(props, prop, value);
              tweens.push(FlxTween.tween(target, props, duration, {ease: ease}));
          }
        case 'tint':
          if (!Std.isOfType(target, FlxSprite)) return;
          var spr:FlxSprite = cast target;
          var to = QOLDeath.colorOf(s.color, FlxColor.WHITE);
          tweens.push(FlxTween.color(spr, duration, spr.color, to, {ease: ease}));
        case 'playAnim':
          if (Std.isOfType(target, Bopper)) (cast target : Bopper).playAnimation(s.anim ?? 'idle', true);
          else if (Std.isOfType(target, FlxSprite)) (cast target : FlxSprite).animation.play(s.anim ?? 'idle', true);
        case 'show':
          if (target != null) target.visible = true;
        case 'hide':
          if (target != null) target.visible = false;
        case 'sound':
          if (s.sound != null && s.sound != '') FunkinSound.playOnce(Paths.sound(s.sound), s.volume ?? 1);
        case 'flash':
          var cam:FlxCamera = Std.isOfType(target, FlxCamera) ? cast target : FlxG.camera;
          cam.flash(QOLDeath.colorOf(s.color, FlxColor.WHITE), duration, null, true);
        case 'shake':
          var cam:FlxCamera = Std.isOfType(target, FlxCamera) ? cast target : FlxG.camera;
          cam.shake(s.intensity ?? 0.01, duration);
        case 'zoom':
          if (zoomHandler != null) zoomHandler(s.value ?? 1, duration, ease);
      }
    }
    catch (e)
    {
      trace('[QOL] Stage event step failed: $e');
    }
  }
}
