package funkin.qol.runtime;

import flixel.FlxBasic;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import funkin.data.character.CharacterData.CharacterDataParser;
import funkin.data.song.SongData.SongNoteData;
import funkin.data.stage.StageRegistry;
import funkin.modding.events.ScriptEvent;
import funkin.modding.events.ScriptEventDispatcher;
import funkin.play.PlayState;
import funkin.play.character.BaseCharacter;
import funkin.play.character.BaseCharacter.CharacterType;
import funkin.play.notes.NoteDirection;
import funkin.play.notes.Strumline;
import funkin.play.stage.Stage;
import funkin.qol.runtime.QOLModchart;
import funkin.qol.runtime.QOLModchart.QOLModchartData;
import funkin.qol.runtime.QOLModchart.QOLModchartRuntime;
import funkin.qol.runtime.QOLModchart.QOLModHost;
import funkin.qol.runtime.QOLModchart.QOLModKey;
import funkin.qol.runtime.QOLModchart.QOLModTrack;
import funkin.qol.runtime.QOLStageEvents;
import funkin.qol.util.QOLJson;
import funkin.util.GRhythmUtil;

/**
 * Settings for one extra strumline (a 3rd, 4th... lane of notes, e.g. for Girlfriend).
 */
typedef QOLStrumlineData =
{
  /**
   * Strumline index: notes with `data` 8-11 are strumline 2, 12-15 are strumline 3, and so on.
   */
  var index:Int;

  var ?name:String;

  /**
   * `bf`, `gf`, `dad`, or any character ID (spawned next to Girlfriend).
   */
  var ?character:String;

  var ?visible:Bool;
  var ?x:Null<Float>;
  var ?y:Null<Float>;
  var ?scale:Float;
  var ?alpha:Float;

  /**
   * Added to sing animations (e.g. `alt` plays `singLEFT-alt`).
   */
  var ?singSuffix:String;

  /**
   * Extra position offset for a spawned character.
   */
  var ?charOffset:Array<Float>;
}

/**
 * Per-song QOL Slice settings, made by the chart editor. `data/qol/songs/<song id>.json`.
 */
typedef QOLSongData =
{
  var ?version:String;
  var ?strumlines:Array<QOLStrumlineData>;
}

/**
 * QOL Slice's additions to gameplay, attached to the PlayState:
 * extra strumlines, stage events, stage and character swapping, and health bar colors.
 */
class QOLPlayHooks
{
  public static var instance(default, null):Null<QOLPlayHooks> = null;

  /**
   * Song settings to use instead of the saved file (set by the chart editor before a playtest).
   */
  public static var pendingSongData:Null<QOLSongData> = null;

  /**
   * Modchart to use instead of the saved file (set by the Modchart Editor before a playtest).
   */
  public static var pendingModchart:Null<QOLModchartData> = null;

  public var modchartData:Null<QOLModchartData> = null;
  public var modchart:Null<QOLModchartRuntime> = null;

  var modStrumlines:Map<Int, Strumline> = new Map<Int, Strumline>();

  public var ps:PlayState;
  public var songData:QOLSongData;
  public var extraStrumlines:Map<Int, Strumline> = new Map<Int, Strumline>();
  public var extraData:Map<Int, QOLStrumlineData> = new Map<Int, QOLStrumlineData>();
  public var extraCharacters:Map<Int, BaseCharacter> = new Map<Int, BaseCharacter>();

  var pendingNotes:Map<Int, Array<SongNoteData>> = new Map<Int, Array<SongNoteData>>();
  var stagePlayers:Array<QOLStageEventPlayer> = [];
  var cachedStages:Map<String, Stage> = new Map<String, Stage>();
  var cachedCharacters:Map<String, BaseCharacter> = new Map<String, BaseCharacter>();

  public function new(ps:PlayState)
  {
    this.ps = ps;
    instance = this;
    songData = pendingSongData ?? loadSongData(ps.currentChart?.song?.id);
    pendingSongData = null;
    for (sl in songData.strumlines ?? [])
      extraData.set(sl.index, sl);
    modchartData = pendingModchart ?? QOLModchart.load(ps.currentChart?.song?.id, ps.currentVariation);
    pendingModchart = null;
    applyHealthBarColors();
    precacheEvents();
  }

  //
  // Modcharts
  //

  /**
   * Called at the start of PlayState.update: undoes last frame's modchart changes so the game updates from clean values.
   */
  public function preUpdate():Void
  {
    modchart?.preUpdate();
  }

  function updateModchart():Void
  {
    if (modchartData == null || modchartData.tracks.length == 0) return;
    if (ps.playerStrumline == null || ps.opponentStrumline == null) return;
    modStrumlines.set(0, ps.playerStrumline);
    modStrumlines.set(1, ps.opponentStrumline);
    for (index => strum in extraStrumlines)
      modStrumlines.set(index, strum);
    if (modchart == null)
    {
      modchart = new QOLModchartRuntime(modchartData, {
        strumlines: modStrumlines,
        objects: modchartObjects,
        cameras: ['camGame' => ps.camGame, 'camHUD' => ps.camHUD]
      });
    }
    modchart.update(Conductor.instance.currentBeatTime);
  }

  @:access(funkin.play.PlayState)
  function modchartObjects(target:String):Null<Array<flixel.FlxObject>>
  {
    var stage = ps.currentStage;
    return switch (target)
    {
      case 'healthBar': [ps.healthBarBG, ps.healthBar];
      case 'iconP1': [ps.iconP1];
      case 'iconP2': [ps.iconP2];
      case 'scoreText': [ps.scoreText];
      case 'char:bf': [stage?.getBoyfriend()];
      case 'char:dad': [stage?.getDad()];
      case 'char:gf': [stage?.getGirlfriend()];
      default: target.startsWith('prop:') ? [stage?.getNamedProp(target.substr(5))] : null;
    }
  }

  public static function loadSongData(songId:Null<String>):QOLSongData
  {
    if (songId != null)
    {
      try
      {
        var path = Paths.json('qol/songs/$songId');
        if (Assets.exists(path))
        {
          var parsed:QOLSongData = QOLJson.tryParse(Assets.getText(path));
          if (parsed != null) return parsed;
        }
      }
      catch (e) {}
    }
    return {strumlines: []};
  }

  //
  // Health bar colors (set per character in the Character Editor)
  //

  public static function healthBarColorOf(char:Null<BaseCharacter>, fallback:FlxColor):FlxColor
  {
    if (char == null) return fallback;
    @:privateAccess var qol:Dynamic = Reflect.field(char._data, 'qol');
    var hex:Null<String> = qol?.healthBarColor;
    if (hex == null) return fallback;
    var c = FlxColor.fromString(hex);
    return c == null ? fallback : c;
  }

  public function applyHealthBarColors():Void
  {
    var stage = ps.currentStage;
    if (stage == null || ps.healthBar == null) return;
    var left = healthBarColorOf(stage.getDad(), Constants.COLOR_HEALTH_BAR_RED);
    var right = healthBarColorOf(stage.getBoyfriend(), Constants.COLOR_HEALTH_BAR_GREEN);
    ps.healthBar.createFilledBar(left, right);
    ps.healthBar.updateBar();
  }

  //
  // Extra strumlines
  //

  public function clearExtraNotes():Void
  {
    pendingNotes = new Map<Int, Array<SongNoteData>>();
  }

  public function queueExtraNote(note:SongNoteData):Void
  {
    var index = note.getStrumlineIndex();
    if (index < 2) return;
    if (!pendingNotes.exists(index)) pendingNotes.set(index, []);
    pendingNotes.get(index).push(note);
  }

  public function applyExtraNotes():Void
  {
    for (index => notes in pendingNotes)
    {
      var strum = getOrCreateStrumline(index);
      if (strum == null) continue;
      // Strumlines expect directions 0-3.
      var local:Array<SongNoteData> = [];
      for (n in notes)
      {
        var copy = new SongNoteData(n.time, n.getDirection(), n.length, n.kind);
        local.push(copy);
      }
      strum.applyNoteData(local);
    }
    for (index => strum in extraStrumlines)
      if (!pendingNotes.exists(index)) strum.applyNoteData([]);
  }

  function getOrCreateStrumline(index:Int):Null<Strumline>
  {
    if (extraStrumlines.exists(index)) return extraStrumlines.get(index);
    var data = extraData.get(index);
    if (data == null)
    {
      data = {index: index, character: index == 2 ? 'gf' : 'dad', scale: 0.45};
      extraData.set(index, data);
    }
    @:privateAccess var style = ps.noteStyle;
    var order = [for (k in extraData.keys()) k];
    order.sort((a, b) -> a - b);
    var strum = buildExtraStrumline(style, data, order.indexOf(index), order.length, ps.currentChart?.scrollSpeed);
    strum.zIndex = 999;
    strum.cameras = [ps.camHUD];
    ps.add(strum);
    strum.fadeInArrows();
    extraStrumlines.set(index, strum);
    setupCharacter(index, data);
    return strum;
  }

  /**
   * Builds and places an extra strumline (shared by gameplay and the editors' previews).
   * @param slot Position among the extra strumlines (0 = first).
   */
  public static function buildExtraStrumline(style:funkin.play.notes.notestyle.NoteStyle, data:QOLStrumlineData, slot:Int, count:Int,
      ?scrollSpeed:Float):Strumline
  {
    var strum = new Strumline(style, false, scrollSpeed);
    strum.visible = data.visible ?? true;
    strum.alpha = data.alpha ?? 1;
    var scale = data.scale ?? 0.45;
    if (scale != 1) strum.enterMiniMode(scale);
    var defaultX = (FlxG.width - strum.width) / 2 + (slot - (count - 1) / 2) * (strum.width + 40);
    strum.x = data.x ?? defaultX;
    var defaultY = Preferences.downscroll ? FlxG.height - strum.height - Constants.STRUMLINE_Y_OFFSET - 20 : Constants.STRUMLINE_Y_OFFSET + 20;
    strum.y = data.y ?? defaultY;
    return strum;
  }

  function setupCharacter(index:Int, data:QOLStrumlineData)
  {
    var id = data.character ?? 'gf';
    if (id == 'bf' || id == 'gf' || id == 'dad') return;
    var stage = ps.currentStage;
    if (stage == null) return;
    var c = CharacterDataParser.fetchCharacter(id);
    if (c == null) return;
    stage.addCharacter(c, OTHER);
    var gf = stage.getGirlfriend();
    var offset = data.charOffset ?? [0, 0];
    if (gf != null)
    {
      c.x = gf.x + offset[0];
      c.y = gf.y + offset[1];
      c.zIndex = gf.zIndex + 1;
    }
    stage.refresh();
    extraCharacters.set(index, c);
  }

  public function characterFor(index:Int):Null<BaseCharacter>
  {
    if (extraCharacters.exists(index)) return extraCharacters.get(index);
    var stage = ps.currentStage;
    if (stage == null) return null;
    return switch (extraData.get(index)?.character ?? 'gf')
    {
      case 'bf': stage.getBoyfriend();
      case 'dad': stage.getDad();
      default: stage.getGirlfriend();
    }
  }

  /**
   * CPU-plays every extra strumline (called from PlayState.processNotes).
   */
  public function processNotes(elapsed:Float):Void
  {
    for (index => strum in extraStrumlines)
    {
      if (strum.notes?.members == null) continue;
      var data = extraData.get(index);
      var suffix = data?.singSuffix ?? '';
      var singer = characterFor(index);
      for (note in strum.notes.members)
      {
        if (note == null || !note.alive) continue;
        var r = GRhythmUtil.processWindow(note, false);
        if (!r.botplayHit) continue;
        var dir:NoteDirection = note.direction;
        strum.hitNote(note);
        if (note.holdNoteSprite != null) strum.playNoteHoldCover(note.holdNoteSprite);
        if (singer != null)
        {
          singer.playSingAnimation(dir, false, suffix);
          singer.holdTimer = 0;
        }
      }
      for (hold in strum.holdNotes.members)
      {
        if (hold == null || !hold.alive) continue;
        if (hold.hitNote && !hold.missedNote && hold.sustainLength > 0 && singer != null && singer.isSinging()) singer.holdTimer = 0;
      }
    }
  }

  public function cleanStrumlines():Void
  {
    for (strum in extraStrumlines)
      strum.clean();
  }

  public function vwooshIn():Void
  {
    for (strum in extraStrumlines)
    {
      if (strum.notes.length == 0) strum.updateNotes();
      strum.vwooshInNotes();
    }
  }

  //
  // Stage events
  //

  public function runStageEvent(key:String):Void
  {
    var slash = key.indexOf('/');
    var stageId = slash > 0 ? key.substr(0, slash) : (ps.currentStage?.id ?? '');
    var eventId = slash > 0 ? key.substr(slash + 1) : key;
    var event = QOLStageEvents.find(stageId, eventId);
    if (event == null)
    {
      trace('[QOL] Stage event not found: $key');
      return;
    }
    stagePlayers.push(new QOLStageEventPlayer(event, resolveTarget, Conductor.instance.stepLengthMs, (zoom, duration, ease) -> {
      ps.tweenCameraZoom(zoom, duration, false, ease);
    }));
  }

  public function resolveTarget(name:String):Null<FlxBasic>
  {
    var stage = ps.currentStage;
    return switch (name)
    {
      case 'bf': stage?.getBoyfriend();
      case 'gf': stage?.getGirlfriend();
      case 'dad': stage?.getDad();
      case 'camera': ps.camGame;
      case 'hud': ps.camHUD;
      default: stage?.getNamedProp(name);
    }
  }

  public function update(elapsed:Float):Void
  {
    updateModchart();
    var i = stagePlayers.length - 1;
    while (i >= 0)
    {
      var p = stagePlayers[i];
      p.update(elapsed);
      if (p.finished) stagePlayers.splice(i, 1);
      i--;
    }
  }

  //
  // Swapping stages & characters mid-song
  //

  /**
   * Builds stages and characters used by Change Stage / Change Character events ahead of time,
   * so swapping during the song is instant.
   */
  function precacheEvents():Void
  {
    var events = ps.currentChart?.getEvents() ?? [];
    for (e in events)
    {
      try
      {
        switch (e.eventKind)
        {
          case 'ChangeStage':
            var id:Null<String> = e.getString('stage');
            if (id != null && !cachedStages.exists(id) && id != ps.currentStage?.id)
            {
              var stage = StageRegistry.instance.fetchEntry(id);
              if (stage != null)
              {
                stage.revive();
                ScriptEventDispatcher.callEvent(stage, new ScriptEvent(CREATE, false));
                cachedStages.set(id, stage);
              }
            }
          case 'ChangeCharacter':
            var id:Null<String> = e.getString('character');
            if (id != null && !cachedCharacters.exists(id))
            {
              var c = CharacterDataParser.fetchCharacter(id);
              if (c != null) cachedCharacters.set(id, c);
            }
        }
      }
      catch (err)
      {
        trace('[QOL] Precache failed: $err');
      }
    }
  }

  public function changeStage(id:String):Void
  {
    var old = ps.currentStage;
    if (old == null || old.id == id) return;
    var bf = old.getBoyfriend(true);
    var gf = old.getGirlfriend(true);
    var dad = old.getDad(true);
    var newStage = cachedStages.get(id);
    cachedStages.remove(id);
    if (newStage == null)
    {
      newStage = StageRegistry.instance.fetchEntry(id);
      if (newStage == null)
      {
        trace('[QOL] Change Stage: unknown stage $id');
        if (bf != null) old.addCharacter(bf, BF);
        if (gf != null) old.addCharacter(gf, GF);
        if (dad != null) old.addCharacter(dad, DAD);
        return;
      }
      newStage.revive();
      ScriptEventDispatcher.callEvent(newStage, new ScriptEvent(CREATE, false));
    }
    var index = ps.members.indexOf(old);
    ps.remove(old, true);
    old.kill();
    ps.currentStage = newStage;
    if (index >= 0) ps.insert(index, newStage);
    else
      ps.add(newStage);
    if (gf != null) newStage.addCharacter(gf, GF);
    if (bf != null) newStage.addCharacter(bf, BF);
    if (dad != null) newStage.addCharacter(dad, DAD);
    for (i => c in extraCharacters)
    {
      newStage.addCharacter(c, OTHER);
      var g = newStage.getGirlfriend();
      var offset = extraData.get(i)?.charOffset ?? [0, 0];
      if (g != null) c.setPosition(g.x + offset[0], g.y + offset[1]);
    }
    newStage.refresh();
    ps.resetCameraZoom();
    ScriptEventDispatcher.callEvent(newStage, new ScriptEvent(SONG_START, false));
  }

  public function changeCharacter(target:String, id:String):Void
  {
    var stage = ps.currentStage;
    if (stage == null) return;
    var type:CharacterType = switch (target)
    {
      case 'bf': BF;
      case 'gf': GF;
      default: DAD;
    };
    var old:Null<BaseCharacter> = switch (type)
    {
      case BF: stage.getBoyfriend(true);
      case GF: stage.getGirlfriend(true);
      default: stage.getDad(true);
    };
    var c = cachedCharacters.get(id);
    cachedCharacters.remove(id);
    if (c == null) c = CharacterDataParser.fetchCharacter(id);
    if (c == null)
    {
      trace('[QOL] Change Character: unknown character $id');
      if (old != null) stage.addCharacter(old, type);
      return;
    }
    if (old != null)
    {
      // Keep the old one around so switching back is instant.
      cachedCharacters.set(old.characterId, old);
    }
    stage.addCharacter(c, type);
    stage.refresh();
    if (type == BF) c.initHealthIcon(false);
    else if (type == DAD) c.initHealthIcon(true);
    applyHealthBarColors();
  }

  public function destroy():Void
  {
    modchart?.destroy();
    modchart = null;
    for (p in stagePlayers)
      p.cancel();
    stagePlayers = [];
    for (s in cachedStages)
      s.kill();
    cachedStages.clear();
    for (c in cachedCharacters)
      if (c != null) c.destroy();
    cachedCharacters.clear();
    if (instance == this) instance = null;
  }
}
