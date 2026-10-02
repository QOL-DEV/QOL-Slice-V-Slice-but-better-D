package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
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
  public static final RULER_H:Int = 22;
  public static final ROW_H:Int = 22;

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
    gKeyFull = QOLTheme.cached('anim-key-full', () -> circleBitmap(9, 0xFF101014, 0xFFE8E0FF, true));
    gKeyEmpty = QOLTheme.cached('anim-key-empty', () -> circleBitmap(9, 0xFFE8E0FF, 0xFF101014, false));
    gEyeOn = QOLTheme.cached('anim-eye-on', () -> circleBitmap(10, 0xFFE8E0FF, 0xFFE8E0FF, true));
    gEyeOff = QOLTheme.cached('anim-eye-off', () -> circleBitmap(10, 0xFF5A5470, 0xFF5A5470, false));
    gLockOn = QOLTheme.cached('anim-lock-on', () -> squareBitmap(10, 0xFFFF9F43, true));
    gLockOff = QOLTheme.cached('anim-lock-off', () -> squareBitmap(10, 0xFF5A5470, false));
    gOutline = QOLTheme.cached('anim-outline', () -> squareBitmap(10, 0xFFFFFFFF, false));
    gSquare = QOLTheme.cached('anim-square', () -> squareBitmap(10, 0xFFFFFFFF, true));

    bg = rect(0xFF17181D);
    labelBg = rect(0xFF202229);
    rulerBg = rect(0xFF26283A);
    divider = rect(0xFF3A3F4F);
    playhead = rect(0xFFFF3355);
    playheadTag = rect(0xFFFF3355);
    playheadText = QOLTheme.text(0, 0, 40, '', 10, QOLTheme.FONT_MONO, FlxColor.WHITE);
    prep(playheadText);
    title = QOLTheme.text(0, 0, LABEL_W - 16, 'TIMELINE', 12, QOLTheme.FONT_TITLE, QOLTheme.ACCENT_PINK);
    prep(title);
    add(bg);
    add(labelBg);
    add(rulerBg);
    add(layerRows);
    add(layerGrid);
    add(layerSpans);
    add(layerKeys);
    add(layerText);
    add(title);
    add(divider);
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

  function txt(x:Float, y:Float, w:Float, s:String, size:Int, color:FlxColor, ?mono:Bool = false):FlxText
  {
    var t = pooled(texts, nText++, layerText, () -> QOLTheme.text(0, 0, 10, '', 11, QOLTheme.FONT_BODY, FlxColor.WHITE));
    if (t.size != size) t.size = size;
    if (t.fieldWidth != w) t.fieldWidth = w;
    var font = mono ? QOLTheme.FONT_MONO : QOLTheme.FONT_BODY;
    if (t.font != font) t.font = font;
    if (t.text != s) t.text = s;
    t.color = color;
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

  public function redraw():Void
  {
    nSpan = nKey = nText = nIcon = nGrid = nRow = 0;
    var sym = ed.sym;
    place(bg, x, y, width, height);
    place(labelBg, x, y, LABEL_W, height);
    place(rulerBg, gridX, y, width - LABEL_W, RULER_H);
    place(divider, gridX - 1, y, 1, height);
    title.setPosition(x + 8, y + 3);

    var frames = visibleFrames;
    var rows = visibleRows;
    var bottom = y + height;

    // Ruler numbers & frame grid.
    for (i in 0...frames + 1)
    {
      var f = scrollFrame + i;
      var fx = frameX(f);
      if (fx > x + width) break;
      var major = (f + 1) % 5 == 0 || f == 0;
      var line = pooled(gridLines, nGrid++, layerGrid, () -> new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE));
      place(line, fx, y + (major ? RULER_H - 8 : RULER_H - 4), 1, (major ? 8 : 4));
      line.color = 0xFF5A5470;
      if (major)
      {
        var gl = pooled(gridLines, nGrid++, layerGrid, () -> new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE));
        place(gl, fx + cellW, y + RULER_H, 1, height - RULER_H);
        gl.color = 0xFF262833;
        if ((f + 1) % 5 == 0 || f == 0) txt(fx + 1, y + 3, 40, '${f + 1}', 10, 0xFF9A93B8, true);
      }
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
      var rowBg = pooled(rowBgs, nRow++, layerRows, () -> new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE));
      place(rowBg, x, ry, width, ROW_H - 1);
      rowBg.color = selected ? 0xFF2F3B58 : (r % 2 == 0 ? 0xFF1B1D24 : 0xFF1E2028);

      // Label column.
      span(x + 4, ry + 4, 4, ROW_H - 9, layer.color);
      var kindTag = layer.kind == 'bitmap' ? '[B] ' : '';
      var guideTag = layer.guide == true ? '(guide) ' : '';
      txt(x + 14, ry + 4, LABEL_W - 80, kindTag + guideTag + layer.name, 12, selected ? FlxColor.WHITE : 0xFFC9C2E6);
      icon(layer.visible ? gEyeOn : gEyeOff, x + LABEL_W - 56, ry + 6);
      icon(layer.locked ? gLockOn : gLockOff, x + LABEL_W - 38, ry + 6);
      icon(layer.outline == true ? gOutline : gSquare, x + LABEL_W - 20, ry + 6, layer.color);

      // Frame selection.
      if (selected && ed.selEnd >= ed.selStart)
      {
        var sx = Math.max(gridX, frameX(ed.selStart));
        var ex = frameX(ed.selEnd + 1);
        if (ex > sx) span(sx, ry, ex - sx, ROW_H - 1, 0xFF3D6BFF, 0.35);
      }

      // Keyframes.
      for (k in layer.frames)
      {
        var kx = frameX(k.start);
        var kw = k.duration * cellW;
        if (kx > x + width || kx + kw < gridX) continue;
        var has = k.elements.length > 0 || (layer.kind == 'bitmap' && k.bitmap != null);
        var color:FlxColor = k.tween != null ? 0xFF5B4B9A : (has ? 0xFF3A3F4F : 0xFF26282F);
        var sx = Math.max(gridX, kx + 1);
        var ex = Math.min(x + width, kx + kw);
        if (ex > sx) span(sx, ry + 2, ex - sx - 1, ROW_H - 5, color);
        if (k.tween != null && kw > cellW * 2)
        {
          // Tween arrow line.
          var lx = Math.max(gridX, kx + cellW);
          var lw = Math.min(x + width, kx + kw - cellW / 2) - lx;
          if (lw > 0) span(lx, ry + ROW_H / 2 - 1, lw, 1, 0xFFE8E0FF);
        }
        if (kx >= gridX - 1)
        {
          var key = pooled(keys, nKey++, layerKeys, () -> new FlxSprite());
          var g = has ? gKeyFull : gKeyEmpty;
          if (key.graphic != g) key.loadGraphic(g);
          key.setPosition(kx + (cellW - 9) / 2, ry + (ROW_H - 9) / 2 - 1);
          key.color = FlxColor.WHITE;
        }
        // End of span.
        if (k.duration > 1)
        {
          var endX = frameX(k.start + k.duration - 1);
          if (endX >= gridX && endX < x + width) span(endX + cellW / 2 - 3, ry + ROW_H - 9, 6, 5, 0xFF8A86A8);
        }
        if (k.label != null && k.label != '' && kx >= gridX) txt(kx + 10, ry + 3, Math.max(20, kw - 10), k.label, 10, 0xFFFF8FB8);
      }
    }

    // Symbol end.
    var endX = frameX(lengthAll);
    if (endX >= gridX && endX <= x + width) span(endX, y + RULER_H, 1, height - RULER_H, 0xFF7CE38B, 0.6);

    // Playhead.
    var px = frameX(ed.frame);
    playhead.visible = playheadTag.visible = playheadText.visible = px >= gridX - 1 && px <= x + width;
    if (playhead.visible)
    {
      place(playhead, px + cellW / 2, y + RULER_H, 1, height - RULER_H);
      place(playheadTag, px, y + 1, Math.max(cellW, 24), RULER_H - 3);
      playheadText.text = '${ed.frame + 1}';
      playheadText.setPosition(px + 2, y + 4);
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
