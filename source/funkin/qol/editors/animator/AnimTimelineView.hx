package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextAlign;
import flixel.util.FlxColor;
import funkin.qol.editors.animator.AnimData;
import funkin.qol.ui.QOLTheme;
import openfl.display.BitmapData;
import openfl.display.Shape;

/**
 * The Animator's timeline: layers on the left (with show/lock/outline toggles), frames on the right with keyframes,
 * frame spans and classic tweens, a frame ruler and the playhead. Flash-style.
 */
class AnimTimelineView extends FlxGroup
{
  public static final LABEL_W:Int = 236;
  public static final RULER_H:Int = 24;
  public static final ROW_H:Int = 24;

  public var x:Float = 0;
  public var y:Float = 0;
  public var width:Float = 100;
  public var height:Float = 100;

  public var cellW:Float = 14;
  public var scrollFrame:Int = 0;
  public var scrollRow:Int = 0;

  var ed:AnimatorState;
  var cam:FlxCamera;

  var bg:FlxSprite;
  var labelBg:FlxSprite;
  var rulerBg:FlxSprite;
  var divider:FlxSprite;
  var playhead:FlxSprite;
  var playheadTag:FlxSprite;
  var playheadText:FlxText;
  var title:FlxText;

  var layerRows:FlxGroup = new FlxGroup();
  var layerGrid:FlxGroup = new FlxGroup();
  var layerSpans:FlxGroup = new FlxGroup();
  var layerKeys:FlxGroup = new FlxGroup();
  var layerText:FlxGroup = new FlxGroup();

  var rowBgs:Array<FlxSprite> = [];
  var gridLines:Array<FlxSprite> = [];
  var spans:Array<FlxSprite> = [];
  var keys:Array<FlxSprite> = [];
  var texts:Array<FlxText> = [];
  var rulerTexts:Array<FlxText> = [];
  var icons:Array<FlxSprite> = [];

  var gKeyFull:FlxGraphic;
  var gKeyEmpty:FlxGraphic;
  var gEyeOn:FlxGraphic;
  var gEyeOff:FlxGraphic;
  var gLockOn:FlxGraphic;
  var gLockOff:FlxGraphic;
  var gOutline:FlxGraphic;
  var gSquare:FlxGraphic;
  var gPen:FlxGraphic;
  var gPixels:FlxGraphic;
  var gGuide:FlxGraphic;
  var gTag:FlxGraphic;
  var gArrow:FlxGraphic;
  var playheadGlow:FlxSprite;
  var subtitle:FlxText;

  // Input.
  var drag:String = '';
  var dragLayer:Int = -1;
  var dragKey:Null<AnimKeyframe> = null;
  var dragKeyStart:Int = 0;
  var dragFrame0:Int = 0;
  var dragMoved:Bool = false;
  var lastClick:Float = 0;
  var lastClickLayer:Int = -1;

  public function new(ed:AnimatorState, cam:FlxCamera)
  {
    super();
    this.ed = ed;
    this.cam = cam;
    gKeyFull = QOLTheme.cached('anim-key-full2', () -> circleBitmap(11, 0xFF1A1030, 0xFFFFFFFF, true));
    gKeyEmpty = QOLTheme.cached('anim-key-empty2', () -> circleBitmap(11, 0xFFFFFFFF, 0xFFFFFFFF, false));
    gEyeOn = AnimatorSkin.iconGraphic('eye', 14, 0xFFEDE6FF, false);
    gEyeOff = AnimatorSkin.iconGraphic('eye-off', 14, 0xFF5E5488, false);
    gLockOn = AnimatorSkin.iconGraphic('lock', 14, 0xFFFFA43D, false);
    gLockOff = AnimatorSkin.iconGraphic('unlock', 14, 0xFF5E5488, false);
    gOutline = AnimatorSkin.iconGraphic('outline', 14, 0xFFFFFFFF, false);
    gSquare = AnimatorSkin.iconGraphic('solid', 14, 0xFFFFFFFF, false);
    gPen = AnimatorSkin.iconGraphic('pen', 14, 0xFFFFFFFF, false);
    gPixels = AnimatorSkin.iconGraphic('pixels', 14, 0xFFFFFFFF, false);
    gGuide = AnimatorSkin.iconGraphic('guide', 14, 0xFFFFFFFF, false);
    gArrow = QOLTheme.cached('anim-tween-arrow', () -> {
      var sh = new Shape();
      sh.graphics.beginFill(0xFFFFFF, 1);
      sh.graphics.moveTo(0, 0);
      sh.graphics.lineTo(8, 5);
      sh.graphics.lineTo(0, 10);
      sh.graphics.lineTo(0, 0);
      sh.graphics.endFill();
      var b = new BitmapData(9, 11, true, 0);
      b.draw(sh, null, null, null, null, true);
      return b;
    });
    gTag = QOLTheme.cached('anim-playhead-tag', () -> QOLTheme.drawRound(34, RULER_H - 4, 0xFFFF5C9D, 8, 0xFFFFB3D1, 1.5));

    bg = rect(0xFF140F26);
    labelBg = rect(0xFF1B1533);
    rulerBg = rect(0xFF221A40);
    divider = rect(0xFF3D3366);
    playheadGlow = rect(0xFFFF5C9D);
    playhead = rect(0xFFFF5C9D);
    playheadTag = prep(new FlxSprite().loadGraphic(gTag));
    playheadText = QOLTheme.text(0, 0, 34, '', 11, QOLTheme.FONT_TITLE, FlxColor.WHITE);
    playheadText.alignment = CENTER;
    prep(playheadText);
    title = QOLTheme.text(0, 0, LABEL_W - 16, 'TIMELINE', 13, QOLTheme.FONT_TITLE, QOLTheme.ACCENT_PINK);
    prep(title);
    subtitle = QOLTheme.text(0, 0, LABEL_W - 16, '', 10, QOLTheme.FONT_BODY, 0xFF8C80BF);
    subtitle.alignment = RIGHT;
    prep(subtitle);
    add(bg);
    add(labelBg);
    add(rulerBg);
    add(layerRows);
    add(layerGrid);
    add(layerSpans);
    add(layerKeys);
    add(layerText);
    add(title);
    add(subtitle);
    add(divider);
    add(playheadGlow);
    add(playhead);
    add(playheadTag);
    add(playheadText);
  }

  static function circleBitmap(size:Int, line:Int, fill:Int, filled:Bool):BitmapData
  {
    var s = new Shape();
    if (filled) s.graphics.beginFill(fill & 0xFFFFFF, 1);
    s.graphics.lineStyle(1.5, line & 0xFFFFFF, 1);
    s.graphics.drawCircle(size / 2, size / 2, size / 2 - 1);
    if (filled) s.graphics.endFill();
    var b = new BitmapData(size, size, true, 0);
    b.draw(s, null, null, null, null, true);
    return b;
  }

  static function squareBitmap(size:Int, color:Int, filled:Bool):BitmapData
  {
    var s = new Shape();
    if (filled) s.graphics.beginFill(color & 0xFFFFFF, 1);
    s.graphics.lineStyle(1.5, color & 0xFFFFFF, 1);
    s.graphics.drawRect(1, 1, size - 2, size - 2);
    if (filled) s.graphics.endFill();
    var b = new BitmapData(size, size, true, 0);
    b.draw(s, null, null, null, null, true);
    return b;
  }

  function prep<T:FlxSprite>(s:T):T
  {
    s.cameras = [cam];
    s.scrollFactor.set();
    return s;
  }

  function rect(color:FlxColor):FlxSprite
  {
    var s = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
    s.color = color;
    return prep(s);
  }

  static function place(s:FlxSprite, x:Float, y:Float, w:Float, h:Float):Void
  {
    s.setGraphicSize(Std.int(Math.max(1, w)), Std.int(Math.max(1, h)));
    s.updateHitbox();
    s.setPosition(x, y);
    s.visible = true;
  }

  public function setBounds(x:Float, y:Float, w:Float, h:Float):Void
  {
    this.x = x;
    this.y = y;
    this.width = w;
    this.height = h;
  }

  public var gridX(get, never):Float;

  inline function get_gridX():Float
    return x + LABEL_W;

  public var visibleFrames(get, never):Int;

  inline function get_visibleFrames():Int
    return Std.int((width - LABEL_W) / cellW) + 1;

  public var visibleRows(get, never):Int;

  inline function get_visibleRows():Int
    return Std.int((height - RULER_H) / ROW_H) + 1;

  public function frameX(f:Float):Float
    return gridX + (f - scrollFrame) * cellW;

  public function frameAt(px:Float):Int
    return Std.int(Math.floor((px - gridX) / cellW)) + scrollFrame;

  public function rowY(row:Int):Float
    return y + RULER_H + (row - scrollRow) * ROW_H;

  public function rowAt(py:Float):Int
    return Std.int(Math.floor((py - y - RULER_H) / ROW_H)) + scrollRow;

  /**
   * Keep the playhead in view.
   */
  public function follow(frame:Int):Void
  {
    if (frame < scrollFrame) scrollFrame = frame;
    if (frame >= scrollFrame + visibleFrames - 2) scrollFrame = frame - visibleFrames + 3;
    if (scrollFrame < 0) scrollFrame = 0;
  }

  //
  // Drawing
  //

  var nSpan:Int = 0;
  var nKey:Int = 0;
  var nText:Int = 0;
  var nIcon:Int = 0;
  var nGrid:Int = 0;
  var nRow:Int = 0;

  function pooled<T:FlxSprite>(pool:Array<T>, idx:Int, group:FlxGroup, make:Void->T):T
  {
    while (pool.length <= idx)
    {
      var s = prep(make());
      pool.push(s);
      group.add(s);
    }
    var s = pool[idx];
    s.visible = true;
    return s;
  }

  function txt(x:Float, y:Float, w:Float, s:String, size:Int, color:FlxColor, ?mono:Bool = false, ?center:Bool = false):FlxText
  {
    var t = pooled(texts, nText++, layerText, () -> QOLTheme.text(0, 0, 10, '', 11, QOLTheme.FONT_BODY, FlxColor.WHITE));
    if (t.size != size) t.size = size;
    if (t.fieldWidth != w) t.fieldWidth = w;
    var font = mono ? QOLTheme.FONT_MONO : QOLTheme.FONT_BODY;
    if (t.font != font) t.font = font;
    if (t.text != s) t.text = s;
    t.color = color;
    var align:FlxTextAlign = center ? CENTER : LEFT;
    if (t.alignment != align) t.alignment = align;
    t.setPosition(x, y);
    return t;
  }

  function icon(g:FlxGraphic, x:Float, y:Float, ?color:FlxColor = FlxColor.WHITE):FlxSprite
  {
    var s = pooled(icons, nIcon++, layerKeys, () -> new FlxSprite());
    if (s.graphic != g) s.loadGraphic(g);
    s.color = color;
    s.setPosition(x, y);
    return s;
  }

  function span(x:Float, y:Float, w:Float, h:Float, color:FlxColor, ?alpha:Float = 1):FlxSprite
  {
    var s = pooled(spans, nSpan++, layerSpans, () -> new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE));
    place(s, x, y, w, h);
    s.color = color;
    s.alpha = alpha;
    return s;
  }

  static inline function mix(a:Int, b:Int, t:Float):FlxColor
    return AnimRender.lerpColor(a | 0xFF000000, b | 0xFF000000, t);

  public function redraw():Void
  {
    nSpan = nKey = nText = nIcon = nGrid = nRow = 0;
    var sym = ed.sym;
    place(bg, x, y, width, height);
    place(labelBg, x, y, LABEL_W, height);
    place(rulerBg, gridX, y, width - LABEL_W, RULER_H);
    place(divider, gridX - 1, y, 1, height);
    title.setPosition(x + 10, y + 4);
    var layerCount = sym.layers.length;
    var sub = '$layerCount layer${layerCount == 1 ? '' : 's'} \u00B7 ${AnimData.symbolLength(sym)}f';
    if (subtitle.text != sub) subtitle.text = sub;
    subtitle.setPosition(x + 8, y + 6);
    subtitle.fieldWidth = LABEL_W - 18;

    var frames = visibleFrames;
    var rows = visibleRows;
    var bottom = y + height;
    var mp = FlxG.mouse.getViewPosition(cam);
    var mx = mp.x, my = mp.y;
    mp.put();
    var hoverFrame = contains(mx, my) && mx >= gridX && drag == '' ? frameAt(mx) : -1;
    var hoverRow = hoverFrame >= 0 ? rowAt(my) : -1;

    // Every fifth frame gets a lighter column, like Flash.
    for (i in 0...frames + 1)
    {
      var f = scrollFrame + i;
      var fx = frameX(f);
      if (fx > x + width) break;
      if ((f + 1) % 5 == 0) span(fx, y + RULER_H, Math.min(cellW, x + width - fx), height - RULER_H, 0xFFFFFFFF, 0.035);
    }

    // Ruler numbers & ticks.
    for (i in 0...frames + 1)
    {
      var f = scrollFrame + i;
      var fx = frameX(f);
      if (fx > x + width) break;
      var major = (f + 1) % 5 == 0 || f == 0;
      var line = pooled(gridLines, nGrid++, layerGrid, () -> new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE));
      place(line, fx + cellW / 2, y + (major ? RULER_H - 7 : RULER_H - 4), 1, (major ? 7 : 4));
      line.color = major ? 0xFF8C80BF : 0xFF4A3F78;
      if (major && f != ed.frame) txt(fx + cellW / 2 - 15, y + 5, 30, '${f + 1}', 10, 0xFFA99CD6, true, true);
    }

    // Layers.
    var lengthAll = AnimData.symbolLength(sym);
    for (r in 0...rows)
    {
      var li = scrollRow + r;
      if (li >= sym.layers.length) break;
      var layer = sym.layers[li];
      var ry = rowY(li);
      if (ry + ROW_H > bottom + 1) break;
      var selected = li == ed.curLayer;
      var baseBg:Int = r % 2 == 0 ? 0xFF181230 : 0xFF1C1636;
      var rowColor:Int = selected ? mix(baseBg, layer.color, 0.22) : baseBg;
      var rowBg = pooled(rowBgs, nRow++, layerRows, () -> new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE));
      place(rowBg, x, ry, width, ROW_H - 1);
      rowBg.color = rowColor;

      // Label column.
      span(x + 4, ry + 3, 4, ROW_H - 7, layer.color);
      if (selected) span(x + 8, ry + 3, 2, ROW_H - 7, layer.color, 0.35);
      icon(layer.guide == true ? gGuide : (layer.kind == 'bitmap' ? gPixels : gPen), x + 14, ry + 5, mix(layer.color, 0xFFFFFFFF, 0.25));
      txt(x + 33, ry + 4, LABEL_W - 100, layer.name, 12, selected ? FlxColor.WHITE : (layer.visible ? 0xFFC9C2E6 : 0xFF6E6497));
      icon(layer.visible ? gEyeOn : gEyeOff, x + LABEL_W - 60, ry + 5);
      icon(layer.locked ? gLockOn : gLockOff, x + LABEL_W - 41, ry + 5);
      icon(layer.outline == true ? gOutline : gSquare, x + LABEL_W - 22, ry + 5, layer.color);

      // Frame selection.
      if (selected && ed.selEnd >= ed.selStart)
      {
        var sx = Math.max(gridX, frameX(ed.selStart));
        var ex = frameX(ed.selEnd + 1);
        if (ex > sx) span(sx, ry, ex - sx, ROW_H - 1, 0xFF5CE1FF, 0.22);
      }

      // Keyframe spans and dots.
      for (k in layer.frames)
      {
        var kx = frameX(k.start);
        var kw = k.duration * cellW;
        if (kx > x + width || kx + kw < gridX) continue;
        var has = k.elements.length > 0 || (layer.kind == 'bitmap' && k.bitmap != null);
        var color:FlxColor = k.tween != null ? mix(rowColor, 0xFF9B6BFF, 0.55) : (has ? mix(rowColor, layer.color, 0.32) : mix(rowColor, 0xFF3D3366, 0.5));
        var sx = Math.max(gridX, kx + 1);
        var ex = Math.min(x + width, kx + kw);
        if (ex > sx) span(sx, ry + 3, ex - sx - 1, ROW_H - 7, color);
        if (k.tween != null && kw > cellW * 2)
        {
          // Tween arrow.
          var lx = Math.max(gridX, kx + cellW);
          var lw = Math.min(x + width, kx + kw - cellW * 0.7) - lx;
          if (lw > 0) span(lx, ry + ROW_H / 2 - 1, lw, 2, 0xFFEDE6FF, 0.85);
          var hx = kx + kw - cellW * 0.7;
          if (hx > gridX && hx < x + width) icon(gArrow, hx - 4, ry + ROW_H / 2 - 5.5, 0xFFEDE6FF);
        }
        if (kx >= gridX - 1)
        {
          var key = pooled(keys, nKey++, layerKeys, () -> new FlxSprite());
          var g = has ? gKeyFull : gKeyEmpty;
          if (key.graphic != g) key.loadGraphic(g);
          key.setPosition(kx + (cellW - 11) / 2, ry + (ROW_H - 11) / 2 - 1);
          key.color = has ? mix(layer.color, 0xFFFFFFFF, 0.35) : mix(layer.color, 0xFFFFFFFF, 0.5);
        }
        // End of a span.
        if (k.duration > 1)
        {
          var endX = frameX(k.start + k.duration - 1);
          if (endX >= gridX && endX < x + width) span(endX + cellW / 2 - 3, ry + ROW_H - 10, 6, 5, mix(layer.color, 0xFFFFFFFF, 0.4), 0.8);
        }
        if (k.label != null && k.label != '' && kx >= gridX) txt(kx + 12, ry + 4, Math.max(20, kw - 12), k.label, 10, 0xFFFFD84A);
      }

      // Hover cell.
      if (hoverRow == li && hoverFrame >= 0) span(frameX(hoverFrame), ry, cellW, ROW_H - 1, 0xFFFFFFFF, 0.08);
    }

    // "+ New layer" row and tips in the empty space below the layers.
    var nextRow = sym.layers.length;
    var ny = rowY(nextRow);
    if (nextRow >= scrollRow && ny + ROW_H <= bottom)
    {
      var hoverNew = contains(mx, my) && mx < gridX && rowAt(my) == nextRow && drag == '';
      if (hoverNew) span(x, ny, LABEL_W, ROW_H - 1, 0xFFFF5C9D, 0.18);
      txt(x + 14, ny + 4, LABEL_W - 20, '+  New layer', 12, hoverNew ? 0xFFFFFFFF : 0xFFFF8FC0);
      if (ny + ROW_H * 2.5 <= bottom)
        txt(gridX + 12, bottom - 22, width - LABEL_W - 24,
          'Drag keyframes to move them  \u00B7  Right-click frames for more  \u00B7  Double-click a layer to rename it  \u00B7  Ctrl + wheel zooms the timeline', 10,
          0xFF5E5488);
    }

    // Symbol end.
    var endX = frameX(lengthAll);
    if (endX >= gridX && endX <= x + width) span(endX, y + RULER_H, 2, height - RULER_H, 0xFF6BE38E, 0.5);

    // Playhead.
    var px = frameX(ed.frame);
    var show = px >= gridX - 1 && px <= x + width;
    playhead.visible = playheadGlow.visible = playheadTag.visible = playheadText.visible = show;
    if (show)
    {
      var cx = px + cellW / 2;
      place(playheadGlow, cx - 3, y + RULER_H - 2, 6, height - RULER_H + 2);
      playheadGlow.alpha = ed.playing ? 0.3 + Math.sin(haxe.Timer.stamp() * 8) * 0.12 : 0.22;
      place(playhead, cx - 1, y + RULER_H - 2, 2, height - RULER_H + 2);
      playheadTag.setPosition(Math.round(cx - 17), y + 2);
      playheadText.text = '${ed.frame + 1}';
      playheadText.setPosition(Math.round(cx - 17), y + 4);
    }

    hide(rowBgs, nRow);
    hide(gridLines, nGrid);
    hide(spans, nSpan);
    hide(keys, nKey);
    hide(texts, nText);
    hide(icons, nIcon);
  }

  static function hide<T:FlxSprite>(pool:Array<T>, from:Int):Void
  {
    for (i in from...pool.length)
      pool[i].visible = false;
  }

  //
  // Mouse
  //

  public function contains(mx:Float, my:Float):Bool
    return mx >= x && mx < x + width && my >= y && my < y + height;

  /**
   * Returns true if the timeline used the mouse this frame.
   */
  public function handleMouse(mx:Float, my:Float):Bool
  {
    var sym = ed.sym;
    if (drag != '')
    {
      if (FlxG.mouse.pressed)
      {
        var f = Std.int(Math.max(0, frameAt(mx)));
        switch (drag)
        {
          case 'scrub':
            ed.setFrame(f);
          case 'select':
            ed.selectFrames(dragLayer, Std.int(Math.min(dragFrame0, f)), Std.int(Math.max(dragFrame0, f)));
            ed.setFrame(f, false);
          case 'key':
            if (dragKey != null && f != dragFrame0)
            {
              if (!dragMoved) ed.doc.checkpoint();
              dragMoved = true;
              ed.moveKeyframe(dragLayer, dragKey, dragKeyStart + (f - dragFrame0));
            }
          case 'layer':
            var r = rowAt(my);
            if (r >= 0 && r < sym.layers.length && r != dragLayer)
            {
              ed.moveLayer(dragLayer, r);
              dragLayer = r;
            }
        }
        autoScroll(mx);
      }
      else
      {
        if (drag == 'key' && dragMoved) ed.afterTimelineEdit();
        drag = '';
      }
      return true;
    }

    if (!contains(mx, my)) return false;

    // Wheel: scroll frames (or layers with Shift); Ctrl zooms.
    if (FlxG.mouse.wheel != 0)
    {
      if (FlxG.keys.pressed.CONTROL) cellW = Math.max(6, Math.min(40, cellW + (FlxG.mouse.wheel > 0 ? 2 : -2)));
      else if (FlxG.keys.pressed.SHIFT || mx < gridX) scrollRow = Std.int(Math.max(0, Math.min(sym.layers.length - 1, scrollRow - FlxG.mouse.wheel)));
      else
        scrollFrame = Std.int(Math.max(0, scrollFrame - FlxG.mouse.wheel * 3));
    }

    if (!FlxG.mouse.justPressed && !FlxG.mouse.justPressedRight) return true;

    var row = rowAt(my);
    var onRuler = my < y + RULER_H;
    if (onRuler && mx >= gridX)
    {
      drag = 'scrub';
      ed.setFrame(Std.int(Math.max(0, frameAt(mx))));
      return true;
    }
    if (row == sym.layers.length && mx < gridX && FlxG.mouse.justPressed)
    {
      ed.addLayer('vector');
      return true;
    }
    if (row < 0 || row >= sym.layers.length)
    {
      if (mx >= gridX) ed.setFrame(Std.int(Math.max(0, frameAt(mx))));
      return true;
    }

    if (mx < gridX)
    {
      // Label column: toggles, select, rename (double-click), drag to reorder.
      var layer = sym.layers[row];
      if (mx >= x + LABEL_W - 60 && mx < x + LABEL_W - 42) ed.toggleLayer(row, 'visible');
      else if (mx >= x + LABEL_W - 42 && mx < x + LABEL_W - 24) ed.toggleLayer(row, 'locked');
      else if (mx >= x + LABEL_W - 24) ed.toggleLayer(row, 'outline');
      else
      {
        var now = haxe.Timer.stamp();
        if (lastClickLayer == row && now - lastClick < 0.4) ed.renameLayer(row);
        else
        {
          ed.selectLayer(row);
          drag = 'layer';
          dragLayer = row;
        }
        lastClick = now;
        lastClickLayer = row;
      }
      return true;
    }

    var f = Std.int(Math.max(0, frameAt(mx)));
    var layer = sym.layers[row];
    if (FlxG.mouse.justPressedRight)
    {
      ed.selectLayer(row);
      if (f < ed.selStart || f > ed.selEnd) ed.selectFrames(row, f, f);
      ed.setFrame(f, false);
      ed.openFrameMenu();
      return true;
    }
    ed.selectLayer(row);
    // Dragging a keyframe moves it; dragging elsewhere selects frames.
    var key = AnimData.keyAt(layer, f);
    if (key != null && key.start == f && !layer.locked && !FlxG.keys.pressed.SHIFT)
    {
      drag = 'key';
      dragKey = key;
      dragKeyStart = key.start;
      dragFrame0 = f;
      dragLayer = row;
      dragMoved = false;
      ed.selectFrames(row, f, f);
      ed.setFrame(f, false);
      return true;
    }
    if (FlxG.keys.pressed.SHIFT && ed.selEnd >= ed.selStart)
    {
      ed.selectFrames(row, Std.int(Math.min(ed.selStart, f)), Std.int(Math.max(ed.selEnd, f)));
      ed.setFrame(f, false);
      return true;
    }
    drag = 'select';
    dragLayer = row;
    dragFrame0 = f;
    ed.selectFrames(row, f, f);
    ed.setFrame(f, false);
    return true;
  }

  function autoScroll(mx:Float):Void
  {
    if (mx > x + width - 10) scrollFrame++;
    if (mx < gridX + 4 && scrollFrame > 0) scrollFrame--;
  }

  public var dragging(get, never):Bool;

  inline function get_dragging():Bool
    return drag != '';
}
#end
