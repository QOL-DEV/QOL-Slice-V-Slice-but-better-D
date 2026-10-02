package funkin.qol.editors.modchart;

#if FEATURE_HAXEUI
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.graphics.frames.FlxBitmapFont;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.text.FlxBitmapText;
import flixel.ui.FlxBar;
import flixel.util.FlxColor;
import funkin.data.character.CharacterData.CharacterDataParser;
import funkin.data.notestyle.NoteStyleRegistry;
import funkin.data.song.SongData.SongNoteData;
import funkin.data.stage.StageRegistry;
import funkin.graphics.FunkinCamera;
import funkin.graphics.FunkinSprite;
import funkin.modding.events.ScriptEvent;
import funkin.modding.events.ScriptEventDispatcher;
import funkin.play.character.BaseCharacter;
import funkin.play.components.HealthIcon;
import funkin.play.notes.NoteDirection;
import funkin.play.notes.Strumline;
import funkin.play.song.Song;
import funkin.play.song.Song.SongDifficulty;
import funkin.play.stage.Bopper;
import funkin.play.stage.Stage;
import funkin.qol.runtime.QOLModchart;
import funkin.qol.runtime.QOLModchart.QOLModchartData;
import funkin.qol.runtime.QOLModchart.QOLModchartRuntime;
import funkin.qol.runtime.QOLModchart.QOLModHost;
import funkin.qol.runtime.QOLModchart.QOLModKey;
import funkin.qol.runtime.QOLModchart.QOLModTrack;
import funkin.qol.runtime.QOLPlayHooks;
import funkin.qol.runtime.QOLPlayHooks.QOLStrumlineData;
import funkin.modding.events.ScriptEvent.SongTimeScriptEvent;
import funkin.play.character.BaseCharacter.CharacterType;
import funkin.qol.ui.QOLTheme;
import funkin.qol.util.QOLAssets;

/**
 * A scaled-down, live copy of gameplay for the Modchart Editor: the real stage and characters, the real strumlines with
 * the song's notes (played by the CPU), and the HUD. The modchart runtime animates it exactly like it animates gameplay.
 */
class ModchartPreview
{
  /**
   * Where the 1280x720 "screen" is drawn, and how big.
   */
  public var x:Float;

  public var y:Float;
  public var scale:Float;

  public var camGame:FunkinCamera;
  public var camHUD:FlxCamera;

  var display:funkin.qol.ui.QOLScaledCameras;

  public var stage:Null<Stage> = null;
  public var stageZoom:Float = 1.0;
  public var cameraFocus:FlxPoint = FlxPoint.get(FlxG.width / 2, FlxG.height / 2);

  public var strumlines:Map<Int, Strumline> = new Map<Int, Strumline>();
  public var strumNotes:Map<Int, Array<SongNoteData>> = new Map<Int, Array<SongNoteData>>();

  public var healthBarBG:Null<FunkinSprite> = null;
  public var healthBar:Null<FlxBar> = null;
  public var iconP1:Null<HealthIcon> = null;
  public var iconP2:Null<HealthIcon> = null;
  public var scoreText:Null<FlxBitmapText> = null;
  var noStageBG:Null<FunkinSprite> = null;

  /**
   * Everything the modchart runtime can animate.
   */
  public var host:QOLModHost;

  var state:FlxState;
  var added:Array<FlxBasic> = [];
  var lastSongPos:Float = -1;
  var lastStep:Int = -1;
  var chars:Map<Int, Null<BaseCharacter>> = new Map<Int, Null<BaseCharacter>>();
  var buildToken:Int = 0;

  public function new(state:FlxState, x:Float, y:Float, scale:Float)
  {
    this.state = state;
    this.x = x;
    this.y = y;
    this.scale = scale;

    // Full-size 1280x720 cameras shrunk into the preview box (see QOLScaledCameras).
    camGame = new FunkinCamera('qolModchartGame', 0, 0, FlxG.width, FlxG.height);
    camGame.bgColor = 0xFF000000;
    camHUD = new FlxCamera(0, 0, FlxG.width, FlxG.height);
    camHUD.bgColor.alpha = 0;
    display = new funkin.qol.ui.QOLScaledCameras([camGame, camHUD], x, y, scale);
    place();

    host = {
      strumlines: strumlines,
      objects: objectsFor,
      cameras: ['camGame' => camGame, 'camHUD' => camHUD],
      cameraOffsetScale: scale
    };
  }

  /**
   * Position the preview cameras (call every frame before the modchart applies camera offsets).
   */
  public function place():Void
  {
    camGame.x = camHUD.x = 0;
    camGame.y = camHUD.y = 0;
    camGame.zoom = stageZoom;
    camHUD.zoom = 1;
    camGame.focusOn(cameraFocus);
  }

  //
  // Building
  //

  /**
   * Build the preview for a song difficulty.
   * @param extras QOL settings for extra strumlines.
   * @param onReady Called when the stage is ready (web builds load stage assets first).
   */
  public function build(song:Song, diff:SongDifficulty, showStage:Bool, extras:Array<QOLStrumlineData>, ?onReady:Void->Void):Void
  {
    clear();
    var token = ++buildToken;
    buildHUD(diff);
    buildStrumlines(diff, extras);
    if (showStage)
    {
      var stageData = StageRegistry.instance.fetchEntry(diff.stage);
      @:privateAccess var lib = stageData?._data?.directory;
      QOLAssets.withLibrary(lib, () -> {
        if (token != buildToken) return;
        buildStage(diff);
        if (onReady != null) onReady();
      });
    }
    else
    {
      buildNoStage();
      if (onReady != null) onReady();
    }
  }

  function addToState(obj:FlxBasic, cam:FlxCamera, ?atStart:Bool = false):Void
  {
    obj.cameras = [cam];
    if (atStart) state.insert(0, obj);
    else
      state.add(obj);
    added.push(obj);
  }

  function buildNoStage():Void
  {
    noStageBG = FunkinSprite.create(0, 0, 'menuDesat');
    noStageBG.setGraphicSize(FlxG.width, FlxG.height);
    noStageBG.updateHitbox();
    noStageBG.color = 0xFF3A3352;
    noStageBG.scrollFactor.set();
    addToState(noStageBG, camGame, true);
    stageZoom = 1;
    cameraFocus.set(FlxG.width / 2, FlxG.height / 2);
  }

  function buildStage(diff:SongDifficulty):Void
  {
    try
    {
      stage = StageRegistry.instance.fetchEntry(diff.stage);
      if (stage == null)
      {
        buildNoStage();
        return;
      }
      stage.revive();
      ScriptEventDispatcher.callEvent(stage, new ScriptEvent(CREATE, false));
      var chars = diff.characters;
      this.chars.clear();
      for (pair in [
        {id: chars?.girlfriend, type: GF, slot: 2},
        {id: chars?.player, type: BF, slot: 0},
        {id: chars?.opponent, type: DAD, slot: 1}
      ])
      {
        if (pair.id == null || pair.id == '') continue;
        var c = CharacterDataParser.fetchCharacter(pair.id);
        if (c == null) continue;
        stage.addCharacter(c, pair.type);
        this.chars.set(pair.slot, c);
      }
      stage.refresh();
      addToState(stage, camGame, true);
      stage.cameras = [camGame];
      stageZoom = stage.camZoom;
      var bf = stage.getBoyfriend();
      var dad = stage.getDad();
      if (bf != null && dad != null) cameraFocus.set((bf.cameraFocusPoint.x + dad.cameraFocusPoint.x) / 2,
        (bf.cameraFocusPoint.y + dad.cameraFocusPoint.y) / 2);
      else if (bf != null) cameraFocus.copyFrom(bf.cameraFocusPoint);
    }
    catch (e)
    {
      trace('[QOL] Modchart preview stage failed: $e');
      stage = null;
      buildNoStage();
    }
  }

  function buildHUD(diff:SongDifficulty):Void
  {
    var downscroll = Preferences.downscroll;
    healthBarBG = FunkinSprite.create(0, 0, 'healthBar');
    healthBarBG.y = downscroll ? FlxG.height * 0.1 : FlxG.height * 0.9;
    healthBarBG.screenCenter(X);
    healthBarBG.scrollFactor.set();
    addToState(healthBarBG, camHUD);

    healthBar = new FlxBar(healthBarBG.x + 4, healthBarBG.y + 4, RIGHT_TO_LEFT, Std.int(healthBarBG.width - 8), Std.int(healthBarBG.height - 8), null, '',
      0, 2);
    var chars = diff.characters;
    var dadData = chars != null ? CharacterDataParser.fetchCharacterData(chars.opponent) : null;
    var bfData = chars != null ? CharacterDataParser.fetchCharacterData(chars.player) : null;
    healthBar.createFilledBar(colorOf(dadData, Constants.COLOR_HEALTH_BAR_RED), colorOf(bfData, Constants.COLOR_HEALTH_BAR_GREEN));
    healthBar.value = 1;
    healthBar.scrollFactor.set();
    addToState(healthBar, camHUD);

    var center = healthBar.x + healthBar.width / 2;
    iconP2 = chars != null ? QOLTheme.healthIcon(chars.opponent, 150) : null;
    if (iconP2 != null)
    {
      iconP2.x = center - (iconP2.width - 26);
      iconP2.y = healthBar.y - iconP2.height / 2;
      addToState(iconP2, camHUD);
    }
    iconP1 = chars != null ? QOLTheme.healthIcon(chars.player, 150, true) : null;
    if (iconP1 != null)
    {
      iconP1.x = center - 26;
      iconP1.y = healthBar.y - iconP1.height / 2;
      addToState(iconP1, camHUD);
    }

    scoreText = new FlxBitmapText(0, 0, 'Score: 0', FlxBitmapFont.fromAngelCode(Paths.font('vcr-bmp.png'), Paths.font('vcr-bmp.fnt')));
    scoreText.x = healthBarBG.x + healthBarBG.width - 190;
    scoreText.y = healthBarBG.y + 30;
    scoreText.alignment = RIGHT;
    scoreText.borderStyle = OUTLINE;
    scoreText.borderColor = FlxColor.BLACK;
    scoreText.letterSpacing = -1;
    scoreText.scrollFactor.set();
    addToState(scoreText, camHUD);
  }

  static function colorOf(data:Dynamic, fallback:FlxColor):FlxColor
  {
    try
    {
      var qol:Dynamic = data != null ? Reflect.field(data, 'qol') : null;
      var c:Dynamic = qol != null ? Reflect.field(qol, 'healthBarColor') : null;
      if (c != null)
      {
        var parsed = FlxColor.fromString(Std.string(c));
        if (parsed != null) return parsed;
      }
    }
    catch (e) {}
    return fallback;
  }

  function buildStrumlines(diff:SongDifficulty, extras:Array<QOLStrumlineData>):Void
  {
    var style = NoteStyleRegistry.instance.fetchEntry(diff.noteStyle) ?? NoteStyleRegistry.instance.fetchDefault();
    var speed = diff.scrollSpeed;
    var lists = new Map<Int, Array<SongNoteData>>();
    for (n in diff.notes)
    {
      var s = n.getStrumlineIndex();
      var list = lists.get(s);
      if (list == null)
      {
        list = [];
        lists.set(s, list);
      }
      list.push(s < 2 ? n : new SongNoteData(n.time, n.getDirection(), n.length, n.kind));
    }

    var downscroll = Preferences.downscroll;
    var player = new Strumline(style, false, speed);
    player.x = FlxG.width / 2 + Constants.STRUMLINE_X_OFFSET;
    player.y = downscroll ? FlxG.height - player.height - Constants.STRUMLINE_Y_OFFSET - style.getStrumlineOffsets()[1] : Constants.STRUMLINE_Y_OFFSET;
    var opponent = new Strumline(style, false, speed);
    opponent.x = Constants.STRUMLINE_X_OFFSET;
    opponent.y = downscroll ? FlxG.height - opponent.height - Constants.STRUMLINE_Y_OFFSET - style.getStrumlineOffsets()[1] : Constants.STRUMLINE_Y_OFFSET;
    strumlines.set(0, player);
    strumlines.set(1, opponent);

    // Extra strumlines: every configured one, plus any that has notes.
    var extraData = new Map<Int, QOLStrumlineData>();
    for (e in extras)
      if (e.index >= 2) extraData.set(e.index, e);
    for (s in lists.keys())
      if (s >= 2 && !extraData.exists(s)) extraData.set(s, {index: s, character: s == 2 ? 'gf' : 'dad'});
    var order = [for (k in extraData.keys()) k];
    order.sort((a, b) -> a - b);
    for (i in 0...order.length)
      strumlines.set(order[i], QOLPlayHooks.buildExtraStrumline(style, extraData.get(order[i]), i, order.length, speed));

    for (s => strum in strumlines)
    {
      addToState(strum, camHUD);
      var notes = lists.get(s) ?? [];
      strumNotes.set(s, notes);
      strum.applyNoteData(notes);
    }
    lastSongPos = -1;
  }

  /**
   * Remove everything from the scene.
   */
  public function clear():Void
  {
    for (obj in added)
    {
      state.remove(obj, true);
      if (obj != stage) obj.destroy();
    }
    added = [];
    if (stage != null)
    {
      // The stage is shared (cached by the registry): don't let it keep our camera for whoever uses it next.
      stage.cameras = null;
      try
      {
        ScriptEventDispatcher.callEvent(stage, new ScriptEvent(DESTROY, false));
      }
      catch (e) {}
      stage = null;
    }
    chars.clear();
    strumlines.clear();
    strumNotes.clear();
    healthBarBG = null;
    healthBar = null;
    iconP1 = iconP2 = null;
    scoreText = null;
    noStageBG = null;
  }

  public function destroy():Void
  {
    display.destroy();
    clear();
    cameraFocus.put();
  }

  //
  // Playback
  //

  /**
   * Call every frame after Conductor.instance was updated to `songPos`.
   */
  public function update(songPos:Float):Void
  {
    // Seeking: rebuild the notes from the new position.
    if (lastSongPos < 0 || songPos < lastSongPos - 5 || songPos > lastSongPos + 750) resetNotes();
    lastSongPos = songPos;

    // The CPU plays every strumline.
    for (s => strum in strumlines)
    {
      for (note in strum.notes.members)
      {
        if (note == null || !note.alive || note.hasBeenHit) continue;
        if (note.strumTime > songPos) continue;
        var dir:NoteDirection = note.direction;
        strum.hitNote(note);
        if (note.holdNoteSprite != null) strum.playNoteHoldCover(note.holdNoteSprite);
        sing(s, dir);
      }
    }

    // Characters and props bop to the music.
    var step = Std.int(Math.floor(Conductor.instance.currentStepTime));
    if (step != lastStep && step >= 0)
    {
      lastStep = step;
      if (stage != null)
      {
        var event = new SongTimeScriptEvent(SONG_STEP_HIT, Std.int(step / Constants.STEPS_PER_BEAT), step);
        @:privateAccess
        for (b in stage.boppers)
          if (b != null && b.alive) try
            b.onStepHit(event)
          catch (e) {}
        @:privateAccess
        for (c in stage.characters)
          if (c != null && c.alive) try
            c.onStepHit(event)
          catch (e) {}
      }
    }
  }

  function sing(strum:Int, dir:NoteDirection):Void
  {
    var c = chars.get(strum);
    if (c == null) return;
    try
    {
      c.playSingAnimation(dir, false);
      c.holdTimer = 0;
    }
    catch (e) {}
  }

  function resetNotes():Void
  {
    for (s => strum in strumlines)
    {
      strum.clean();
      strum.applyNoteData(strumNotes.get(s) ?? []);
    }
  }

  //
  // Targets
  //

  function objectsFor(target:String):Null<Array<FlxObject>>
  {
    return switch (target)
    {
      case 'healthBar': [healthBarBG, healthBar];
      case 'iconP1': [iconP1];
      case 'iconP2': [iconP2];
      case 'scoreText': [scoreText];
      case 'char:bf': [stage?.getBoyfriend()];
      case 'char:dad': [stage?.getDad()];
      case 'char:gf': [stage?.getGirlfriend()];
      default: target.startsWith('prop:') ? [stage?.getNamedProp(target.substr(5))] : null;
    }
  }

  /**
   * Every target the preview has, grouped for the timeline.
   */
  public function targetGroups():Array<{name:String, targets:Array<String>}>
  {
    var strums = [for (k in strumlines.keys()) k];
    strums.sort((a, b) -> {
      // Opponent first, then player, then extras (like the screen).
      var oa = a == 1 ? -1 : a;
      var ob = b == 1 ? -1 : b;
      return oa - ob;
    });
    var props:Array<String> = [];
    if (stage != null)
    {
      @:privateAccess
      for (name in stage.namedProps.keys())
        props.push('prop:$name');
      props.sort((a, b) -> a < b ? -1 : 1);
    }
    return [
      {name: 'Strumlines', targets: [for (s in strums) 'strum:$s']},
      {name: 'Cameras', targets: ['camGame', 'camHUD']},
      {name: 'HUD', targets: ['healthBar', 'iconP1', 'iconP2', 'scoreText']},
      {name: 'Characters', targets: ['char:dad', 'char:bf', 'char:gf']},
      {name: 'Stage props', targets: props}
    ];
  }

  //
  // Coordinates
  //

  /**
   * The game camera's zoom as the game would see it (the preview's display shrink removed).
   */
  public var gameZoom(get, never):Float;

  function get_gameZoom():Float
    return camGame.zoom;

  /**
   * Screen position → HUD ("1280x720 screen") position.
   */
  public function screenToHud(sx:Float, sy:Float):FlxPoint
    return FlxPoint.get((sx - x) / scale, (sy - y) / scale);

  public function hudToScreen(hx:Float, hy:Float):FlxPoint
    return FlxPoint.get(x + hx * scale, y + hy * scale);

  /**
   * HUD position → world (stage) position, through the game camera.
   */
  public function hudToWorld(hx:Float, hy:Float):FlxPoint
  {
    var z = gameZoom;
    return FlxPoint.get(camGame.scroll.x + (hx - FlxG.width * (1 - z) / 2) / z, camGame.scroll.y + (hy - FlxG.height * (1 - z) / 2) / z);
  }

  public function worldToHud(wx:Float, wy:Float):FlxPoint
  {
    var z = gameZoom;
    return FlxPoint.get((wx - camGame.scroll.x) * z + FlxG.width * (1 - z) / 2, (wy - camGame.scroll.y) * z + FlxG.height * (1 - z) / 2);
  }

  public function inside(sx:Float, sy:Float):Bool
    return sx >= x && sy >= y && sx < x + FlxG.width * scale && sy < y + FlxG.height * scale;

  /**
   * Bounds of a target in HUD coordinates (null if it isn't on screen).
   */
  public function boundsOf(target:String):Null<FlxRect>
  {
    switch (QOLModchart.targetKind(target))
    {
      case 'strum' | 'lane':
        var strum = strumlines.get(QOLModchart.strumIndexOf(target));
        if (strum == null) return null;
        var lanes = QOLModchart.targetKind(target) == 'lane' ? [QOLModchart.laneIndexOf(target)] : [0, 1, 2, 3];
        var r:Null<FlxRect> = null;
        for (i in lanes)
        {
          var n = strum.getByIndex(i);
          if (n == null) continue;
          var b = FlxRect.get(n.x, n.y, n.width, n.height);
          if (r == null) r = b;
          else
          {
            r = r.union(b);
            b.put();
          }
        }
        return r;
      case 'camera':
        return FlxRect.get(0, 0, FlxG.width, FlxG.height);
      default:
        var objs = objectsFor(target);
        if (objs == null) return null;
        var world = target.startsWith('char:') || target.startsWith('prop:');
        var r:Null<FlxRect> = null;
        for (o in objs)
        {
          if (o == null || !o.exists) continue;
          var b:FlxRect;
          if (world)
          {
            var p1 = worldToHud(o.x, o.y);
            var p2 = worldToHud(o.x + o.width, o.y + o.height);
            b = FlxRect.get(p1.x, p1.y, p2.x - p1.x, p2.y - p1.y);
            p1.put();
            p2.put();
          }
          else
            b = FlxRect.get(o.x, o.y, o.width, o.height);
          if (r == null) r = b;
          else
          {
            r = r.union(b);
            b.put();
          }
        }
        return r;
    }
  }

  /**
   * What is under a HUD position. `lanes` = pick single arrows instead of whole strumlines.
   */
  public function hitTest(hx:Float, hy:Float, lanes:Bool):Null<String>
  {
    for (s => strum in strumlines)
    {
      for (i in 0...Strumline.KEY_COUNT)
      {
        var n = strum.getByIndex(i);
        if (n == null || !n.visible) continue;
        if (hx >= n.x && hx < n.x + n.width && hy >= n.y && hy < n.y + n.height) return lanes ? 'strum:$s:$i' : 'strum:$s';
      }
    }
    for (target in ['iconP1', 'iconP2', 'scoreText', 'healthBar'])
    {
      var b = boundsOf(target);
      if (b == null) continue;
      var hit = b.containsXY(hx, hy);
      b.put();
      if (hit) return target;
    }
    for (target in ['char:bf', 'char:dad', 'char:gf'])
    {
      var b = boundsOf(target);
      if (b == null) continue;
      var hit = b.containsXY(hx, hy);
      b.put();
      if (hit) return target;
    }
    return null;
  }
}
#end
