package funkin.qol.ui;

import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.audio.FunkinSound;

/**
 * A chunky rounded button for QOL Slice's game-styled screens (Mod Menu, Guide...).
 * Both states are pre-rendered once; hovering only swaps visibility and bumps the scale.
 */
class QOLFlxButton extends FlxSpriteGroup
{
  public var onClick:Null<Void->Void>;
  public var label:FlxText;
  public var enabled:Bool = true;
  public var hovered(default, null):Bool = false;

  var bg:FlxSprite;
  var bgHover:FlxSprite;
  var grid:FlxSprite;
  var baseColor:FlxColor;
  var pop:Float = 0;

  public function new(x:Float, y:Float, width:Int, height:Int, text:String, ?onClick:Void->Void, ?color:FlxColor, fontSize:Int = 15)
  {
    super(x, y);
    this.onClick = onClick;
    baseColor = color ?? QOLTheme.PANEL_LIGHT;
    bg = QOLTheme.buttonGraphic(width, height, baseColor, false);
    bgHover = QOLTheme.buttonGraphic(width, height, baseColor.getLightened(0.18), true);
    bgHover.visible = false;
    add(bg);
    add(bgHover);
    // A little grid scrolling diagonally across the face.
    grid = QOLTheme.scrollGrid(width, height);
    grid.alpha = 0.75;
    add(grid);
    label = QOLTheme.text(0, 0, width, text, fontSize, QOLTheme.FONT_TITLE);
    label.alignment = CENTER;
    label.y = (height - 5 - label.height) / 2;
    label.borderStyle = SHADOW;
    label.borderColor = 0x60000000;
    label.borderSize = 2;
    add(label);
  }

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);
    if (!visible || !enabled)
    {
      hovered = false;
      bgHover.visible = false;
      bg.visible = true;
      return;
    }
    var over = FlxG.mouse.overlaps(bg, cameras != null && cameras.length > 0 ? cameras[0] : null);
    if (over != hovered)
    {
      hovered = over;
      bgHover.visible = over;
      bg.visible = !over;
      grid.alpha = over ? 1 : 0.75;
      if (over) pop = 1;
    }
    if (pop > 0)
    {
      pop = Math.max(0, pop - elapsed * 6);
      var s = 1 + 0.06 * pop;
      for (m in members)
        m.scale.set(s, s);
    }
    if (over && FlxG.mouse.justPressed)
    {
      for (m in members)
        m.scale.set(0.94, 0.94);
    }
    if (over && FlxG.mouse.justReleased && onClick != null)
    {
      FunkinSound.playOnce(Paths.sound('scrollMenu'), 0.6);
      pop = 1;
      onClick();
    }
  }

  public function setText(text:String):Void
  {
    label.text = text;
  }
}
