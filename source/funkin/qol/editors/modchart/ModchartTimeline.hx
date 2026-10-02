package funkin.qol.editors.modchart;

#if FEATURE_HAXEUI
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.qol.editors.ModchartEditorState;
import funkin.qol.editors.modchart.ModchartDoc.ModKeyRef;
import funkin.qol.runtime.QOLModchart;
import funkin.qol.runtime.QOLModchart.QOLModchartData;
import funkin.qol.runtime.QOLModchart.QOLModchartRuntime;
import funkin.qol.runtime.QOLModchart.QOLModHost;
import funkin.qol.runtime.QOLModchart.QOLModKey;
import funkin.qol.runtime.QOLModchart.QOLModTrack;
import funkin.qol.ui.QOLTheme;
import openfl.display.BitmapData;

/**
 * One row of the timeline.
 */
typedef TimelineRow =
{
  /**
   * 0 = section (Strumlines, Cameras...), 1 = target (a strumline, an arrow, the health bar...), 2 = track (one property).
   */
  var kind:Int;

  var label:String;
  var depth:Int;
  var ?target:String;
  var ?track:QOLModTrack;
  var ?expandKey:String;
}

/**
 * The Modchart Editor's timeline: like an animator's, with a row for every UI element and a track (layer) for every
 * animated property. Keys are diamonds; bars between keys show tweens.
 */
class ModchartTimeline extends FlxGroup
{
  public static final LABEL_W:Int = 250;
  public static final RULER_H:Int = 22;
  public static final NOTES_H:Int = 14;
  public static final ROW_H:Int = 20;
  static final KEY_SIZE:Int = 12;

  static final COLOR_BG:FlxColor = 0xFF17181D;
  static final COLOR_LABEL_BG:FlxColor = 0xFF202229;
  static final COLOR_SECTION:FlxColor = 0xFF2A2340;
  static final COLOR_TARGET:FlxColor = 0xFF23262E;
  static final COLOR_TRACK_A:FlxColor = 0xFF1B1D24;
  static final COLOR_TRACK_B:FlxColor = 0xFF1E2028;
  static final COLOR_SELECTED:FlxColor = 0xFF2F3B58;
  static final COLOR_KEY:FlxColor = 0xFF8FD3FF;
  static final COLOR_KEY_EASE:FlxColor = 0xFFC79BFF;
  static final COLOR_KEY_INSTANT:FlxColor = 0xFFFF9B8F;
  static final COLOR_KEY_SELECTED:FlxColor = 0xFFFFD84A;

  public var x:Float;
  public var y:Float;
  public var width:Float;
  public var height:Float;

  public var pxPerBeat:Float = 40;
  public var scrollBeat:Float = -0.5;
  public var scrollRow:Int = 0;
  public var rows:Array<TimelineRow> = [];
  public var expanded:Map<String, Bool> = new Map<String, Bool>();

  var ed:ModchartEditorState;
  var cam:FlxCamera;

  var bgSpr:FlxSprite;
  var labelBg:FlxSprite;
  var rulerBg:FlxSprite;
  var notesBg:FlxSprite;
  var divider:FlxSprite;
  var playhead:FlxSprite;
  var playheadCap:FlxSprite;
  var boxSpr:FlxSprite;
  var hintText:FlxText;

  var rowBgs:Array<FlxSprite> = [];
  var rowTexts:Array<FlxText> = [];
  var valueTexts:Array<FlxText> = [];
  var arrowSprs:Array<FlxSprite> = [];
  var plusTexts:Array<FlxText> = [];
  var keySprs:Array<FlxSprite> = [];
  var barSprs:Array<FlxSprite> = [];
  var gridSprs:Array<FlxSprite> = [];
  var rulerTexts:Array<FlxText> = [];
  var noteSprs:Array<FlxSprite> = [];

  // Draw layers (pools grow over time; each kind of sprite stays in its own layer so the order never breaks).
  var layerGrid:FlxGroup = new FlxGroup();
  var layerRows:FlxGroup = new FlxGroup();
  var layerBars:FlxGroup = new FlxGroup();
  var layerKeys:FlxGroup = new FlxGroup();
  var layerText:FlxGroup = new FlxGroup();

  var keyGraphic:FlxGraphic;
  var keyGraphicSmall:FlxGraphic;
  var arrowRight:FlxGraphic;
  var arrowDown:FlxGraphic;

  // Input state.
  var dragMode:String = '';
  var dragStartX:Float = 0;
  var dragStartY:Float = 0;
  var dragMoved:Bool = false;
  var dragBefore:String = '';
  var dragOrig:Array<Float> = [];
  var dragTracks:Array<QOLModTrack> = [];
  var boxRow:Int = 0;
  var lastClickTime:Float = 0;
  var lastClickRow:Int = -1;

  public function new(ed:ModchartEditorState, cam:FlxCamera, x:Float, y:Float, width:Float, height:Float)
  {
    super();
    this.ed = ed;
    this.cam = cam;
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;

    keyGraphic = QOLTheme.cached('mc-key', () -> diamondBitmap(KEY_SIZE));
    keyGraphicSmall = QOLTheme.cached('mc-key-small', () -> diamondBitmap(8));
    arrowRight = QOLTheme.cached('mc-arrow-right', () -> triangleBitmap(false));
    arrowDown = QOLTheme.cached('mc-arrow-down', () -> triangleBitmap(true));

    bgSpr = rect(x, y, width, height, COLOR_BG);
    labelBg = rect(x, y, LABEL_W, height, COLOR_LABEL_BG);
    rulerBg = rect(x + LABEL_W, y, width - LABEL_W, RULER_H, 0xFF26283A);
    notesBg = rect(x + LABEL_W, y + RULER_H, width - LABEL_W, NOTES_H, 0xFF15161B);
    divider = rect(x + LABEL_W - 1, y, 1, height, 0xFF3A3F4F);
    var top = rect(x, y, width, 1, 0xFF3A3F4F);
    hintText = QOLTheme.text(x + 8, y + 3, LABEL_W - 16, 'TIMELINE', 12, QOLTheme.FONT_TITLE, QOLTheme.ACCENT_PINK);
    prep(hintText);
    var notesLabel = QOLTheme.text(x + 8, y + RULER_H, LABEL_W - 16, 'Notes', 10, QOLTheme.FONT_BODY, 0xFF8A86A8);
    prep(notesLabel);
    add(bgSpr);
    add(labelBg);
    add(rulerBg);
    add(notesBg);
    add(top);
    add(hintText);
    add(notesLabel);
    add(layerRows);
    add(layerGrid);
    add(layerBars);
    add(layerKeys);
    add(layerText);

    boxSpr = new FlxSprite().makeGraphic(1, 1, 0x405CE1FF);
    prep(boxSpr);
    boxSpr.visible = false;
    playhead = new FlxSprite().makeGraphic(1, 1, 0xFFFF4D6D);
    prep(playhead);
    playheadCap = new FlxSprite().loadGraphic(arrowDown);
    playheadCap.color = 0xFFFF4D6D;
    prep(playheadCap);
  }

  /**
   * Add the overlay sprites last so they draw on top of everything.
   */
  public function addOverlays():Void
  {
    add(divider);
    add(boxSpr);
    add(playhead);
    add(playheadCap);
  }

  function prep<T:FlxSprite>(s:T):T
  {
    s.cameras = [cam];
    s.scrollFactor.set();
    return s;
  }

  function rect(x:Float, y:Float, w:Float, h:Float, color:FlxColor):FlxSprite
  {
    var s = new FlxSprite(x, y).makeGraphic(1, 1, FlxColor.WHITE);
    s.color = color;
    s.alpha = color.alphaFloat;
    s.setGraphicSize(Std.int(Math.max(1, w)), Std.int(Math.max(1, h)));
    s.updateHitbox();
    return prep(s);
  }

  static function diamondBitmap(size:Int):BitmapData
  {
    var bmp = new BitmapData(size, size, true, 0);
    var c = (size - 1) / 2;
    for (py in 0...size)
      for (px in 0...size)
      {
        var d = Math.abs(px - c) + Math.abs(py - c);
        if (d <= c + 0.5) bmp.setPixel32(px, py, d >= c - 1 ? 0xFF101015 : 0xFFFFFFFF);
      }
    return bmp;
  }

  static function triangleBitmap(down:Bool):BitmapData
  {
    var bmp = new BitmapData(9, 9, true, 0);
    for (py in 0...9)
      for (px in 0...9)
      {
        var inside = down ? (py <= 6 && Math.abs(px - 4) <= (6 - py) * 0.7) : (px <= 6 && Math.abs(py - 4) <= (6 - px) * 0.7);
        if (inside) bmp.setPixel32(px, py, 0xFFFFFFFF);
      }
    return bmp;
  }

  //
  // Geometry
  //

  public var trackX(get, never):Float;

  function get_trackX():Float
    return x + LABEL_W;

  public var rowsTop(get, never):Float;

  function get_rowsTop():Float
    return y + RULER_H + NOTES_H;

  public var visibleRows(get, never):Int;

  function get_visibleRows():Int
    return Std.int((y + height - rowsTop) / ROW_H);

  public inline function xOf(beat:Float):Float
    return trackX + (beat - scrollBeat) * pxPerBeat;

  public inline function beatAt(sx:Float):Float
    return scrollBeat + (sx - trackX) / pxPerBeat;

  public function contains(sx:Float, sy:Float):Bool
    return sx >= x && sx < x + width && sy >= y && sy < y + height;

  public function rowAt(sy:Float):Int
  {
    if (sy < rowsTop) return -1;
    var r = scrollRow + Std.int((sy - rowsTop) / ROW_H);
    return r >= 0 && r < rows.length ? r : -1;
  }

  function rowY(index:Int):Float
    return rowsTop + (index - scrollRow) * ROW_H;

  public function keyAt(sx:Float, sy:Float):Null<ModKeyRef>
  {
    var r = rowAt(sy);
    if (r < 0 || rows[r].kind != 2) return null;
    var track = rows[r].track;
    var best:Null<QOLModKey> = null;
    var bestDist = 8.0;
    for (k in track.keys)
    {
      var d = Math.abs(xOf(k.t) - sx);
      if (d <= bestDist)
      {
        bestDist = d;
        best = k;
      }
    }
    return best == null ? null : {track: track, key: best};
  }

  //
  // Rows
  //

  public function rebuildRows():Void
  {
    rows = [];
    for (group in ed.preview.targetGroups())
    {
      if (group.targets.length == 0) continue;
      var key = 'sec:${group.name}';
      rows.push({
        kind: 0,
        label: group.name.toUpperCase(),
        depth: 0,
        expandKey: key
      });
      if (!isExpanded(key, group.name != 'Stage props')) continue;
      for (target in group.targets)
        addTargetRows(target, 1);
    }
    scrollRow = Std.int(Math.max(0, Math.min(scrollRow, rows.length - visibleRows)));
  }

  function hasTracksDeep(target:String):Bool
  {
    if (ed.doc.hasTracks(target)) return true;
    if (QOLModchart.targetKind(target) == 'strum') for (i in 0...4)
      if (ed.doc.hasTracks('$target:$i')) return true;
    return false;
  }

  function addTargetRows(target:String, depth:Int):Void
  {
    var kind = QOLModchart.targetKind(target);
    var label = kind == 'lane' ? '${QOLModchart.LANE_NAMES[QOLModchart.laneIndexOf(target)]} arrow' : QOLModchart.targetName(target);
    rows.push({
      kind: 1,
      label: label,
      depth: depth,
      target: target,
      expandKey: target
    });
    if (!isExpanded(target, hasTracksDeep(target))) return;
    for (t in ed.doc.tracksOf(target))
    {
      var prop = QOLModchart.getProp(t.prop, kind);
      rows.push({
        kind: 2,
        label: prop?.name ?? t.prop,
        depth: depth + 1,
        target: target,
        track: t
      });
    }
    if (kind == 'strum') for (i in 0...4)
      addTargetRows('$target:$i', depth + 1);
  }

  public function isExpanded(key:String, fallback:Bool):Bool
    return expanded.exists(key) ? expanded.get(key) : fallback;

  public function toggle(key:String, fallback:Bool):Void
  {
    expanded.set(key, !isExpanded(key, fallback));
    rebuildRows();
  }

  /**
   * Make sure a target's rows are visible (expanding its parents), and scroll to it.
   */
  public function reveal(target:String):Void
  {
    var kind = QOLModchart.targetKind(target);
    var section = switch (kind)
    {
      case 'strum' | 'lane': 'Strumlines';
      case 'camera': 'Cameras';
      default: target.startsWith('char:') ? 'Characters' : (target.startsWith('prop:') ? 'Stage props' : 'HUD');
    };
    expanded.set('sec:$section', true);
    if (kind == 'lane') expanded.set('strum:${QOLModchart.strumIndexOf(target)}', true);
    expanded.set(target, true);
    rebuildRows();
    for (i in 0...rows.length)
    {
      if (rows[i].kind == 1 && rows[i].target == target)
      {
        if (i < scrollRow) scrollRow = i;
        else if (i >= scrollRow + visibleRows - 2) scrollRow = Std.int(Math.max(0, i - visibleRows + 3));
        break;
      }
    }
  }

  //
  // Drawing
  //

  function layerOf(pool:Array<Dynamic>):FlxGroup
  {
    if (pool == rowBgs) return layerRows;
    if (pool == gridSprs || pool == noteSprs) return layerGrid;
    if (pool == barSprs) return layerBars;
    if (pool == keySprs) return layerKeys;
    return layerText;
  }

  function pooled<T:FlxSprite>(pool:Array<T>, index:Int, make:Void->T):T
  {
    while (pool.length <= index)
    {
      var s = prep(make());
      pool.push(s);
      layerOf(cast pool).add(s);
    }
    var s = pool[index];
    s.visible = true;
    return s;
  }

  static function hideFrom<T:FlxSprite>(pool:Array<T>, from:Int):Void
  {
    for (i in from...pool.length)
      pool[i].visible = false;
  }

  function line(pool:Array<FlxSprite>, index:Int, x:Float, y:Float, w:Float, h:Float, color:FlxColor):FlxSprite
  {
    var s = pooled(pool, index, () -> new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE));
    s.setPosition(x, y);
    s.scale.set(Math.max(1, w), Math.max(1, h));
    s.updateHitbox();
    s.color = color.rgb;
    s.alpha = color.alphaFloat;
    return s;
  }

  public function refresh():Void
  {
    var right = x + width;
    var bottom = y + height;
    var firstBeat = Math.floor(beatAt(trackX));
    var lastBeat = Math.ceil(beatAt(right));
    var bpm = ed.beatsPerMeasure;

    // Grid + ruler.
    var gi = 0;
    var ti = 0;
    var showBeats = pxPerBeat >= 12;
    var labelEvery = pxPerBeat >= 30 ? 1 : (pxPerBeat >= 14 ? 2 : 4);
    for (b in firstBeat...lastBeat + 1)
    {
      if (b < 0) continue;
      var isMeasure = b % bpm == 0;
      if (!isMeasure && !showBeats) continue;
      var lx = xOf(b);
      if (lx < trackX || lx > right) continue;
      line(gridSprs, gi++, lx, y + (isMeasure ? 4 : 12), 1, (isMeasure ? RULER_H - 4 : RULER_H - 12), isMeasure ? 0xFFB9B4D8 : 0xFF6E6A8A);
      line(gridSprs, gi++, lx, y + RULER_H, 1, height - RULER_H, isMeasure ? 0x30FFFFFF : 0x14FFFFFF);
      // Sub-beat snap lines when zoomed in.
      if (pxPerBeat >= 80 && ed.snapBeats < 1)
      {
        var sub = ed.snapBeats;
        var n = Std.int(Math.round(1 / sub));
        for (k in 1...n)
        {
          var sx = xOf(b + k * sub);
          if (sx > trackX && sx < right) line(gridSprs, gi++, sx, y + RULER_H, 1, height - RULER_H, 0x0AFFFFFF);
        }
      }
      var measureNum = Std.int(b / bpm) + 1;
      var beatInMeasure = b % bpm;
      if ((isMeasure && (labelEvery <= 4 || measureNum % 2 == 1)) || (pxPerBeat >= 30 && !isMeasure))
      {
        if (!isMeasure && (b % labelEvery) != 0) continue;
        var t = pooled(rulerTexts, ti++, () -> QOLTheme.text(0, 0, 60, '', 10, QOLTheme.FONT_MONO, 0xFFDAD6F2));
        var txt = isMeasure ? '$measureNum' : '$measureNum.${beatInMeasure + 1}';
        if (t.text != txt) t.text = txt;
        t.color = isMeasure ? 0xFFFFFFFF : 0xFF9A96B8;
        t.setPosition(lx + 3, y + 3);
      }
    }
    hideFrom(gridSprs, gi);
    hideFrom(rulerTexts, ti);

    // Notes strip.
    var ni = 0;
    var notes = ed.noteBeats;
    if (notes != null)
    {
      var lo = 0;
      var hi = notes.length;
      var startBeat = beatAt(trackX);
      while (lo < hi)
      {
        var mid = (lo + hi) >> 1;
        if (notes[mid].b < startBeat) lo = mid + 1;
        else
          hi = mid;
      }
      var lastPx = -999.0;
      for (i in lo...notes.length)
      {
        var n = notes[i];
        var nx = xOf(n.b);
        if (nx > right) break;
        if (nx - lastPx < 1.5 && ni > 0) continue;
        lastPx = nx;
        var col:FlxColor = n.s == 0 ? 0xFF5CE1FF : (n.s == 1 ? 0xFFFF7CB8 : 0xFFFFD84A);
        var yy = y + RULER_H + 2 + (n.s == 0 ? 0 : (n.s == 1 ? 4 : 8));
        line(noteSprs, ni++, nx, yy, 2, 4, col);
        if (ni > 600) break;
      }
    }
    hideFrom(noteSprs, ni);

    // Rows.
    var ri = 0;
    var ki = 0;
    var bi = 0;
    var ai = 0;
    var pi = 0;
    var vi = 0;
    var pli = 0;
    var vis = visibleRows;
    for (r in 0...vis)
    {
      var index = scrollRow + r;
      if (index >= rows.length) break;
      var row = rows[index];
      var ry = rowsTop + r * ROW_H;
      var selected = (row.kind == 2 && row.track == ed.selTrack) || (row.kind == 1 && row.target == ed.selTarget && ed.selTrack == null);
      var color:FlxColor = switch (row.kind)
      {
        case 0: COLOR_SECTION;
        case 1: COLOR_TARGET;
        default: (index % 2 == 0) ? COLOR_TRACK_A : COLOR_TRACK_B;
      };
      if (selected) color = COLOR_SELECTED;
      line(rowBgs, ri++, x, ry, width, ROW_H - 1, color);

      var indent = 8 + row.depth * 14;
      if (row.kind != 2)
      {
        var exp = isExpanded(row.expandKey, row.kind == 0 ? row.label != 'STAGE PROPS' : hasTracksDeep(row.target));
        var a = pooled(arrowSprs, ai++, () -> new FlxSprite().loadGraphic(arrowRight));
        a.loadGraphic(exp ? arrowDown : arrowRight);
        a.setPosition(x + indent, ry + (ROW_H - 9) / 2);
        a.color = row.kind == 0 ? 0xFFFF8FB8 : 0xFFB9B4D8;
      }
      var t = pooled(rowTexts, pi++, () -> QOLTheme.text(0, 0, LABEL_W - 40, '', 12, QOLTheme.FONT_BODY, 0xFFFFFFFF));
      var label = row.label + ((row.kind == 2 && row.track.muted == true) ? '  (muted)' : '');
      if (t.text != label) t.text = label;
      t.fieldWidth = LABEL_W - indent - (row.kind == 2 ? 70 : 34);
      t.color = switch (row.kind)
      {
        case 0: 0xFFFF8FB8;
        case 1: 0xFFE8E4FF;
        default: row.track.muted == true ? 0xFF77738F : 0xFFC9C2E6;
      };
      t.setPosition(x + indent + (row.kind == 2 ? 4 : 14), ry + 2);

      if (row.kind == 2)
      {
        // Current value.
        var v = pooled(valueTexts, vi++, () -> QOLTheme.text(0, 0, 60, '', 11, QOLTheme.FONT_MONO, 0xFF9FE8FF));
        var value = QOLModchart.sample(row.track, ed.beat, QOLModchart.neutralOf(row.target, row.track.prop));
        var vt = formatValue(value);
        if (v.text != vt) v.text = vt;
        v.alignment = RIGHT;
        v.setPosition(x + LABEL_W - 66, ry + 3);

        // Keys and tween bars.
        var keys = row.track.keys;
        for (k in 0...keys.length)
        {
          var key = keys[k];
          if (k + 1 < keys.length)
          {
            var next = keys[k + 1];
            var x1 = Math.max(trackX, xOf(key.t));
            var x2 = Math.min(right, xOf(next.t));
            if (x2 > x1)
            {
              var tween = next.v != key.v;
              var bc:FlxColor = tween ? (next.e == 'INSTANT' ? 0x50FF9B8F : 0x60B48CFF) : 0x26FFFFFF;
              line(barSprs, bi++, x1, ry + ROW_H / 2 - (tween ? 2 : 1), x2 - x1, tween ? 4 : 2, bc);
            }
          }
          var kx = xOf(key.t);
          if (kx < trackX - KEY_SIZE || kx > right + KEY_SIZE) continue;
          var s = pooled(keySprs, ki++, () -> new FlxSprite().loadGraphic(keyGraphic));
          if (s.graphic != keyGraphic) s.loadGraphic(keyGraphic);
          s.setPosition(kx - KEY_SIZE / 2, ry + (ROW_H - KEY_SIZE) / 2);
          s.color = ed.isKeySelected(key) ? COLOR_KEY_SELECTED : (row.track.muted == true ? 0xFF77738F : (key.e == 'INSTANT' ? COLOR_KEY_INSTANT : ((key.e == null
            || key.e == 'linear') ? COLOR_KEY : COLOR_KEY_EASE)));
        }
      }
      else if (row.kind == 1)
      {
        // "+" to add a property.
        var plus = pooled(plusTexts, pli++, () -> QOLTheme.text(0, 0, 20, '+', 14, QOLTheme.FONT_TITLE, 0xFF7CE38B));
        plus.setPosition(x + LABEL_W - 22, ry);
        // Summary of the target's keys while collapsed.
        if (!isExpanded(row.expandKey, hasTracksDeep(row.target)))
        {
          var lastX = -999.0;
          for (trk in ed.doc.tracksOf(row.target))
          {
            for (key in trk.keys)
            {
              var kx = xOf(key.t);
              if (kx < trackX || kx > right || Math.abs(kx - lastX) < 3) continue;
              lastX = kx;
              var s = pooled(keySprs, ki++, () -> new FlxSprite().loadGraphic(keyGraphicSmall));
              if (s.graphic != keyGraphicSmall) s.loadGraphic(keyGraphicSmall);
              s.setPosition(kx - 4, ry + (ROW_H - 8) / 2);
              s.color = 0xFF8A86A8;
            }
          }
        }
      }
    }
    hideFrom(rowBgs, ri);
    hideFrom(rowTexts, pi);
    hideFrom(valueTexts, vi);
    hideFrom(keySprs, ki);
    hideFrom(barSprs, bi);
    hideFrom(arrowSprs, ai);
    hideFrom(plusTexts, pli);

    // Playhead.
    var px = xOf(ed.beat);
    playhead.visible = playheadCap.visible = px >= trackX && px <= right;
    playhead.setPosition(px - 1, y + 4);
    playhead.scale.set(2, height - 4);
    playhead.updateHitbox();
    playheadCap.setPosition(px - 4.5, y + 1);

    // Box selection.
    if (dragMode == 'box' && dragMoved)
    {
      var mx = FlxG.mouse.viewX;
      var my = FlxG.mouse.viewY;
      boxSpr.visible = true;
      boxSpr.setPosition(Math.min(mx, dragStartX), Math.min(my, dragStartY));
      boxSpr.scale.set(Math.max(1, Math.abs(mx - dragStartX)), Math.max(1, Math.abs(my - dragStartY)));
      boxSpr.updateHitbox();
    }
    else
      boxSpr.visible = false;
  }

  public static function formatValue(v:Float):String
  {
    var r = Math.round(v * 100) / 100;
    var s = Std.string(r);
    if (s.indexOf('.') == -1) s += '.00';
    else if (s.length - s.indexOf('.') == 2) s += '0';
    return s;
  }

  //
  // Input
  //

  /**
   * Handle the mouse. Returns true if the timeline used it.
   */
  public function handleMouse():Bool
  {
    var mx = FlxG.mouse.viewX;
    var my = FlxG.mouse.viewY;
    var inside = contains(mx, my);

    // Wheel: scroll rows, Shift = scroll time, Ctrl = zoom.
    if (inside && FlxG.mouse.wheel != 0)
    {
      var w = FlxG.mouse.wheel > 0 ? 1 : -1;
      if (ed.ctrl())
      {
        var anchor = beatAt(Math.max(trackX, mx));
        pxPerBeat = Math.max(4, Math.min(480, pxPerBeat * (w > 0 ? 1.2 : 1 / 1.2)));
        scrollBeat = anchor - (Math.max(trackX, mx) - trackX) / pxPerBeat;
      }
      else if (FlxG.keys.pressed.SHIFT || mx >= trackX && my < rowsTop) scrollBeat = Math.max(-2, scrollBeat - w * 80 / pxPerBeat);
      else
        scrollRow = Std.int(Math.max(0, Math.min(rows.length - visibleRows, scrollRow - w * 2)));
    }

    if (dragMode != '')
    {
      continueDrag(mx, my);
      return true;
    }
    if (!inside) return false;

    if (FlxG.mouse.justPressedRight)
    {
      var k = keyAt(mx, my);
      if (k != null)
      {
        ed.deleteKeys([k]);
        return true;
      }
      var r = rowAt(my);
      if (r >= 0 && mx < trackX)
      {
        var row = rows[r];
        if (row.kind == 2) ed.trackMenu(row.track);
        else if (row.kind == 1) ed.addPropertyMenu(row.target);
      }
      return true;
    }

    if (!FlxG.mouse.justPressed) return true;

    dragStartX = mx;
    dragStartY = my;
    dragMoved = false;

    // Ruler / notes strip: scrub.
    if (my < rowsTop)
    {
      if (mx >= trackX)
      {
        dragMode = 'scrub';
        ed.seekBeat(ed.snap(Math.max(0, beatAt(mx))));
      }
      return true;
    }

    var r = rowAt(my);
    if (r < 0)
    {
      ed.clearSelection();
      return true;
    }
    var row = rows[r];
    var now = haxe.Timer.stamp();
    var doubleClick = r == lastClickRow && now - lastClickTime < 0.35;
    lastClickTime = now;
    lastClickRow = r;

    if (mx < trackX)
    {
      // Label column.
      switch (row.kind)
      {
        case 0:
          toggle(row.expandKey, row.label != 'STAGE PROPS');
        case 1:
          var indent = x + 8 + row.depth * 14;
          if (mx >= x + LABEL_W - 24) ed.addPropertyMenu(row.target);
          else if (mx < indent + 14 || doubleClick) toggle(row.expandKey, hasTracksDeep(row.target));
          else
            ed.selectTarget(row.target);
        default:
          ed.selectTrack(row.track);
      }
      return true;
    }

    // Track area.
    if (row.kind == 2)
    {
      var k = keyAt(mx, my);
      if (k != null)
      {
        if (ed.ctrl()) ed.toggleKey(k);
        else if (!ed.isKeySelected(k.key)) ed.selectKeys([k], FlxG.keys.pressed.SHIFT);
        if (ed.isKeySelected(k.key))
        {
          dragMode = 'keys';
          dragBefore = ed.doc.snapshot();
          dragOrig = [for (s in ed.selKeys) s.key.t];
          dragTracks = [];
          for (s in ed.selKeys)
            if (!dragTracks.contains(s.track)) dragTracks.push(s.track);
        }
        return true;
      }
      if (doubleClick)
      {
        ed.addKeyAt(row.track, ed.snap(Math.max(0, beatAt(mx))));
        return true;
      }
    }
    dragMode = 'box';
    boxRow = r;
    return true;
  }

  function continueDrag(mx:Float, my:Float):Void
  {
    if (Math.abs(mx - dragStartX) > 3 || Math.abs(my - dragStartY) > 3) dragMoved = true;
    switch (dragMode)
    {
      case 'scrub':
        ed.seekBeat(ed.snap(Math.max(0, beatAt(mx))));
        autoScroll(mx);
      case 'keys':
        if (dragMoved)
        {
          var delta = (mx - dragStartX) / pxPerBeat;
          if (!FlxG.keys.pressed.ALT) delta = Math.round(delta / ed.snapBeats) * ed.snapBeats;
          var minOrig = 1e9;
          for (o in dragOrig)
            minOrig = Math.min(minOrig, o);
          if (minOrig + delta < 0) delta = -minOrig;
          for (i in 0...ed.selKeys.length)
            ed.selKeys[i].key.t = Math.round((dragOrig[i] + delta) * 10000) / 10000;
          for (t in dragTracks)
            QOLModchart.sortKeys(t);
          ed.liveEdit();
          autoScroll(mx);
        }
      default:
    }
    if (!FlxG.mouse.pressed)
    {
      switch (dragMode)
      {
        case 'keys':
          if (dragMoved) ed.doc.commitFrom(dragBefore);
          ed.afterEdit();
        case 'box':
          if (dragMoved) boxSelect(Math.min(dragStartX, mx), Math.min(dragStartY, my), Math.max(dragStartX, mx), Math.max(dragStartY, my));
          else
          {
            // A plain click on empty space: move the playhead there and select the row.
            ed.clearSelection(false);
            var row = rows[boxRow];
            if (row != null)
            {
              if (row.kind == 2) ed.selectTrack(row.track);
              else if (row.kind == 1) ed.selectTarget(row.target);
            }
            ed.seekBeat(ed.snap(Math.max(0, beatAt(dragStartX))));
          }
        default:
      }
      dragMode = '';
    }
  }

  function autoScroll(mx:Float):Void
  {
    if (mx > x + width - 20) scrollBeat += 8 / pxPerBeat;
    else if (mx < trackX + 10 && scrollBeat > -2) scrollBeat -= 8 / pxPerBeat;
  }

  function boxSelect(x1:Float, y1:Float, x2:Float, y2:Float):Void
  {
    var found:Array<ModKeyRef> = [];
    for (r in 0...visibleRows)
    {
      var index = scrollRow + r;
      if (index >= rows.length) break;
      var row = rows[index];
      if (row.kind != 2) continue;
      var cy = rowY(index) + ROW_H / 2;
      if (cy < y1 || cy > y2) continue;
      for (k in row.track.keys)
      {
        var kx = xOf(k.t);
        if (kx >= x1 && kx <= x2) found.push({track: row.track, key: k});
      }
    }
    ed.selectKeys(found, FlxG.keys.pressed.SHIFT || ed.ctrl());
  }

  /**
   * Keep the playhead on screen while playing.
   */
  public function follow(beat:Float):Void
  {
    var px = xOf(beat);
    var right = x + width;
    if (px > right - 40 || px < trackX) scrollBeat = beat - (width - LABEL_W) * 0.15 / pxPerBeat;
  }

  public var dragging(get, never):Bool;

  function get_dragging():Bool
    return dragMode != '';
}
#end
