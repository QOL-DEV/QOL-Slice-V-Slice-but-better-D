package funkin.qol.ui;

#if FEATURE_HAXEUI
import haxe.ui.components.Button;
import haxe.ui.components.Label;
import haxe.ui.containers.Box;
import haxe.ui.containers.HBox;
import haxe.ui.containers.VBox;
import haxe.ui.core.Component;

/**
 * A movable editor panel: a title bar you can drag (to float the panel anywhere or dock it to the left or right
 * edge), a collapse button, resizable edges, and a scrolling content area.
 *
 * Panels are owned and laid out by `QOLEditorState`.
 */
class QOLDockPanel extends VBox
{
  public static inline final HEADER_HEIGHT:Int = 24;
  public static inline final COLLAPSED_WIDTH:Int = 30;

  public var panelId(default, null):String;
  public var title(default, set):String;

  /**
   * The width the editor built the panel's contents for.
   */
  public var naturalWidth(default, null):Int;

  /**
   * Current width (docked or floating).
   */
  public var panelWidth:Int;

  /**
   * 'left', 'right' or 'float'.
   */
  public var side:String;

  public var defaultSide(default, null):String;
  public var collapsed(default, set):Bool = false;

  public var floatX:Float = 200;
  public var floatY:Float = 80;
  public var floatHeight:Float = 480;

  public var header(default, null):HBox;
  public var titleLabel(default, null):Label;
  public var collapseButton(default, null):Button;
  public var floatButton(default, null):Button;
  public var scroll(default, null):QOLScrollView;

  /**
   * Where the editor puts its controls.
   */
  public var content(default, null):VBox;

  /**
   * Called when the user clicks collapse or float/dock.
   */
  public var onToggleCollapse:Null<QOLDockPanel->Void> = null;

  public var onToggleFloat:Null<QOLDockPanel->Void> = null;

  /**
   * When false, the panel doesn't stretch its contents itself; `onPanelResized` is called instead.
   */
  public var autoFit:Bool = true;

  public var onPanelResized:Null<QOLDockPanel->Void> = null;

  var baseWidths:Map<Component, Float> = new Map<Component, Float>();
  var appliedWidth:Int = -1;
  var lastW:Float = -1;
  var lastH:Float = -1;

  public function new(id:String, title:String, width:Int, side:String)
  {
    super();
    this.panelId = id;
    this.naturalWidth = width;
    this.panelWidth = width;
    this.side = side;
    this.defaultSide = side;
    styleString = 'spacing: 0; background-color: #2B2D31; border: 1px solid #3A3F47;';

    header = new HBox();
    header.percentWidth = 100;
    header.height = HEADER_HEIGHT;
    header.styleString = 'background-color: #1F2024; border-bottom: 1px solid #3A3F47; padding-left: 8px; padding-right: 3px; padding-top: 3px; spacing: 3px;';
    titleLabel = new Label();
    titleLabel.percentWidth = 100;
    titleLabel.styleString = 'color: #C8C2E0; font-bold: true; padding-top: 1px;';
    header.addComponent(titleLabel);
    floatButton = smallButton('Float');
    floatButton.tooltip = 'Float this panel (or drag its title bar anywhere; drop it on the left or right edge to dock it)';
    floatButton.onClick = _ -> if (onToggleFloat != null) onToggleFloat(this);
    header.addComponent(floatButton);
    collapseButton = smallButton('-');
    collapseButton.tooltip = 'Collapse';
    collapseButton.onClick = _ -> if (onToggleCollapse != null) onToggleCollapse(this);
    header.addComponent(collapseButton);
    addComponent(header);

    scroll = new QOLScrollView();
    scroll.percentWidth = 100;
    scroll.styleString = 'border: none; background-color: #2B2D31; padding: 8px;';
    content = new VBox();
    content.width = width - 28;
    content.styleString = 'spacing: 6px;';
    scroll.addComponent(content);
    addComponent(scroll);

    this.title = title;
  }

  /**
   * Restyle the panel (editors with their own look, like the Animator).
   * @param headerBackground CSS for the title bar's background, e.g. `background: #FF5C9D #9B6BFF horizontal;`.
   */
  public function setSkin(body:String, border:String, headerBackground:String, titleColor:String):Void
  {
    styleString = 'spacing: 0; background-color: $body; border: 1px solid $border;';
    header.styleString = '$headerBackground border-bottom: 1px solid $border; padding-left: 8px; padding-right: 3px; padding-top: 3px; spacing: 3px;';
    titleLabel.styleString = 'color: $titleColor; font-bold: true; padding-top: 1px;';
    scroll.styleString = 'border: none; background-color: $body; padding: 8px;';
  }

  static function smallButton(text:String):Button
  {
    var b = new Button();
    b.text = text;
    b.height = 18;
    b.styleString = 'padding: 0px 6px; font-size: 11px;';
    return b;
  }

  function set_title(value:String):String
  {
    title = value;
    if (titleLabel != null) titleLabel.text = value;
    return value;
  }

  function set_collapsed(value:Bool):Bool
  {
    collapsed = value;
    if (collapseButton != null)
    {
      collapseButton.text = value ? '+' : '-';
      collapseButton.tooltip = value ? 'Expand' : 'Collapse';
    }
    if (scroll != null) scroll.hidden = value;
    if (titleLabel != null) titleLabel.hidden = value && side != 'float';
    if (floatButton != null) floatButton.hidden = value && side != 'float';
    return value;
  }

  public var isFloating(get, never):Bool;

  inline function get_isFloating():Bool
    return side == 'float';

  /**
   * Width on screen right now.
   */
  public function shownWidth():Int
    return (collapsed && !isFloating) ? COLLAPSED_WIDTH : panelWidth;

  /**
   * Put the panel at a screen rectangle.
   */
  public function place(x:Float, y:Float, w:Float, h:Float):Void
  {
    left = Math.round(x);
    top = Math.round(y);
    width = Math.round(w);
    height = Math.round(h);
    scroll.height = Math.max(10, Math.round(h) - HEADER_HEIGHT - 2);
    floatButton.text = isFloating ? 'Dock' : 'Float';
    // Titles/buttons only make sense when there's room for them.
    titleLabel.hidden = collapsed && !isFloating;
    floatButton.hidden = collapsed && !isFloating;
    if (!collapsed)
    {
      if (autoFit) fitContents(panelWidth);
      else if (onPanelResized != null && (lastW != panelWidth || lastH != Math.round(h)))
      {
        lastW = panelWidth;
        lastH = Math.round(h);
        onPanelResized(this);
      }
    }
  }

  /**
   * Stretch or shrink the panel's contents to a new width. Forms resize their controls; anything else that was built
   * to span the panel (lists, tabs, long buttons) grows or shrinks by the same amount.
   */
  public function fitContents(w:Int):Void
  {
    if (w == appliedWidth) return;
    appliedWidth = w;
    var delta = w - naturalWidth;
    var naturalContent = naturalWidth - 28;
    content.width = naturalContent + delta;
    for (c in content.childComponents)
      fitComponent(c, delta, naturalContent);
  }

  function fitComponent(c:Component, delta:Float, naturalContent:Float):Void
  {
    if (Std.isOfType(c, QOLForm))
    {
      (cast c : QOLForm).fitDelta(delta);
      return;
    }
    if (c.percentWidth == null && c.width > 0)
    {
      var base = baseWidths.get(c);
      if (base == null)
      {
        base = c.width;
        baseWidths.set(c, base);
      }
      // Built to span the panel? Then it follows the panel's width.
      if (base >= naturalContent - 70) c.width = Math.max(40, base + delta);
    }
    // Only walk into layout containers (not into lists, dropdowns, steppers...).
    if (Std.isOfType(c, Box) || Std.isOfType(c, haxe.ui.containers.TabView))
    {
      for (child in c.childComponents)
        fitComponent(child, delta, naturalContent);
    }
  }

  /**
   * True if a screen point is on the title bar (but not on its buttons).
   */
  public function headerHit(x:Float, y:Float):Bool
  {
    if (hidden) return false;
    if (!(x >= screenLeft && x < screenLeft + width && y >= screenTop && y < screenTop + HEADER_HEIGHT)) return false;
    for (b in [floatButton, collapseButton])
      if (!b.hidden && x >= b.screenLeft && x < b.screenLeft + b.width && y >= b.screenTop && y < b.screenTop + b.height) return false;
    return true;
  }

  public function contains(x:Float, y:Float):Bool
    return !hidden && x >= screenLeft && x < screenLeft + width && y >= screenTop && y < screenTop + height;
}
#end
