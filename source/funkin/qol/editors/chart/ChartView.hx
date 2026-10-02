package funkin.qol.editors.chart;

import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.data.song.SongData.SongEventData;
import funkin.data.song.SongData.SongNoteData;
import funkin.play.components.HealthIcon;
import funkin.qol.ui.QOLTheme;

/**
 * Draws the QOL chart editor's grid: strumline lanes side by side (opponent, player, then any extra
 * strumlines), an events lane on the left, beat & measure lines, notes, holds, events,
 * the placement ghost, the selection box and the playhead.
 *
 * Only what's on screen is drawn, using pooled sprites, so huge charts stay fast.
 */
class ChartView extends FlxGroup
{
  public static final LANE_COLORS:Array<FlxColor> = [0xFFC24B99, 0xFF00FFFF, 0xFF12FA05, 0xFFF9393F];
  static final NOTE_PREFIXES:Array<String> = ['purple instance', 'blue instance', 'green instance', 'red instance'];

  public var model:ChartModel;
  public var conductor:Conductor;

  // Screen rectangle of the chart area.
  public var x:Float;

  /**
   * Left edge of the chart (the view centers the chart inside its area).
   */
  public var ox:Float = 0;
  public var y:Float;
  public var width:Float;
  public var height:Float;

  public var laneWidth:Float = 40;
  public var pxPerStep:Float = 40;
  public var headerHeight:Float = 64;
  public var eventLaneWidth:Float = 56;
  public var strumGap:Float = 14;

  /**
   * Where the playhead sits, as a fraction of the chart height.
   */
  public var playheadRatio:Float = 0.3;

  /**
   * Current song position in milliseconds.
   */
  public var songPosition:Float = 0;

  /**
   * Snap in steps (1 = 16th notes).
   */
  public var snapSteps:Float = 1;

  public var selectedNotes:Array<SongNoteData> = [];
  public var selectedEvents:Array<SongEventData> = [];

  /**
   * Notes currently being dragged are drawn with this offset (in steps / lanes).
   */
  public var dragStepOffset:Float = 0;

  public var dragLaneOffset:Int = 0;
  public var showWaveforms:Bool = true;

  public var ghostLane:Int = -2;
  public var ghostTime:Float = 0;
  public var ghostLength:Float = 0;
  public var boxSelect:Null<Array<Float>> = null;

  var strumCount:Int = 2;
  var bgSprites:Array<FlxSprite> = [];
  var laneLines:Array<FlxSprite> = [];
  var headers:Array<{bg:FlxSprite, icon:Null<HealthIcon>, label:FlxText, char:String}> = [];
  var beatLines:Array<FlxSprite> = [];
  var measureTexts:Array<FlxText> = [];
  var noteSprites:Array<FlxSprite> = [];
  var holdSprites:Array<FlxSprite> = [];
  var selectGlows:Array<FlxSprite> = [];
  var kindLabels:Array<FlxText> = [];
  var eventSprites:Array<FlxSprite> = [];
  var eventLabels:Array<FlxText> = [];
  var ghost:FlxSprite;
  var ghostHold:FlxSprite;
  var selectRect:FlxSprite;
  var playhead:FlxSprite;
  var playheadTime:FlxText;
  var noteFrames:FlxAtlasFrames;
  var eventFrames:Map<String, Null<FlxAtlasFrames>> = new Map<String, Null<FlxAtlasFrames>>();
  var layoutKey:String = '';

  public var waveforms:Array<funkin.audio.waveform.WaveformSprite> = [];

  public function new(model:ChartModel, conductor:Conductor)
  {
    super();
    this.model = model;
    this.conductor = conductor;
    noteFrames = Paths.getSparrowAtlas('NOTE_assets');

    ghost = makeNote();
    ghost.alpha = 0.45;
    ghostHold = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
    ghostHold.alpha = 0.35;
    selectRect = new FlxSprite().makeGraphic(1, 1, 0x405CE1FF);
    selectRect.visible = false;
    playhead = new FlxSprite().makeGraphic(1, 1, 0xFFFF3355);
    playheadTime = QOLTheme.outlinedText(0, 0, 0, '', 13, FlxColor.WHITE, 1.5);
  }

  function makeNote():FlxSprite
  {
    var s = new FlxSprite();
    s.frames = noteFrames;
    for (i in 0...4)
      s.animation.addByPrefix('n$i', NOTE_PREFIXES[i], 0, false);
    s.animation.play('n0');
    s.antialiasing = true;
    return s;
  }

  //
  // Layout
  //

  /**
   * Display order: opponent (1) first, then player (0), then extras (2, 3...).
   */
  public function displayOrder():Array<Int>
  {
    var order = [1, 0];
    for (i in 2...strumCount)
      order.push(i);
    return order;
  }

  public function strumlineX(strumline:Int):Float
  {
    var d = displayOrder().indexOf(strumline);
    return ox + eventLaneWidth + strumGap + d * (laneWidth * 4 + strumGap);
  }

  public var chartWidth(get, never):Float;

  function get_chartWidth():Float
    return eventLaneWidth + strumGap + strumCount * (laneWidth * 4 + strumGap);

  public var playheadY(get, never):Float;

  function get_playheadY():Float
    return y + headerHeight + (height - headerHeight) * playheadRatio;

  public function stepAt(ms:Float):Float
    return conductor.getTimeInSteps(ms);

  public function msAt(step:Float):Float
    return conductor.getStepTimeInMs(step);

  public function yAt(ms:Float):Float
    return playheadY + (stepAt(ms) - stepAt(songPosition)) * pxPerStep;

  public function timeAt(screenY:Float):Float
    return msAt(stepAt(songPosition) + (screenY - playheadY) / pxPerStep);

  /**
   * Step at a screen Y, snapped to the current snap.
   */
  public function snappedStepAt(screenY:Float, floor:Bool = false):Float
  {
    var raw = stepAt(songPosition) + (screenY - playheadY) / pxPerStep;
    return (floor ? Math.floor(raw / snapSteps) : Math.round(raw / snapSteps)) * snapSteps;
  }

  /**
   * Global lane under a screen X: `strumline * 4 + direction`, -1 for the events lane, -2 for nothing.
   */
  public function laneAt(screenX:Float):Int
  {
    if (screenX >= ox && screenX < ox + eventLaneWidth) return -1;
    for (s in 0...strumCount)
    {
      var sx = strumlineX(s);
      if (screenX >= sx && screenX < sx + laneWidth * 4) return s * 4 + Std.int((screenX - sx) / laneWidth);
    }
    return -2;
  }

  public function laneX(lane:Int):Float
    return strumlineX(Std.int(lane / 4)) + (lane % 4) * laneWidth;

  public function inChart(sx:Float, sy:Float):Bool
    return sx >= ox && sx < ox + chartWidth && sy >= y + headerHeight && sy < y + height;

  public function headerAt(sx:Float, sy:Float):Int
  {
    if (sy < y || sy >= y + headerHeight) return -1;
    for (s in 0...strumCount)
    {
      var hx = strumlineX(s);
      if (sx >= hx && sx < hx + laneWidth * 4) return s;
    }
    return -1;
  }

  /**
   * Find the note under the mouse (the topmost one).
   */
  public function noteAt(sx:Float, sy:Float):Null<SongNoteData>
  {
    var lane = laneAt(sx);
    if (lane < 0) return null;
    var notes = model.notes;
    var tMin = timeAt(sy - laneWidth / 2 - 2);
    var start = Std.int(Math.max(0, model.firstNoteIndexAt(tMin) - 1));
    var best:Null<SongNoteData> = null;
    for (i in start...notes.length)
    {
      var n = notes[i];
      var ny = yAt(n.time);
      if (ny - laneWidth / 2 > sy + 2) break;
      if (n.data != lane) continue;
      if (Math.abs(ny - sy) <= laneWidth / 2) best = n;
      else if (n.length > 0 && sy >= ny && sy <= yAt(n.time + n.length)) best = n;
    }
    return best;
  }

  public function eventAt(sx:Float, sy:Float):Null<SongEventData>
  {
    if (laneAt(sx) != -1) return null;
    for (e in model.events)
    {
      var ey = yAt(e.time);
      if (Math.abs(ey - sy) <= 18) return e;
    }
    return null;
  }

  function updateLayout()
  {
    strumCount = model.strumlineCount();
    var available = width - eventLaneWidth - strumGap;
    laneWidth = Math.min(48, Math.max(22, (available / strumCount - strumGap) / 4));
    ox = x + Math.max(0, Math.floor((width - chartWidth) / 2));
    var key = '$strumCount:$laneWidth:$x:$y:$width:$height:${characterKey()}';
    if (key == layoutKey) return;
    layoutKey = key;

    for (s in bgSprites.concat(laneLines))
    {
      remove(s, true);
      s.destroy();
    }
    for (h in headers)
    {
      remove(h.bg, true);
      remove(h.label, true);
      if (h.icon != null) remove(h.icon, true);
    }
    bgSprites = [];
    laneLines = [];
    headers = [];
    for (w in waveforms)
    {
      remove(w, true);
      w.destroy();
    }
    waveforms = [];

    var top = y + headerHeight;
    var h = height - headerHeight;
    var evBg = new FlxSprite(ox, top).makeGraphic(1, 1, 0xFF201A33);
    evBg.setGraphicSize(Std.int(eventLaneWidth), Std.int(h));
    evBg.updateHitbox();
    addAt(evBg, 0);
    bgSprites.push(evBg);
    var evLabel = QOLTheme.outlinedText(ox, y + 22, eventLaneWidth, 'EVENTS', 11, QOLTheme.TEXT_DIM, 1);
    evLabel.alignment = CENTER;
    var evHeaderBg = new FlxSprite(ox, y).makeGraphic(1, 1, 0xFF2B2340);
    evHeaderBg.setGraphicSize(Std.int(eventLaneWidth), Std.int(headerHeight - 4));
    evHeaderBg.updateHitbox();
    add(evHeaderBg);
    add(evLabel);
    headers.push({bg: evHeaderBg, icon: null, label: evLabel, char: ''});

    for (s in 0...strumCount)
    {
      var sx = strumlineX(s);
      var bg = new FlxSprite(sx, top).makeGraphic(1, 1, s == 0 ? 0xFF1E2A3A : (s == 1 ? 0xFF2E1E33 : 0xFF2A2A1E));
      bg.setGraphicSize(Std.int(laneWidth * 4), Std.int(h));
      bg.updateHitbox();
      addAt(bg, 1);
      bgSprites.push(bg);
      for (l in 1...4)
      {
        var line = new FlxSprite(sx + l * laneWidth, top).makeGraphic(1, 1, 0x30FFFFFF);
        line.setGraphicSize(1, Std.int(h));
        line.updateHitbox();
        addAt(line, 2);
        laneLines.push(line);
      }

      // Header with the character's icon.
      var hb = QOLTheme.roundRect(Std.int(laneWidth * 4), Std.int(headerHeight - 4), s == 0 ? 0xFF2D5C8F : (s == 1 ? 0xFF7A2E5C : 0xFF6B6A2A), 8);
      hb.setPosition(sx, y);
      add(hb);
      var charId = characterOf(s);
      var icon:Null<HealthIcon> = QOLTheme.healthIcon(charId, 44, s == 0);
      if (icon != null)
      {
        icon.setPosition(sx + 1, y + (headerHeight - 4 - icon.height) / 2);
        add(icon);
      }
      var name = strumlineName(s);
      var label = QOLTheme.outlinedText(sx + 42, y + 6, laneWidth * 4 - 44, name, 12, FlxColor.WHITE, 1.5);
      add(label);
      headers.push({
        bg: hb,
        icon: icon,
        label: label,
        char: charId
      });
    }
  }

  function addAt(s:FlxSprite, layer:Int)
  {
    // Background layers go to the start of the group so everything else draws on top.
    var index = 0;
    for (b in bgSprites.concat(laneLines))
      if (members.indexOf(b) >= 0) index = Std.int(Math.max(index, members.indexOf(b) + 1));
    insert(layer == 0 ? 0 : index, s);
  }

  function characterKey():String
  {
    var c = model.metadata.playData.characters;
    var extras = [for (sl in model.qolSong.strumlines) '${sl.index}=${sl.character}'].join(',');
    return '${c.player},${c.opponent},${c.girlfriend},$extras';
  }

  public function characterOf(strumline:Int):String
  {
    var c = model.metadata.playData.characters;
    return switch (strumline)
    {
      case 0: c.player;
      case 1: c.opponent;
      default:
        var data = model.extraStrumline(strumline);
        var id = data?.character ?? 'gf';
        id == 'gf' ? c.girlfriend : (id == 'bf' ? c.player : (id == 'dad' ? c.opponent : id));
    }
  }

  public function strumlineName(strumline:Int):String
  {
    return switch (strumline)
    {
      case 0: 'Player\n${characterOf(0)}';
      case 1: 'Opponent\n${characterOf(1)}';
      default:
        var data = model.extraStrumline(strumline);
        '${data?.name ?? 'Strumline ${strumline + 1}'}\n${characterOf(strumline)} · CPU';
    }
  }

  public function forceLayout()
    layoutKey = '';

  //
  // Drawing
  //

  public function refresh():Void
  {
    updateLayout();
    var top = y + headerHeight;
    var bottom = y + height;
    var curStep = stepAt(songPosition);
    var firstStep = Math.floor(curStep + (top - playheadY) / pxPerStep) - 1;
    var lastStep = Math.ceil(curStep + (bottom - playheadY) / pxPerStep) + 1;
    var lineIndex = 0;
    var textIndex = 0;
    var w = chartWidth;

    // Beat and measure lines.
    var stepsPerBeat = 4;
    var beatsPerMeasure = Std.int(conductor.timeSignatureNumerator > 0 ? conductor.timeSignatureNumerator : 4);
    var showSteps = pxPerStep >= 22;
    for (step in firstStep...lastStep + 1)
    {
      if (step < 0) continue;
      var isBeat = step % stepsPerBeat == 0;
      var isMeasure = step % (stepsPerBeat * beatsPerMeasure) == 0;
      if (!isBeat && !showSteps) continue;
      var ly = playheadY + (step - curStep) * pxPerStep;
      if (ly < top || ly > bottom) continue;
      var line = getPooled(beatLines, lineIndex++, () -> new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE));
      line.setPosition(ox, ly);
      line.setGraphicSize(Std.int(w), isMeasure ? 2 : 1);
      line.updateHitbox();
      line.alpha = isMeasure ? 0.55 : (isBeat ? 0.25 : 0.08);
      if (isMeasure)
      {
        var t = getPooled(measureTexts, textIndex++, () -> QOLTheme.text(0, 0, 40, '', 11, QOLTheme.FONT_MONO, QOLTheme.TEXT_DIM));
        t.text = '${Std.int(step / (stepsPerBeat * beatsPerMeasure)) + 1}';
        t.setPosition(ox + 2, ly + 1);
      }
    }
    hideRest(beatLines, lineIndex);
    hideRest(measureTexts, textIndex);

    // Notes.
    var notes = model.notes;
    var tStart = msAt(firstStep - 64);
    var tEnd = msAt(lastStep + 1);
    var noteIndex = 0;
    var holdIndex = 0;
    var kindIndex = 0;
    var glowIndex = 0;
    var start = model.firstNoteIndexAt(tStart);
    var dragOffsetMs = 0.0;
    for (i in start...notes.length)
    {
      var n = notes[i];
      if (n.time > tEnd) break;
      var selected = selectedNotes.indexOf(n) != -1;
      var lane = n.data;
      var noteStep = stepAt(n.time);
      if (selected && (dragStepOffset != 0 || dragLaneOffset != 0))
      {
        noteStep += dragStepOffset;
        lane = n.data + dragLaneOffset;
        if (lane < 0 || Std.int(lane / 4) >= strumCount) lane = n.data;
      }
      var ny = playheadY + (noteStep - curStep) * pxPerStep;
      if (n.length > 0)
      {
        var endY = playheadY + (stepAt(n.time + n.length) + (noteStep - stepAt(n.time)) - curStep) * pxPerStep;
        if (endY > top && ny < bottom)
        {
          var hold = getPooled(holdSprites, holdIndex++, () -> new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE));
          var hw = Math.max(4, laneWidth * 0.28);
          var hy = Math.max(top, ny);
          var hh = Math.min(bottom, endY) - hy;
          hold.setPosition(laneX(lane) + (laneWidth - hw) / 2, hy);
          hold.setGraphicSize(Std.int(hw), Std.int(Math.max(1, hh)));
          hold.updateHitbox();
          hold.color = selected ? 0xFF5CE1FF : LANE_COLORS[lane % 4];
          hold.alpha = 0.85;
        }
      }
      if (ny < top - laneWidth || ny > bottom + laneWidth) continue;
      var spr = getPooled(noteSprites, noteIndex++, makeNote);
      spr.animation.play('n${lane % 4}');
      spr.setGraphicSize(Std.int(laneWidth - 4), Std.int(laneWidth - 4));
      spr.updateHitbox();
      spr.setPosition(laneX(lane) + 2, ny - (laneWidth - 4) / 2);
      // Selected notes keep their colors and get an outline (tinting would turn red notes dark).
      spr.color = FlxColor.WHITE;
      spr.alpha = (ny < top) ? 0.3 : 1;
      if (selected)
      {
        var glow = getPooled(selectGlows, glowIndex++, () -> new FlxSprite());
        var size = Std.int(laneWidth);
        var key = 'qol-chart-sel3-$size';
        if (glow.graphic == null || glow.graphic.key != key)
        {
          glow.loadGraphic(QOLTheme.cached(key, () -> QOLTheme.drawOutline(size, size, 0x00000000, Math.max(4, size * 0.22), 0xFF8CF6FF, 3)));
          glow.antialiasing = true;
        }
        glow.setPosition(laneX(lane), ny - size / 2);
      }
      if (n.kind != null && n.kind != '')
      {
        var label = getPooled(kindLabels, kindIndex++, () -> {
          var t = QOLTheme.outlinedText(0, 0, 0, '', 10, QOLTheme.ACCENT_YELLOW, 1.2);
          return t;
        });
        var k = n.kind.length > 6 ? n.kind.substr(0, 6) : n.kind;
        if (label.text != k) label.text = k;
        label.setPosition(laneX(lane) + 1, ny - 7);
      }
    }
    hideRest(noteSprites, noteIndex);
    hideRest(holdSprites, holdIndex);
    hideRest(kindLabels, kindIndex);

    // Events.
    var evIndex = 0;
    var evLabelIndex = 0;
    var stackY = -9999.0;
    var stackX = 0;
    for (e in model.events)
    {
      if (e.time < tStart) continue;
      if (e.time > tEnd) break;
      var selected = selectedEvents.indexOf(e) != -1;
      var eStep = stepAt(e.time) + (selected ? dragStepOffset : 0);
      var ey = playheadY + (eStep - curStep) * pxPerStep;
      if (ey < top - 30 || ey > bottom + 30) continue;
      if (Math.abs(ey - stackY) < 1) stackX++;
      else
      {
        stackX = 0;
        stackY = ey;
      }
      var spr = getPooled(eventSprites, evIndex++, () -> {
        var s = new FlxSprite();
        s.antialiasing = true;
        return s;
      });
      applyEventIcon(spr, e.eventKind);
      var size = Std.int(Math.min(36, eventLaneWidth - 12));
      spr.setGraphicSize(size, size);
      spr.updateHitbox();
      spr.setPosition(ox + 6 + stackX * 8, ey - size / 2);
      spr.color = FlxColor.WHITE;
      spr.alpha = (ey < top) ? 0.3 : 1;
      if (selected)
      {
        var glow = getPooled(selectGlows, glowIndex++, () -> new FlxSprite());
        var gs = size + 6;
        var key = 'qol-chart-sel3-$gs';
        if (glow.graphic == null || glow.graphic.key != key)
        {
          glow.loadGraphic(QOLTheme.cached(key, () -> QOLTheme.drawOutline(gs, gs, 0x00000000, Math.max(4, gs * 0.22), 0xFF8CF6FF, 3)));
          glow.antialiasing = true;
        }
        glow.setPosition(spr.x - 3, spr.y - 3);
        var label = getPooled(eventLabels, evLabelIndex++, () -> QOLTheme.outlinedText(0, 0, 0, '', 11, FlxColor.WHITE, 1.5));
        var title = funkin.data.event.SongEventRegistry.getEvent(e.eventKind)?.getTitle() ?? e.eventKind;
        if (label.text != title) label.text = title;
        label.setPosition(ox + eventLaneWidth + 2, ey - 8);
      }
    }
    hideRest(eventSprites, evIndex);
    hideRest(eventLabels, evLabelIndex);
    hideRest(selectGlows, glowIndex);

    // Ghost note.
    ghost.visible = ghostLane >= 0;
    ghostHold.visible = ghost.visible && ghostLength > 0;
    if (ghost.visible)
    {
      ghost.animation.play('n${ghostLane % 4}');
      ghost.setGraphicSize(Std.int(laneWidth - 4), Std.int(laneWidth - 4));
      ghost.updateHitbox();
      var gy = yAt(ghostTime);
      ghost.setPosition(laneX(ghostLane) + 2, gy - (laneWidth - 4) / 2);
      if (ghostHold.visible)
      {
        var hw = Math.max(4, laneWidth * 0.28);
        var ey = yAt(ghostTime + ghostLength);
        ghostHold.setPosition(laneX(ghostLane) + (laneWidth - hw) / 2, gy);
        ghostHold.setGraphicSize(Std.int(hw), Std.int(Math.max(1, ey - gy)));
        ghostHold.updateHitbox();
        ghostHold.color = LANE_COLORS[ghostLane % 4];
      }
    }

    // Selection rectangle.
    selectRect.visible = boxSelect != null;
    if (boxSelect != null)
    {
      var bx = Math.min(boxSelect[0], boxSelect[2]);
      var by = Math.min(boxSelect[1], boxSelect[3]);
      selectRect.setPosition(bx, by);
      selectRect.setGraphicSize(Std.int(Math.max(1, Math.abs(boxSelect[2] - boxSelect[0]))), Std.int(Math.max(1, Math.abs(boxSelect[3] - boxSelect[1]))));
      selectRect.updateHitbox();
    }

    // Playhead.
    playhead.setPosition(ox, playheadY - 1);
    playhead.setGraphicSize(Std.int(w), 3);
    playhead.updateHitbox();
    var secs = songPosition / 1000;
    var label = '${Math.floor(secs / 60)}:${StringTools.lpad('${Math.floor(secs % 60)}', '0', 2)}.${StringTools.lpad('${Math.floor((secs * 100) % 100)}', '0', 2)}';
    if (playheadTime.text != label) playheadTime.text = label;
    playheadTime.setPosition(ox + w + 6, playheadY - 9);

    // Waveforms follow the song position.
    if (waveforms.length > 0)
    {
      // The waveform starts at the song's start (y of time 0) when that is on screen.
      var startY = Math.max(top, yAt(0));
      var startMs = Math.max(0, timeAt(startY));
      var endMs = timeAt(bottom);
      for (wave in waveforms)
      {
        var wh = Math.max(1, bottom - startY);
        if (wave.y != startY) wave.y = startY;
        if (wave.height != wh) wave.height = wh;
        var t = startMs / 1000;
        var d = Math.max(0.001, (endMs - startMs) / 1000);
        if (wave.time != t) wave.time = t;
        if (wave.duration != d) wave.duration = d;
      }
    }
  }

  /**
   * Waveforms go behind the notes, one per strumline (player & opponent vocals) plus the instrumental under the events lane.
   */
  public function setWaveforms(inst:Null<funkin.audio.waveform.WaveformData>, player:Null<funkin.audio.waveform.WaveformData>,
      opponent:Null<funkin.audio.waveform.WaveformData>):Void
  {
    for (w in waveforms)
    {
      remove(w, true);
      w.destroy();
    }
    waveforms = [];
    if (!showWaveforms) return;
    var top = y + headerHeight;
    var h = height - headerHeight;
    function addWave(data:Null<funkin.audio.waveform.WaveformData>, wx:Float, ww:Float, color:FlxColor)
    {
      if (data == null) return;
      var wave = new funkin.audio.waveform.WaveformSprite(data, funkin.audio.waveform.WaveformSprite.WaveformOrientation.VERTICAL, color, 1.0);
      wave.x = wx;
      wave.y = top;
      wave.width = ww;
      wave.height = h;
      wave.alpha = 0.35;
      insert(bgSprites.length + laneLines.length, wave);
      waveforms.push(wave);
    }
    addWave(inst, ox, eventLaneWidth, 0xFF8E7CC3);
    addWave(player, strumlineX(0), laneWidth * 4, 0xFF5CB8FF);
    addWave(opponent, strumlineX(1), laneWidth * 4, 0xFFFF7CB8);
  }

  function applyEventIcon(spr:FlxSprite, kind:String)
  {
    var frames = eventFrames.get(kind);
    if (!eventFrames.exists(kind))
    {
      frames = null;
      try
      {
        if (Assets.exists(Paths.image('ui/chart-editor/events/$kind'))) frames = Paths.getSparrowAtlas('ui/chart-editor/events/$kind');
      }
      catch (e) {}
      if (frames == null) frames = Paths.getSparrowAtlas('ui/chart-editor/events/Default');
      eventFrames.set(kind, frames);
    }
    if (spr.frames != frames) spr.frames = frames;
  }

  function getPooled<T:FlxSprite>(pool:Array<T>, index:Int, make:Void->T):T
  {
    while (pool.length <= index)
    {
      var s = make();
      pool.push(s);
      // Keep the overlays (ghost, selection, playhead) drawing on top.
      var overlayStart = members.indexOf(ghostHold);
      if (overlayStart >= 0) insert(overlayStart, s);
      else
        add(s);
    }
    var s = pool[index];
    s.visible = true;
    return s;
  }

  static function hideRest<T:FlxSprite>(pool:Array<T>, from:Int)
  {
    for (i in from...pool.length)
      pool[i].visible = false;
  }

  /**
   * Adds the overlays (ghost, selection, playhead) last so they draw on top.
   */
  public function addOverlays():Void
  {
    add(ghostHold);
    add(ghost);
    add(selectRect);
    add(playhead);
    add(playheadTime);
  }
}
