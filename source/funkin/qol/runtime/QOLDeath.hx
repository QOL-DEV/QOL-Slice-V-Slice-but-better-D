package funkin.qol.runtime;

import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import funkin.audio.FunkinSound;
import funkin.play.character.BaseCharacter;
import funkin.qol.util.QOLEase;
import funkin.qol.util.QOLJson;

/**
 * A custom game over sequence, made with the Death Animation Editor.
 *
 * Stored in `data/qol/deaths/<character id>.json` (or `default.json` to apply to every character).
 */
typedef QOLDeathData =
{
  var ?version:String;

  /**
   * Animation names (defaults: firstDeath / deathLoop / deathConfirm).
   */
  var ?firstAnim:String;

  var ?loopAnim:String;
  var ?confirmAnim:String;

  /**
   * Sound played when you die, and the looping / retry music (asset keys, e.g. `gameplay/gameover/fnf_loss_sfx`).
   */
  var ?startSound:String;

  var ?music:String;
  var ?endMusic:String;
  var ?musicVolume:Float;

  var ?bgColor:String;
  var ?bgAlpha:Float;
  var ?hideCharacter:Bool;

  /**
   * Camera offset (added to the character's death camera offset), zoom multiplier and follow speed.
   */
  var ?cameraOffsets:Array<Float>;

  var ?cameraZoom:Float;
  var ?cameraSpeed:Float;

  /**
   * How the screen fades out after pressing retry.
   */
  var ?retryFadeColor:String;

  var ?retryFadeTime:Float;
  var ?retryDelay:Float;

  var ?overlays:Array<QOLDeathOverlay>;
  var ?actions:Array<QOLDeathAction>;
}

typedef QOLDeathOverlay =
{
  var id:String;

  /**
   * `image`, `animated`, `text` or `solid`.
   */
  var type:String;

  var ?image:String;
  var ?anim:String;
  var ?fps:Int;
  var ?loop:Bool;
  var ?text:String;
  var ?font:String;
  var ?size:Int;
  var ?color:String;
  var ?outline:Bool;
  var ?width:Int;
  var ?height:Int;
  var x:Float;
  var y:Float;
  var ?scale:Float;
  var ?alpha:Float;
  var ?angle:Float;
  var ?visible:Bool;
  var ?blend:String;
  var ?antialiasing:Bool;
}

typedef QOLDeathAction =
{
  /**
   * Seconds after the trigger.
   */
  var time:Float;

  /**
   * `start` (when you die), `loop` (when the loop animation begins) or `retry` (when you press retry).
   */
  var ?trigger:String;

  /**
   * `tween`, `show`, `hide`, `playAnim`, `sound`, `flash`, `shake`, `zoom`.
   */
  var type:String;

  /**
   * An overlay ID, `character` or `camera`.
   */
  var ?target:String;

  var ?x:Null<Float>;
  var ?y:Null<Float>;
  var ?alpha:Null<Float>;
  var ?angle:Null<Float>;
  var ?scale:Null<Float>;
  var ?duration:Float;
  var ?ease:String;
  var ?sound:String;
  var ?volume:Float;
  var ?anim:String;
  var ?color:String;
  var ?intensity:Float;
  var ?zoom:Float;
}

/**
 * Plays a custom death sequence. Used by the real game over screen AND by the editor preview,
 * so what you see in the editor is exactly what happens in game.
 */
class QOLDeath
{
  public static final ACTION_TYPES:Array<String> = ['tween', 'show', 'hide', 'playAnim', 'sound', 'flash', 'shake', 'zoom'];
  public static final TRIGGERS:Array<String> = ['start', 'loop', 'retry'];
  public static final OVERLAY_TYPES:Array<String> = ['image', 'animated', 'text', 'solid'];

  /**
   * Load the death sequence for a character, falling back to `default.json`. Returns null if there's none.
   */
  public static function load(charId:Null<String>):Null<QOLDeathData>
  {
    for (id in [charId, 'default'])
    {
      if (id == null) continue;
      try
      {
        var path = Paths.json('qol/deaths/$id');
        if (Assets.exists(path))
        {
          var parsed:QOLDeathData = QOLJson.tryParse(Assets.getText(path));
          if (parsed != null) return parsed;
        }
      }
      catch (e) {}
    }
    return null;
  }

  public static function defaults():QOLDeathData
  {
    return {
      version: '1.0.0',
      firstAnim: 'firstDeath',
      loopAnim: 'deathLoop',
      confirmAnim: 'deathConfirm',
      startSound: 'gameplay/gameover/fnf_loss_sfx',
      music: 'gameplay/gameover/gameOver',
      endMusic: 'gameplay/gameover/gameOverEnd',
      musicVolume: 1,
      bgColor: '#000000',
      bgAlpha: 1,
      hideCharacter: false,
      cameraOffsets: [0, 0],
      cameraZoom: 1,
      cameraSpeed: 1,
      retryFadeColor: '#000000',
      retryFadeTime: 2,
      retryDelay: 0.7,
      overlays: [],
      actions: []
    };
  }

  public var data:QOLDeathData;
  public var character:Null<BaseCharacter>;
  public var overlayCamera:FlxCamera;
  public var gameCamera:FlxCamera;
  public var overlays:FlxTypedGroup<FlxSprite>;
  public var overlayMap:Map<String, FlxSprite> = new Map<String, FlxSprite>();

  /**
   * Zoom multiplier set by `zoom` actions (the game over screen multiplies its target zoom by this).
   */
  public var zoomMultiplier:Float = 1;

  var ownsCamera:Bool = false;
  var timers:Map<String, Float> = new Map<String, Float>();
  var fired:Map<String, Array<Bool>> = new Map<String, Array<Bool>>();
  var tweens:Array<FlxTween> = [];

  /**
   * @param overlayCamera Camera for the overlays. If null, a new transparent camera is added on top.
   */
  public function new(data:QOLDeathData, character:Null<BaseCharacter>, gameCamera:FlxCamera, ?overlayCamera:FlxCamera)
  {
    this.data = data;
    this.character = character;
    this.gameCamera = gameCamera;
    if (overlayCamera == null)
    {
      overlayCamera = new FlxCamera();
      overlayCamera.bgColor = FlxColor.TRANSPARENT;
      FlxG.cameras.add(overlayCamera, false);
      ownsCamera = true;
    }
    this.overlayCamera = overlayCamera;
    overlays = new FlxTypedGroup<FlxSprite>();
    for (o in data.overlays ?? [])
    {
      var spr = buildOverlay(o);
      if (spr == null) continue;
      spr.cameras = [overlayCamera];
      overlays.add(spr);
      overlayMap.set(o.id, spr);
    }
    if (character != null && data.hideCharacter == true) character.visible = false;
  }

  public static function colorOf(hex:Null<String>, def:FlxColor):FlxColor
  {
    if (hex == null) return def;
    var c = FlxColor.fromString(hex);
    return c == null ? def : c;
  }

  public static function buildOverlay(o:QOLDeathOverlay):Null<FlxSprite>
  {
    var spr:FlxSprite;
    try
    {
      switch (o.type)
      {
        case 'text':
          var t = new FlxText(0, 0, 0, o.text ?? 'GAME OVER', o.size ?? 48);
          if (o.font != null && o.font != '') t.font = Paths.font(o.font);
          t.color = colorOf(o.color, FlxColor.WHITE);
          if (o.outline != false) t.setBorderStyle(OUTLINE, FlxColor.BLACK, Math.max(1, (o.size ?? 48) / 16));
          spr = t;
        case 'solid':
          spr = new FlxSprite().makeGraphic(o.width ?? 200, o.height ?? 100, FlxColor.WHITE);
          spr.color = colorOf(o.color, FlxColor.WHITE);
        case 'animated':
          spr = new FlxSprite();
          spr.frames = Paths.getSparrowAtlas(o.image ?? '');
          spr.animation.addByPrefix('anim', o.anim ?? '', o.fps ?? 24, o.loop ?? true);
          spr.animation.play('anim');
        default:
          spr = new FlxSprite().loadGraphic(Paths.image(o.image ?? ''));
      }
    }
    catch (e)
    {
      trace('[QOL] Death overlay "${o.id}" failed: $e');
      return null;
    }
    if (o.type != 'text' && o.type != 'solid' && o.color != null) spr.color = colorOf(o.color, FlxColor.WHITE);
    var s = o.scale ?? 1;
    spr.scale.set(s, s);
    spr.updateHitbox();
    spr.setPosition(o.x, o.y);
    spr.alpha = o.alpha ?? 1;
    spr.angle = o.angle ?? 0;
    spr.visible = o.visible ?? true;
    spr.antialiasing = o.antialiasing ?? true;
    spr.scrollFactor.set(0, 0);
    if (o.blend != null && o.blend != '' && o.blend != 'normal') spr.blend = cast o.blend;
    return spr;
  }

  public function firstAnim():String
    return nonEmpty(data.firstAnim, 'firstDeath');

  public function loopAnim():String
    return nonEmpty(data.loopAnim, 'deathLoop');

  public function confirmAnim():String
    return nonEmpty(data.confirmAnim, 'deathConfirm');

  static inline function nonEmpty(v:Null<String>, def:String):String
    return (v == null || v == '') ? def : v;

  /**
   * Start a trigger's timeline (`start`, `loop` or `retry`).
   */
  public function trigger(name:String):Void
  {
    timers.set(name, 0);
    fired.set(name, []);
    // Run actions at time 0 right away.
    update(0);
  }

  public function update(elapsed:Float):Void
  {
    var actions = data.actions ?? [];
    for (name => t in timers)
    {
      var newT = t + elapsed;
      timers.set(name, newT);
      var done = fired.get(name);
      for (i in 0...actions.length)
      {
        var a = actions[i];
        if ((a.trigger ?? 'start') != name || done[i] == true) continue;
        if (a.time <= newT)
        {
          done[i] = true;
          runAction(a);
        }
      }
    }
  }

  function targetOf(name:Null<String>):Null<flixel.FlxBasic>
  {
    if (name == null || name == '' || name == 'character') return character;
    if (name == 'camera') return gameCamera;
    return overlayMap.get(name);
  }

  public function runAction(a:QOLDeathAction):Void
  {
    try
    {
      switch (a.type)
      {
        case 'tween':
          var target = targetOf(a.target);
          if (target == null) return;
          var props:Dynamic = {};
          if (a.x != null) props.x = a.x;
          if (a.y != null) props.y = a.y;
          if (a.alpha != null) props.alpha = a.alpha;
          if (a.angle != null) props.angle = a.angle;
          var dur = Math.max(0.0001, a.duration ?? 1);
          var opts = {ease: QOLEase.get(a.ease)};
          if (Reflect.fields(props).length > 0) tweens.push(FlxTween.tween(target, props, dur, opts));
          if (a.scale != null && Std.isOfType(target, FlxSprite))
          {
            var spr:FlxSprite = cast target;
            tweens.push(FlxTween.tween(spr.scale, {x: a.scale, y: a.scale}, dur, opts));
          }
        case 'show':
          var target = targetOf(a.target);
          if (target != null) target.visible = true;
        case 'hide':
          var target = targetOf(a.target);
          if (target != null) target.visible = false;
        case 'playAnim':
          var target = targetOf(a.target);
          if (Std.isOfType(target, BaseCharacter)) (cast target : BaseCharacter).playAnimation(a.anim ?? '', true, true);
          else if (Std.isOfType(target, FlxSprite))
          {
            var spr:FlxSprite = cast target;
            if (a.anim != null && spr.animation.getByName(a.anim) == null) spr.animation.addByPrefix(a.anim, a.anim, 24, false);
            spr.animation.play(a.anim ?? 'anim', true);
          }
        case 'sound':
          if (a.sound != null && a.sound != '') FunkinSound.playOnce(Paths.sound(a.sound), a.volume ?? 1);
        case 'flash':
          (a.target == 'overlay' ? overlayCamera : gameCamera).flash(colorOf(a.color, FlxColor.WHITE), a.duration ?? 0.5, null, true);
        case 'shake':
          gameCamera.shake(a.intensity ?? 0.02, a.duration ?? 0.4);
        case 'zoom':
          var dur = Math.max(0.0001, a.duration ?? 1);
          tweens.push(FlxTween.num(zoomMultiplier, a.zoom ?? 1, dur, {ease: QOLEase.get(a.ease)}, v -> zoomMultiplier = v));
      }
    }
    catch (e)
    {
      trace('[QOL] Death action failed: $e');
    }
  }

  public function destroy():Void
  {
    for (t in tweens)
      if (t != null) t.cancel();
    tweens = [];
    if (ownsCamera && FlxG.cameras.list.contains(overlayCamera)) FlxG.cameras.remove(overlayCamera, true);
    overlays.destroy();
  }
}
