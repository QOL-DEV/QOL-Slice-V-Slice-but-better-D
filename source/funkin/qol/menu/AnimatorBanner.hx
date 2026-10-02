package funkin.qol.menu;

import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.qol.ui.QOLFlxButton;
import funkin.qol.ui.QOLTheme;
import openfl.display.BitmapData;
import openfl.display.Shape;
import openfl.geom.Matrix;

/**
 * The big banner for the Animator at the top of the Mod Menu.
 *
 * It shows a tiny "Flash" scene playing in time with the menu music: Boyfriend hops across a
 * white stage along a motion path with squash & stretch and onion-skin ghosts, Girlfriend bops
 * on another layer, and a timeline with keyframes, tween spans and a playhead runs underneath.
 *
 * Everything static (background, stage, motion path, timeline) is baked into cached bitmaps once,
 * so each frame only moves a handful of sprites.
 *
 * Drop a `qol/hub/animator-banner.png` into the engine assets to replace the artwork.
 */
class AnimatorBanner extends FlxSpriteGroup
{
  static inline final STAGE_W:Int = 404;
  static inline final STAGE_H:Int = 158;
  static inline final CANVAS_H:Int = 100;
  static inline final FRAMES:Int = 24;
  static inline final BEATS_PER_LOOP:Int = 4;
  static inline final LABEL_W:Int = 30;
  static inline final BF_SCALE:Float = 1.6;

  public var button:QOLFlxButton;

  var bw:Int;
  var bh:Int;
  var custom:Bool = false;
  var fancy:Bool;

  var glow:FlxSprite;
  var bg:FlxSprite;

  // Local position of the mini stage inside the banner.
  var sx:Float;
  var sy:Float;

  var bf:FlxSprite;
  var ghosts:Array<FlxSprite> = [];
  var ghostOffsets:Array<Float> = [-0.16, -0.32, -0.48, 0.22];
  var gf:FlxSprite;
  var gfPop:Float = 0;
  var gfSide:Int = 1;
  var playhead:FlxSprite;
  var cellHighlight:FlxSprite;
  var frameText:FlxText;
  var lastFrame:Int = -1;
  var sparkles:Array<FlxSprite> = [];
  var sparkleTimers:Array<Float> = [];
  var glowPulse:Float = 0;
  var selected:Bool = false;
  var fallbackTime:Float = 0;

  public function new(x:Float, y:Float, width:Int, height:Int, onOpen:Void->Void)
  {
    super(x, y);
    bw = width;
    bh = height;
    fancy = funkin.qol.QOLConfig.fancyMenus;

    glow = QOLTheme.outline(width + 14, height + 14, 0xFFFFFFFF, 24, 5);
    glow.setPosition(-7, -7);
    glow.visible = false;
    add(glow);

    var shadow = QOLTheme.shadow(width, height, 20, 0.5);
    shadow.setPosition(0, 8);
    add(shadow);

    var customKey = 'qol/hub/animator-banner';
    custom = Assets.exists(Paths.image(customKey));

    if (custom)
    {
      bg = new FlxSprite().loadGraphic(Paths.image(customKey));
      bg.setGraphicSize(width, height);
      bg.updateHitbox();
      bg.antialiasing = true;
      add(bg);
      button = new QOLFlxButton(20, height - 52, 230, 40, 'OPEN ANIMATOR  [A]', onOpen, 0xFFFF4F9A, 16);
      add(button);
      return;
    }

    bg = new FlxSprite().loadGraphic(QOLTheme.cached('qol-animator-banner-bg-$width-$height', () -> drawBackground(width, height)));
    bg.antialiasing = true;
    add(bg);

    // Left side: title & pitch.
    var title = QOLTheme.outlinedText(22, 22, 460, 'QOL ANIMATOR', 44, FlxColor.WHITE, 4);
    add(title);
    var tagline = QOLTheme.outlinedText(26, 74, 470, 'A Flash-style animation studio, built right into the engine.', 15, 0xFFFFE9F6, 2);
    add(tagline);

    var pillX:Float = 26;
    for (pill in ['Timeline', 'Tweens', 'Vector + Bitmap', 'Filters & Blends'])
    {
      var t = QOLTheme.text(0, 0, 0, pill, 12, QOLTheme.FONT_TITLE, FlxColor.WHITE);
      var pw = Std.int(t.width + 18);
      var p = QOLTheme.roundRect(pw, 20, 0x55FFFFFF, 10);
      p.setPosition(pillX, 98);
      t.setPosition(pillX + 9, 100);
      add(p);
      add(t);
      pillX += pw + 6;
    }

    // Members are positioned locally; FlxSpriteGroup offsets them by the group position when added.
    button = new QOLFlxButton(26, 138, 214, 32, 'OPEN ANIMATOR  [A]', onOpen, 0xFFFF4F9A, 15);
    add(button);

    buildMiniStage();

    if (fancy)
    {
      for (i in 0...3)
      {
        var s = new FlxSprite();
        s.frames = Paths.getSparrowAtlas('freeplay/sparkle');
        s.animation.addByPrefix('sparkle', 'sparkle Export', 24, false);
        s.blend = ADD;
        s.antialiasing = true;
        s.visible = false;
        add(s);
        sparkles.push(s);
        sparkleTimers.push(0.4 + i * 0.7);
      }
    }
  }

  function drawBackground(width:Int, height:Int):BitmapData
  {
    var shape = new Shape();
    var g = shape.graphics;
    // Outline.
    g.beginFill(0x1A1030, 1);
    g.drawRoundRect(0, 0, width, height, 40, 40);
    g.endFill();
    // Sunset gradient.
    var m = new Matrix();
    m.createGradientBox(width, height, 0.25);
    g.beginGradientFill(LINEAR, [0x2B1055, 0xB5179E, 0xFF6F59], [1, 1, 1], [0, 150, 255], m);
    g.drawRoundRect(3, 3, width - 6, height - 6, 36, 36);
    g.endFill();
    var bmp = new BitmapData(width, height, true, 0);
    bmp.draw(shape, null, null, null, null, true);

    // Baked diagonal stripes, masked to the rounded shape.
    var stripes = new Shape();
    stripes.graphics.beginFill(0xFFFFFF, 0.06);
    var step = 46;
    var i = -height;
    while (i < width + height)
    {
      stripes.graphics.moveTo(i, height);
      stripes.graphics.lineTo(i + 18, height);
      stripes.graphics.lineTo(i + 18 + height, 0);
      stripes.graphics.lineTo(i + height, 0);
      i += step;
    }
    stripes.graphics.endFill();
    var stripeBmp = new BitmapData(width, height, true, 0);
    stripeBmp.draw(stripes, null, null, null, null, true);
    bmp.copyPixels(stripeBmp, stripeBmp.rect, new openfl.geom.Point(0, 0), bmp, new openfl.geom.Point(0, 0), true);
    // Top gloss.
    var gloss = new Shape();
    gloss.graphics.beginFill(0xFFFFFF, 0.08);
    gloss.graphics.drawRoundRect(8, 6, width - 16, height * 0.42, 30, 30);
    gloss.graphics.endFill();
    bmp.draw(gloss, null, null, null, null, true);
    return bmp;
  }

  //
  // The mini Flash scene
  //

  function buildMiniStage()
  {
    sx = bw - STAGE_W - 16;
    sy = (bh - STAGE_H) / 2;

    var stage = new FlxSprite().loadGraphic(QOLTheme.cached('qol-animator-banner-stage', () -> drawStage()));
    stage.setPosition(sx, sy);
    stage.antialiasing = true;
    add(stage);

    for (i in 0...ghostOffsets.length)
    {
      var g = makePixelSprite('freeplay/icons/bfpixel', BF_SCALE);
      g.color = ghostOffsets[i] < 0 ? 0xFF5B8CFF : 0xFF43C76A;
      g.alpha = ghostOffsets[i] < 0 ? 0.42 - i * 0.11 : 0.3;
      ghosts.push(g);
      add(g);
    }

    gf = makePixelSprite('freeplay/icons/gfpixel', 1.7);
    gf.setPosition(sx + STAGE_W - 20 - gf.width, sy + 12 + CANVAS_H - 18 - gf.height);
    add(gf);

    bf = makePixelSprite('freeplay/icons/bfpixel', BF_SCALE);
    add(bf);

    var cellW = (STAGE_W - 16 - LABEL_W) / FRAMES;
    cellHighlight = new FlxSprite().makeGraphic(Std.int(cellW), 32, 0x70FF4F7B);
    add(cellHighlight);

    playhead = new FlxSprite().makeGraphic(2, 40, 0xFFFF3355);
    add(playhead);

    frameText = QOLTheme.text(sx + STAGE_W - 150, sy + 14, 140, '', 11, QOLTheme.FONT_MONO, 0xFF6A5C8F);
    frameText.alignment = RIGHT;
    add(frameText);
  }

  function makePixelSprite(key:String, scale:Float):FlxSprite
  {
    var s = new FlxSprite();
    s.frames = Paths.getSparrowAtlas(key);
    s.animation.addByPrefix('idle', 'idle', 24, false);
    s.animation.play('idle');
    s.scale.set(scale, scale);
    s.updateHitbox();
    s.antialiasing = false;
    return s;
  }

  /**
   * Where Boyfriend is (in canvas coordinates) at a given position in the loop (beats).
   */
  function bfPath(beat:Float):{x:Float, y:Float, sx:Float, sy:Float}
  {
    beat = ((beat % BEATS_PER_LOOP) + BEATS_PER_LOOP) % BEATS_PER_LOOP;
    var hop = beat - Math.floor(beat);
    var leftX = 18.0;
    var rightX = STAGE_W - 16 - 196.0;
    // Two hops right, two hops back.
    var progress = beat < 2 ? beat / 2 : (4 - beat) / 2;
    var px = leftX + (rightX - leftX) * (progress * progress * (3 - 2 * progress));
    var ground = CANVAS_H - 10.0;
    var height = Math.sin(hop * Math.PI) * 38;
    var squash = 0.0;
    if (hop < 0.12) squash = 1 - hop / 0.12;
    else if (hop > 0.9) squash = (hop - 0.9) / 0.1;
    var stretch = Math.sin(hop * Math.PI);
    return {
      x: px,
      y: ground - height,
      sx: 1 + squash * 0.28 - stretch * 0.1,
      sy: 1 - squash * 0.24 + stretch * 0.12
    };
  }

  function drawStage():BitmapData
  {
    var w = STAGE_W;
    var h = STAGE_H;
    var shape = new Shape();
    var g = shape.graphics;
    // Panel.
    g.beginFill(0x1A1030, 1);
    g.drawRoundRect(0, 0, w, h, 24, 24);
    g.endFill();
    g.beginFill(0x2A1F45, 1);
    g.drawRoundRect(3, 3, w - 6, h - 6, 20, 20);
    g.endFill();
    // White Flash stage.
    g.beginFill(0xF7F4FF, 1);
    g.drawRoundRect(8, 8, w - 16, CANVAS_H, 12, 12);
    g.endFill();
    // Light grid on the stage.
    g.lineStyle(1, 0xE6E0F5, 1);
    var gx = 8.0 + 20;
    while (gx < w - 8)
    {
      g.moveTo(gx, 9);
      g.lineTo(gx, 8 + CANVAS_H - 1);
      gx += 20;
    }
    var gy = 8.0 + 20;
    while (gy < 8 + CANVAS_H)
    {
      g.moveTo(9, gy);
      g.lineTo(w - 9, gy);
      gy += 20;
    }
    g.lineStyle();
    // Ground line.
    g.beginFill(0xCFC6EA, 1);
    g.drawRect(14, 8 + CANVAS_H - 10, w - 28, 2);
    g.endFill();

    // Dotted motion path, sampled from the same path Boyfriend follows.
    g.beginFill(0xB59BFF, 1);
    var i = 0.0;
    while (i < BEATS_PER_LOOP / 2)
    {
      var p = bfPath(i);
      g.drawCircle(8 + p.x + 40, 8 + p.y - 22, 1.6);
      i += 0.05;
    }
    g.endFill();

    // Timeline rows.
    var ty = 8 + CANVAS_H + 8.0;
    var rowH = 16;
    var cellW = (w - 16 - LABEL_W) / FRAMES;
    for (row in 0...2)
    {
      var ry = ty + row * (rowH + 2);
      for (f in 0...FRAMES)
      {
        var cx = 8 + LABEL_W + f * cellW;
        var isTween = row == 0;
        var color = isTween ? 0xB9A6F5 : (f % 6 == 0 ? 0xE4DEF5 : 0xF4F1FA);
        g.beginFill(color, 1);
        g.drawRect(cx, ry, cellW - 1, rowH);
        g.endFill();
      }
      // Tween arrows between keyframes (top row), Flash style.
      if (row == 0)
      {
        g.lineStyle(1, 0x5B3FB8, 1);
        var k = 0;
        while (k < FRAMES)
        {
          var x0 = 8 + LABEL_W + k * cellW + cellW / 2 + 4;
          var x1 = 8 + LABEL_W + (k + 6) * cellW - 4;
          g.moveTo(x0, ry + rowH / 2);
          g.lineTo(x1, ry + rowH / 2);
          g.lineTo(x1 - 3, ry + rowH / 2 - 3);
          g.moveTo(x1, ry + rowH / 2);
          g.lineTo(x1 - 3, ry + rowH / 2 + 3);
          k += 6;
        }
        g.lineStyle();
      }
      // Keyframe dots.
      g.beginFill(0x1A1030, 1);
      var k2 = 0;
      while (k2 < FRAMES)
      {
        g.drawCircle(8 + LABEL_W + k2 * cellW + cellW / 2, ry + rowH / 2, 3.2);
        k2 += 6;
      }
      g.endFill();
    }

    var bmp = new BitmapData(w, h, true, 0);
    bmp.draw(shape, null, null, null, null, true);

    // Layer labels.
    var labelFont = Paths.font('Quantico-Bold.ttf');
    for (row in 0...2)
    {
      var tf = new openfl.text.TextField();
      var fmt = new openfl.text.TextFormat(openfl.utils.Assets.getFont(labelFont)?.fontName ?? '_sans', 11, 0xE8E0FF, true);
      tf.defaultTextFormat = fmt;
      tf.embedFonts = openfl.utils.Assets.getFont(labelFont) != null;
      tf.text = row == 0 ? 'BF' : 'GF';
      var mt = new Matrix();
      mt.translate(12, ty + row * (rowH + 2) + 1);
      bmp.draw(tf, mt, null, null, null, true);
    }
    return bmp;
  }

  /**
   * Called by the Mod Menu on every beat of the menu music.
   */
  public function beatHit(beat:Int):Void
  {
    gfPop = 1;
    gfSide = -gfSide;
    glowPulse = 1;
  }

  public function setSelected(value:Bool):Void
  {
    selected = value;
    glow.visible = value;
  }

  public function isHovered():Bool
  {
    return FlxG.mouse.overlaps(bg);
  }

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);

    if (glow.visible)
    {
      glowPulse = Math.max(0, glowPulse - elapsed * 3);
      glow.alpha = 0.6 + glowPulse * 0.4;
    }

    if (custom) return;

    // Follow the music if it's playing, otherwise run at 102 BPM.
    var beatTime:Float;
    if (FlxG.sound.music != null && FlxG.sound.music.playing) beatTime = Conductor.instance.currentBeatTime;
    else
    {
      fallbackTime += elapsed;
      beatTime = fallbackTime * 102 / 60;
    }

    var canvasX = x + sx + 8;
    var canvasY = y + sy + 8;

    placeBF(bf, bfPath(beatTime), canvasX, canvasY);
    for (i in 0...ghosts.length)
      placeBF(ghosts[i], bfPath(beatTime + ghostOffsets[i]), canvasX, canvasY);

    gfPop = Math.max(0, gfPop - elapsed * 4);
    var gsx = 1.7 * (1 + 0.14 * gfPop);
    var gsy = 1.7 * (1 - 0.08 * gfPop);
    gf.scale.set(gsx, gsy);
    gf.angle = gfSide * 6 * gfPop;
    // Keep her feet on the ground while she squashes (frame is 50x50, feet at y=45).
    gf.y = canvasY + CANVAS_H - 10 - gf.height / 2 - 20 * gsy;

    // Timeline playhead.
    var loopT = ((beatTime % BEATS_PER_LOOP) + BEATS_PER_LOOP) % BEATS_PER_LOOP / BEATS_PER_LOOP;
    var cellW = (STAGE_W - 16 - LABEL_W) / FRAMES;
    var frame = Std.int(loopT * FRAMES) % FRAMES;
    var timelineY = y + sy + 8 + CANVAS_H + 8;
    playhead.setPosition(x + sx + 8 + LABEL_W + loopT * (STAGE_W - 16 - LABEL_W) - 1, timelineY - 3);
    cellHighlight.setPosition(x + sx + 8 + LABEL_W + frame * cellW, timelineY);
    if (frame != lastFrame)
    {
      lastFrame = frame;
      frameText.text = 'frame ${frame + 1}/$FRAMES  ·  24 fps';
    }

    // Sparkles near the title.
    for (i in 0...sparkles.length)
    {
      var s = sparkles[i];
      if (s.visible && s.animation.finished) s.visible = false;
      if (!s.visible)
      {
        sparkleTimers[i] -= elapsed;
        if (sparkleTimers[i] <= 0)
        {
          sparkleTimers[i] = FlxG.random.float(0.6, 1.8);
          s.setPosition(x + FlxG.random.float(20, 420), y + FlxG.random.float(26, 90));
          var sc = FlxG.random.float(0.5, 0.9);
          s.scale.set(sc, sc);
          s.visible = true;
          s.animation.play('sparkle', true);
        }
      }
    }
  }

  inline function placeBF(spr:FlxSprite, p:{x:Float, y:Float, sx:Float, sy:Float}, canvasX:Float, canvasY:Float)
  {
    spr.scale.set(BF_SCALE * p.sx, BF_SCALE * p.sy);
    // Keep the feet planted while squashing: the frame is 50x50 (scaled around its center), feet at y=40.
    spr.x = canvasX + p.x;
    spr.y = canvasY + p.y - spr.height / 2 - 15 * BF_SCALE * p.sy;
  }
}
