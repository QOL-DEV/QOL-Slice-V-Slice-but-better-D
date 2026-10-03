package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.addons.display.FlxBackdrop;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxGradient;
import funkin.qol.ui.QOLTheme;
import openfl.display.BitmapData;
import openfl.display.Shape;

/**
 * The fun bits around the Animator's canvas: the purple gradient with a slowly scrolling diagonal grid (like the Mod
 * Menu), a name tag above the stage, a friendly hint on an empty canvas, and a pop-up when you switch tools.
 */
class AnimCanvasDecor extends FlxGroup
{
  var camWorld:FlxCamera;
  var camUI:FlxCamera;

  var gradient:FlxSprite;
  var grid:FlxBackdrop;

  var tagBg:FlxSprite;
  var tagText:FlxText;
  var tagWidth:Int = 0;

  var hintTitle:FlxText;
  var hintBody:FlxText;
  var hintStars:Array<FlxSprite> = [];
  var hintAlpha:Float = 0;
  var hintWanted:Bool = false;
  var hintX:Float = 0;
  var hintY:Float = 0;

  var toastBg:FlxSprite;
  var toastIcon:FlxSprite;
  var toastText:FlxText;
  var toastTime:Float = -1;
  var toastX:Float = 0;
  var toastY:Float = 0;

  var time:Float = 0;

  public function new(camWorld:FlxCamera, camUI:FlxCamera)
  {
    super();
    this.camWorld = camWorld;
    this.camUI = camUI;

    gradient = new FlxSprite();
    gradient.scrollFactor.set();
    gradient.cameras = [camWorld];
    add(gradient);

    grid = new FlxBackdrop(QOLTheme.cached('qol-anim-grid-tile', gridTile));
    grid.cameras = [camWorld];
    grid.velocity.set(9, 9);
    grid.alpha = 0.9;
    add(grid);

    tagBg = ui(new FlxSprite());
    tagText = ui(QOLTheme.text(0, 0, 600, '', 12, QOLTheme.FONT_TITLE, AnimatorSkin.TEXT));
    add(tagBg);
    add(tagText);

    hintTitle = ui(QOLTheme.outlinedText(0, 0, 560, 'Blank canvas!', 34, FlxColor.WHITE, 3));
    hintTitle.alignment = CENTER;
    hintBody = ui(QOLTheme.text(0, 0, 560, 'Grab the Brush (B) and doodle something.\nNew here? Press F1 for the guide.', 15, QOLTheme.FONT_BODY,
      0xFFDCD3FF));
    hintBody.alignment = CENTER;
    hintBody.setBorderStyle(OUTLINE, 0xFF1A1030, 1.5);
    for (i in 0...3)
    {
      var star = ui(new FlxSprite().loadGraphic(AnimatorSkin.iconGraphic('sparkle', 22, [0xFFFF5C9D, 0xFF5CE1FF, 0xFFFFD84A][i], true)));
      hintStars.push(star);
      add(star);
    }
    add(hintTitle);
    add(hintBody);
    setHintAlpha(0);

    refreshTheme();

    toastBg = ui(new FlxSprite());
    toastIcon = ui(new FlxSprite());
    toastText = ui(QOLTheme.outlinedText(0, 0, 220, '', 18, FlxColor.WHITE, 2));
    add(toastBg);
    add(toastIcon);
    add(toastText);
    setToastAlpha(0);
  }

  /**
   * Recolor everything for the current theme.
   */
  public function refreshTheme():Void
  {
    var key = 'qol-anim-bg-${StringTools.hex(AnimatorSkin.BG_TOP, 8)}-${StringTools.hex(AnimatorSkin.BG_BOTTOM, 8)}';
    gradient.loadGraphic(QOLTheme.cached(key, () -> FlxGradient.createGradientBitmapData(16, 256, [AnimatorSkin.BG_TOP, AnimatorSkin.BG_BOTTOM])));
    tagText.color = AnimatorSkin.TEXT;
    tagWidth = -1;
    var t = tagText.text;
    tagText.text = '';
    if (t != '') setStageTag(tagBg.x, tagBg.y + 28, t, -9999, -9999, 99999);
    hintBody.color = AnimatorSkin.TEXT_SOFT;
  }

  function ui<T:FlxSprite>(s:T):T
  {
    s.cameras = [camUI];
    s.scrollFactor.set();
    s.antialiasing = true;
    return s;
  }

  static function gridTile():BitmapData
  {
    var size = 72;
    var s = new Shape();
    var g = s.graphics;
    g.lineStyle(1.5, 0xFFFFFF, 0.055);
    g.moveTo(0, 0);
    g.lineTo(size, size);
    g.moveTo(size, 0);
    g.lineTo(0, size);
    g.lineStyle();
    g.beginFill(0xFFFFFF, 0.08);
    g.drawCircle(size / 2, size / 2, 2);
    g.endFill();
    var b = new BitmapData(size, size, true, 0);
    b.draw(s, null, null, null, null, true);
    return b;
  }

  //
  // Stage tag
  //

  /**
   * The name tag above the stage's top-left corner (game coordinates).
   */
  public function setStageTag(x:Float, y:Float, text:String, minX:Float, minY:Float, maxX:Float):Void
  {
    if (tagText.text != text)
    {
      tagText.text = text;
      var w = Std.int(tagText.textField.textWidth + 22);
      if (w != tagWidth)
      {
        tagWidth = w;
        var fill = (AnimatorSkin.FIELD & 0xFFFFFF) | 0xE6000000;
        tagBg.loadGraphic(QOLTheme.cached('qol-anim-tag-$w-${StringTools.hex(fill, 8)}-${StringTools.hex(AnimatorSkin.BORDER_LIGHT, 8)}',
          () -> QOLTheme.drawRound(w, 22, fill, 11, AnimatorSkin.BORDER_LIGHT, 1.5)));
      }
    }
    var tx = Math.max(minX, Math.min(maxX - tagWidth, x));
    var ty = Math.max(minY, y - 28);
    tagBg.setPosition(tx, ty);
    tagText.setPosition(tx + 11, ty + 3);
  }

  //
  // Empty canvas hint
  //

  public function setHint(show:Bool, cx:Float, cy:Float):Void
  {
    hintWanted = show;
    hintX = cx;
    hintY = cy;
  }

  function setHintAlpha(a:Float):Void
  {
    hintAlpha = a;
    var vis = a > 0.01;
    hintTitle.visible = hintBody.visible = vis;
    hintTitle.alpha = hintBody.alpha = a;
    for (s in hintStars)
    {
      s.visible = vis;
      s.alpha = a;
    }
  }

  //
  // Tool pop-up
  //

  public function showTool(id:String, name:String, key:String, x:Float, y:Float):Void
  {
    var color = AnimatorSkin.TOOL_COLORS.get(id) ?? AnimatorSkin.ACCENT;
    toastText.text = key == '' ? name : '$name  ($key)';
    var w = Std.int(toastText.textField.textWidth + 70);
    toastBg.loadGraphic(QOLTheme.cached('qol-anim-toast-$w-${StringTools.hex(color, 8)}',
      () -> QOLTheme.drawRound(w, 44, color, 14, AnimatorSkin.lighten(color, 0.6), 3)));
    toastIcon.loadGraphic(AnimatorSkin.iconGraphic(id, 26, 0xFFFFFFFF, true));
    toastX = x - w / 2;
    toastY = y;
    toastTime = 0;
  }

  function setToastAlpha(a:Float):Void
  {
    var vis = a > 0.01;
    toastBg.visible = toastIcon.visible = toastText.visible = vis;
    toastBg.alpha = toastIcon.alpha = toastText.alpha = a;
  }

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);
    time += elapsed;

    gradient.setGraphicSize(FlxG.width + 4, FlxG.height + 4);
    gradient.updateHitbox();
    gradient.setPosition(-2, -2);

    // Hint: fade, bob and twinkle.
    var target = hintWanted ? 1.0 : 0.0;
    var a = hintAlpha + (target - hintAlpha) * Math.min(1, elapsed * 8);
    if (Math.abs(a - hintAlpha) > 0.001 || (a > 0 && a < 1)) setHintAlpha(a);
    if (hintAlpha > 0.01)
    {
      var bob = Math.sin(time * 2.2) * 5;
      hintTitle.setPosition(hintX - hintTitle.width / 2, hintY - 46 + bob);
      hintBody.setPosition(hintX - hintBody.width / 2, hintY + 4 + bob * 0.6);
      var tw = hintTitle.textField.textWidth;
      var spots = [[-tw / 2 - 34, -40], [tw / 2 + 12, -48], [tw / 2 + 26, -14]];
      for (i in 0...hintStars.length)
      {
        var st = hintStars[i];
        var tw2 = Math.sin(time * 3 + i * 2.1);
        st.scale.set(0.75 + tw2 * 0.25, 0.75 + tw2 * 0.25);
        st.angle = time * 40 * (i % 2 == 0 ? 1 : -1);
        st.setPosition(hintX + spots[i][0], hintY + spots[i][1] + bob);
      }
    }

    // Tool pop-up: pop in, hold, fade.
    if (toastTime >= 0)
    {
      toastTime += elapsed;
      var t = toastTime;
      var alpha = t < 0.12 ? t / 0.12 : (t < 0.85 ? 1 : Math.max(0, 1 - (t - 0.85) / 0.3));
      var pop = t < 0.18 ? backOut(t / 0.18) : 1;
      var sc = 0.7 + 0.3 * pop;
      // Sprites scale around their own centers, so place each one's center where it belongs at this scale.
      var bw = toastBg.frameWidth, bh = toastBg.frameHeight;
      var cx = toastX + bw / 2, cy = toastY + bh / 2 - (1 - pop) * 10;
      function put(s:FlxSprite, localX:Float)
      {
        s.scale.set(sc, sc);
        var w = s.frameWidth, h = s.frameHeight;
        var centerX = cx + (localX + w / 2 - bw / 2) * sc;
        s.setPosition(centerX - w / 2, cy - h / 2);
      }
      put(toastBg, 0);
      put(toastIcon, 10);
      put(toastText, 44);
      setToastAlpha(alpha);
      if (t > 1.2) toastTime = -1;
    }
  }

  static function backOut(t:Float):Float
  {
    var s = 1.70158;
    t -= 1;
    return t * t * ((s + 1) * t + s) + 1;
  }
}
#end
