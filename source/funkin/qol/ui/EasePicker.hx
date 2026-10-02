package funkin.qol.ui;

#if FEATURE_HAXEUI
import haxe.ui.components.Button;
import haxe.ui.components.HorizontalSlider;
import haxe.ui.components.Image;
import haxe.ui.components.Label;
import haxe.ui.containers.Absolute;
import haxe.ui.containers.Box;
import haxe.ui.containers.Grid;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ScrollView;
import haxe.ui.containers.VBox;
import haxe.ui.containers.dialogs.Dialog;
import haxe.ui.events.MouseEvent;
import funkin.qol.util.QOLEase;

/**
 * The Ease Picker: shows EVERY ease type as a live curve, with an animated preview
 * of how the motion will feel. Used for camera move/zoom events, stage events,
 * modchart keyframes and animator tweens.
 */
class EasePicker extends Dialog
{
  /**
   * Open the picker. `onPick` is called with the chosen ease name (e.g. `quadInOut`).
   */
  public static function open(current:String, includeInstant:Bool, onPick:String->Void, includeClassic:Bool = false):EasePicker
  {
    var picker = new EasePicker(current, includeInstant, onPick, includeClassic);
    picker.showDialog(true);
    return picker;
  }

  static final CELL_W:Int = 78;
  static final CELL_H:Int = 40;
  static final PREVIEW_W:Int = 260;
  static final PREVIEW_H:Int = 190;

  var selected:String;
  var previewing:String;
  var onPick:String->Void;
  var cells:Map<String, Button> = new Map<String, Button>();

  var previewImage:Image;
  var previewDot:Box;
  var motionBox:Box;
  var scaleBox:Box;
  var fadeBox:Box;
  var nameLabel:Label;
  var codeLabel:Label;
  var speedSlider:HorizontalSlider;
  var time:Float = 0;
  var duration:Float = 1.2;

  public function new(current:String, includeInstant:Bool, onPick:String->Void, includeClassic:Bool = false)
  {
    super();
    this.selected = current ?? 'linear';
    this.previewing = this.selected;
    this.onPick = onPick;
    this.title = 'Ease Picker - every ease type';
    this.buttons = DialogButton.CANCEL | '{{Use This Ease}}';
    this.defaultButton = '{{Use This Ease}}';
    this.destroyOnClose = true;

    var main = new HBox();
    main.styleString = 'spacing: 12px;';
    addComponent(main);

    // Left: the grid of every ease.
    var scroll = new ScrollView();
    scroll.width = CELL_W * 3 + 140;
    scroll.height = 470;
    scroll.styleString = 'padding: 4px;';
    main.addComponent(scroll);

    var grid = new Grid();
    grid.columns = 4;
    grid.styleString = 'spacing: 4px;';
    scroll.addComponent(grid);

    // Header row.
    for (h in ['', 'In', 'Out', 'In/Out'])
    {
      var l = new Label();
      l.text = h;
      l.width = h == '' ? 96 : CELL_W;
      l.styleString = 'font-bold: true; text-align: center;';
      grid.addComponent(l);
    }

    // Linear / instant row.
    addFamilyLabel(grid, 'Linear');
    addCell(grid, 'linear');
    if (includeInstant) addCell(grid, 'INSTANT');
    else
      addSpacer(grid);
    if (includeClassic) addCell(grid, 'CLASSIC');
    else
      addSpacer(grid);

    for (family in QOLEase.FAMILIES)
    {
      addFamilyLabel(grid, QOLEase.displayName(family + 'In').split(' In')[0]);
      for (dir in QOLEase.DIRECTIONS)
        addCell(grid, family + dir);
    }

    // Right: the big animated preview.
    var right = new VBox();
    right.styleString = 'spacing: 8px;';
    main.addComponent(right);

    nameLabel = new Label();
    nameLabel.styleString = 'font-size: 18px; font-bold: true;';
    right.addComponent(nameLabel);
    codeLabel = new Label();
    codeLabel.styleString = 'color: #9AA0A6;';
    right.addComponent(codeLabel);

    var graphArea = new Absolute();
    graphArea.width = PREVIEW_W;
    graphArea.height = PREVIEW_H;
    graphArea.styleString = 'background-color: #1B1D21; border: 1px solid #3A3F47; border-radius: 4px;';
    right.addComponent(graphArea);

    previewImage = new Image();
    previewImage.left = 0;
    previewImage.top = 0;
    graphArea.addComponent(previewImage);

    previewDot = new Box();
    previewDot.width = 10;
    previewDot.height = 10;
    previewDot.styleString = 'background-color: #FFD24A; border-radius: 5px;';
    graphArea.addComponent(previewDot);

    var motionLabel = new Label();
    motionLabel.text = 'Motion / Scale / Fade preview';
    right.addComponent(motionLabel);

    var motionArea = new Absolute();
    motionArea.width = PREVIEW_W;
    motionArea.height = 64;
    motionArea.styleString = 'background-color: #1B1D21; border: 1px solid #3A3F47; border-radius: 4px;';
    right.addComponent(motionArea);

    motionBox = new Box();
    motionBox.width = 20;
    motionBox.height = 20;
    motionBox.top = 8;
    motionBox.styleString = 'background-color: #5CC8FF; border-radius: 3px;';
    motionArea.addComponent(motionBox);

    scaleBox = new Box();
    scaleBox.styleString = 'background-color: #FF6FAE; border-radius: 3px;';
    motionArea.addComponent(scaleBox);

    fadeBox = new Box();
    fadeBox.width = 26;
    fadeBox.height = 26;
    fadeBox.left = PREVIEW_W - 40;
    fadeBox.top = 30;
    fadeBox.styleString = 'background-color: #7CE38B; border-radius: 3px;';
    motionArea.addComponent(fadeBox);

    var speedRow = new HBox();
    var speedLabel = new Label();
    speedLabel.text = 'Preview speed';
    speedLabel.width = 96;
    speedRow.addComponent(speedLabel);
    speedSlider = new HorizontalSlider();
    speedSlider.width = PREVIEW_W - 100;
    speedSlider.min = 0.3;
    speedSlider.max = 3;
    speedSlider.pos = duration;
    speedSlider.onChange = _ -> duration = speedSlider.pos;
    speedRow.addComponent(speedSlider);
    right.addComponent(speedRow);

    var hint = new Label();
    hint.text = 'Hover to preview, click to select,\ndouble-click to use it right away.';
    hint.styleString = 'color: #9AA0A6;';
    right.addComponent(hint);

    setPreview(selected);
    highlight();

    FlxG.signals.postUpdate.add(tick);

    onDialogClosed = function(e) {
      FlxG.signals.postUpdate.remove(tick);
      if (e.button == '{{Use This Ease}}') onPick(selected);
    };
  }

  function addFamilyLabel(grid:Grid, text:String)
  {
    var l = new Label();
    l.text = text;
    l.width = 96;
    l.styleString = 'padding-top: 12px;';
    grid.addComponent(l);
  }

  function addSpacer(grid:Grid)
  {
    var b = new Box();
    b.width = CELL_W;
    b.height = CELL_H;
    grid.addComponent(b);
  }

  function addCell(grid:Grid, ease:String)
  {
    var btn = new Button();
    btn.width = CELL_W;
    btn.height = CELL_H;
    btn.toggle = true;
    btn.icon = EaseGraph.frame(ease, CELL_W - 12, CELL_H - 10);
    btn.tooltip = QOLEase.displayName(ease) + ' (' + ease + ')';
    btn.onClick = function(_) {
      selected = ease;
      setPreview(ease);
      highlight();
    };
    btn.onDblClick = function(_) {
      selected = ease;
      hideDialog('{{Use This Ease}}');
    };
    btn.registerEvent(MouseEvent.MOUSE_OVER, function(_) setPreview(ease));
    btn.registerEvent(MouseEvent.MOUSE_OUT, function(_) setPreview(selected));
    cells.set(ease, btn);
    grid.addComponent(btn);
  }

  function highlight()
  {
    for (ease => btn in cells)
      btn.selected = (ease == selected);
  }

  function setPreview(ease:String)
  {
    if (previewing == ease && previewImage.resource != null) return;
    previewing = ease;
    previewImage.resource = EaseGraph.frame(ease, PREVIEW_W, PREVIEW_H, 0x5CC8FF);
    nameLabel.text = QOLEase.displayName(ease) + (ease == selected ? '  (selected)' : '');
    codeLabel.text = 'Saved as: "$ease"';
    time = 0;
  }

  function tick()
  {
    if (previewDot == null) return;
    time += FlxG.elapsed;
    var cycle = duration + 0.5;
    var local = time % cycle;
    var t = Math.min(1, local / duration);
    var v = previewing == 'INSTANT' ? 1.0 : QOLEase.get(previewing)(t);

    // Match EaseGraph's padding.
    var padTop = PREVIEW_H * 0.18;
    var h = PREVIEW_H - padTop * 2;
    var px = 2 + t * (PREVIEW_W - 4);
    var py = padTop + h - v * h;
    previewDot.left = px - 5;
    previewDot.top = Math.max(0, Math.min(PREVIEW_H - 10, py - 5));

    motionBox.left = 6 + v * (PREVIEW_W - 90);
    var size = 6 + Math.max(0, v) * 20;
    scaleBox.width = size;
    scaleBox.height = size;
    scaleBox.left = PREVIEW_W - 80 - size / 2;
    scaleBox.top = 44 - size / 2;
    fadeBox.opacity = Math.max(0, Math.min(1, v));
  }
}
#end
