package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import flixel.FlxCamera;
import flixel.util.FlxColor;
import funkin.qol.editors.animator.AnimData;
import funkin.qol.editors.animator.AnimGeom;
import funkin.qol.editors.animator.AnimatorSkin.AnimTheme;
import haxe.ui.containers.dialogs.Dialog.DialogButton;
import funkin.qol.ui.QOLDockPanel;
import funkin.qol.ui.QOLEditorState;
import funkin.qol.ui.QOLForm;
import funkin.qol.ui.QOLTheme;
import haxe.ui.components.Button;
import haxe.ui.components.Label;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ListView;
import haxe.ui.containers.TabView;
import haxe.ui.containers.VBox;
import haxe.ui.containers.menus.Menu;
import haxe.ui.containers.Box;
import haxe.ui.events.MouseEvent;
import haxe.ui.data.ArrayDataSource;
import openfl.display.BitmapData;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;

typedef AnimSel =
{
  var layer:Int;
  var element:Int;
}

/**
 * The QOL Animator: a Flash-style animation studio and drawing program built into the engine.
 *
 * - Drawing: vector brush, pencil, eraser, paint bucket (fills closed areas with real vector shapes), line, rectangle,
 *   oval, polygon/star, text and eyedropper; bitmap layers for painting pixels (soft/hard brush, pixel pencil, eraser,
 *   bucket with tolerance).
 * - Animation: layers, keyframes, frame spans, classic tweens with every ease, onion skin, symbols with their own
 *   timelines, color effects, filters and blend modes.
 * - Everything saves into the active mod; File > Export makes sprite atlases the game can use.
 */
class AnimatorState extends QOLEditorState
{
  public static final TOOLS:Array<{id:String, name:String, key:String}> = [
    {id: 'select', name: 'Select', key: 'V'},
    {id: 'brush', name: 'Brush', key: 'B'},
    {id: 'pencil', name: 'Pencil', key: 'Y'},
    {id: 'eraser', name: 'Eraser', key: 'E'},
    {id: 'fill', name: 'Bucket', key: 'K'},
    {id: 'line', name: 'Line', key: 'N'},
    {id: 'rect', name: 'Rectangle', key: 'R'},
    {id: 'oval', name: 'Oval', key: 'O'},
    {id: 'poly', name: 'Polygon', key: 'P'},
    {id: 'text', name: 'Text', key: 'T'},
    {id: 'picker', name: 'Eyedropper', key: 'I'},
    {id: 'hand', name: 'Hand', key: 'H'},
    {id: 'zoom', name: 'Zoom', key: 'Z'},
  ];

  static inline final CONTROLS_H:Int = 36;

  public var doc:AnimDoc;
  public var renderer:AnimRender;

  /**
   * Symbol ids being edited (empty = the main timeline).
   */
  var editPath:Array<String> = [];

  public var sym(get, never):AnimSymbol;

  function get_sym():AnimSymbol
  {
    if (editPath.length == 0) return doc.main;
    return doc.symbol(editPath[editPath.length - 1]) ?? doc.main;
  }

  public var frame:Int = 0;
  public var curLayer:Int = 0;
  public var selStart:Int = 0;
  public var selEnd:Int = 0;

  public var tool:String = 'brush';

  // Tool settings.
  public var strokeColor:Int = 0xFF101018;
  public var fillColor:Int = 0xFF31A2FD;
  public var strokeOn:Bool = true;
  public var fillOn:Bool = true;
  public var brushSize:Float = 12;
  public var pencilSize:Float = 3;
  public var eraserSize:Float = 24;
  public var smoothing:Float = 0.5;
  public var opacity:Float = 1;
  public var hardness:Float = 0.8;
  public var taper:Bool = true;
  public var pixelPencil:Bool = false;
  public var shapeStroke:Float = 3;
  public var cornerRadius:Float = 0;
  public var polySides:Int = 5;
  public var polyStar:Bool = false;
  public var fillTolerance:Int = 32;
  public var fillGap:Int = 1;
  public var textSize:Float = 32;

  // View.
  public var zoom:Float = 0.6;
  public var viewX:Float = 0;
  public var viewY:Float = 0;

  /**
   * View rotation in degrees (turning the canvas like a sheet of paper; doesn't change the drawing).
   */
  public var viewRotation:Float = 0;

  /**
   * View mirrored left-right (doesn't change the drawing).
   */
  public var viewFlip:Bool = false;

  /**
   * Show the stage through the camera (when the timeline has one).
   */
  public var cameraView:Bool = true;

  /**
   * Hide everything outside the stage.
   */
  public var clipStage:Bool = false;
  public var onion:Bool = false;
  public var onionBefore:Int = 2;
  public var onionAfter:Int = 2;
  public var loopPlayback:Bool = true;
  public var playing:Bool = false;

  var playTime:Float = 0;

  // Canvas.
  var camCanvas:FlxCamera;
  var canvasRoot:Sprite;
  var stageHolder:Sprite;
  var checker:Shape;
  var onionHolder:Sprite;
  var contentHolder:Sprite;
  var liveShape:Shape;
  var worldHolder:Sprite;
  var camFrame:Shape;
  var stageMask:Shape;
  var overlay:Shape;
  var renderDirty:Bool = true;

  // Selection.
  public var selection:Array<AnimSel> = [];

  var clipboard:Null<String> = null;
  var frameClipboard:Null<String> = null;

  // UI.
  public var timeline:AnimTimelineView;

  var toolsPanel:QOLDockPanel;
  var inspector:QOLDockPanel;
  var tabs:TabView;
  var toolButtons:Map<String, Button> = new Map<String, Button>();
  var colorForm:QOLForm;
  var propsBox:VBox;
  var propsForm:Null<QOLForm> = null;
  var libList:ListView;
  var libIds:Array<String> = [];
  var docForm:QOLForm;
  var ctrlBar:HBox;
  var playButton:Button;
  var frameLabel:Label;
  var pathLabel:Label;
  var backButton:Button;
  var loopButton:Button;
  var onionButton:Button;
  var badge:Label;
  var viewBar:HBox;
  var zoomLabel:Button;
  var rotLabel:Button;
  var flipButton:Button;
  var clipButton:Button;
  var camViewButton:Button;
  var canvasButton:Button;
  var themeButton:Button;
  var decor:AnimCanvasDecor;
  var stageDecor:Shape;
  var playIconShown:Null<Bool> = null;

  public function new(?animId:String)
  {
    super();
    editorName = 'Animator';
    AnimatorSkin.loadCss();
    popupClasses = ['anim-ui', 'anim-popup'];
    bottomAreaHeight = 230;
    bottomAreaResizable = true;
    bottomAreaMin = 110;
    startId = animId;
  }

  var startId:Null<String>;

  override function guidePage():String
    return 'animator';

  //
  // Setup
  //

  override function buildEditor():Void
  {
    QOLSlice.editorOwnsFunctionKeys = true;
    AnimatorSkin.loadCss();
    root.addClass('anim-ui');
    gridBG.visible = false;

    camCanvas = new FlxCamera();
    camCanvas.bgColor = 0x00000000;
    FlxG.cameras.remove(camUI, false);
    FlxG.cameras.add(camCanvas, false);
    FlxG.cameras.add(camUI, false);

    canvasRoot = new Sprite();
    attachCanvas();
    stageDecor = new Shape();
    canvasRoot.addChild(stageDecor);
    stageHolder = new Sprite();
    canvasRoot.addChild(stageHolder);
    checker = new Shape();
    stageHolder.addChild(checker);
    // The drawing itself sits in "world" coordinates, seen through the camera.
    worldHolder = new Sprite();
    stageHolder.addChild(worldHolder);
    onionHolder = new Sprite();
    worldHolder.addChild(onionHolder);
    contentHolder = new Sprite();
    worldHolder.addChild(contentHolder);
    liveShape = new Shape();
    worldHolder.addChild(liveShape);
    camFrame = new Shape();
    worldHolder.addChild(camFrame);
    stageMask = new Shape();
    stageHolder.addChild(stageMask);
    stageMask.visible = false;
    overlay = new Shape();
    canvasRoot.addChild(overlay);

    var lastPref:String = QOLConfig.getPref('animator.last', '');
    var last:Null<String> = startId ?? (lastPref == '' ? null : lastPref);
    var loaded = last != null ? AnimIO.load(last) : null;
    doc = loaded ?? new AnimDoc(AnimData.newProject('My Animation'));
    doc.onChange = onDocChanged;
    renderer = new AnimRender(doc);

    decor = new AnimCanvasDecor(camWorld, camUI);
    add(decor);

    buildMenus();
    buildToolsPanel();
    buildInspector();
    buildControls();
    buildViewBar();
    applySkin();
    timeline = new AnimTimelineView(this, camUI);
    add(timeline);

    layoutReady = true;
    onLayoutChanged();
    fitView();
    setTool('brush', true);
    refreshAll();
  }

  /**
   * The Animator's own look: colored panel headers, a themed status bar and the "QOL ANIMATOR" badge.
   */
  function applySkin():Void
  {
    badge = new Label();
    badge.text = 'QOL ANIMATOR';
    badge.width = 128;
    badge.tooltip = 'The QOL Slice Animator. Press F1 for the guide.';
    root.addComponent(badge);
    themeButton = new Button();
    themeButton.text = 'Theme';
    themeButton.icon = AnimatorSkin.icon('palette', 16, 0xFFFFFFFF, true);
    themeButton.height = 24;
    themeButton.width = 86;
    themeButton.addClass('anim-icon-button');
    themeButton.tooltip = 'Change the Animator\'s colors to anything you like';
    themeButton.onClick = _ -> openThemeDialog();
    root.addComponent(themeButton);
    restyle();
  }

  /**
   * Inline styles that use theme colors (re-run when the theme changes).
   */
  function restyle():Void
  {
    var c = AnimatorSkin.css;
    var panel = c(AnimatorSkin.PANEL), border = c(AnimatorSkin.BORDER);
    var on = c(AnimatorSkin.ON_ACCENT);
    toolsPanel.setSkin(panel, border, 'background: ${c(AnimatorSkin.ACCENT)} ${c(AnimatorSkin.lighten(AnimatorSkin.ACCENT, 0.25))} horizontal;', on);
    inspector.setSkin(panel, border, 'background: ${c(AnimatorSkin.ACCENT2)} ${c(AnimatorSkin.lighten(AnimatorSkin.ACCENT2, 0.25))} horizontal;',
      c(AnimatorSkin.luminance(AnimatorSkin.ACCENT2) > 0.72 ? AnimatorSkin.INK : 0xFFFFFFFF));
    statusBar.styleString = 'background: ${c(AnimatorSkin.lighten(AnimatorSkin.PANEL, 0.04))} ${c(AnimatorSkin.darken(AnimatorSkin.PANEL, 0.12))} vertical; '
      + 'border-top: 1px solid $border; padding-left: 8px; padding-right: 8px; padding-top: 4px;';
    statusLabel.styleString = 'color: ${c(AnimatorSkin.TEXT_SOFT)};';
    statusRight.styleString = 'text-align: right; color: ${c(AnimatorSkin.ACCENT_TEXT)};';
    badge.styleString = 'background: ${c(AnimatorSkin.ACCENT)} ${c(AnimatorSkin.ACCENT2)} horizontal; border: 1px solid ${c(AnimatorSkin.lighten(AnimatorSkin.ACCENT, 0.55))}; '
      + 'border-radius: 11px; padding-top: 4px; padding-bottom: 4px; color: $on; font-bold: true; font-size: 12px; text-align: center;';
    ctrlBar.styleString = 'spacing: 4px; background: ${c(AnimatorSkin.lighten(AnimatorSkin.BUTTON_BOTTOM, 0.02))} ${c(AnimatorSkin.darken(AnimatorSkin.BUTTON_BOTTOM, 0.12))} vertical; '
      + 'border-top: 1px solid $border; border-bottom: 1px solid $border; padding-left: 8px; padding-right: 8px; padding-top: 4px;';
    pathLabel.styleString = 'color: ${c(AnimatorSkin.ACCENT_TEXT)}; font-bold: true; padding-top: 6px; padding-right: 4px;';
    frameLabel.styleString = 'background-color: ${c(AnimatorSkin.FIELD)}; border: 1px solid $border; border-radius: 12px; color: #9FE8FF; padding-top: 5px; '
      + 'padding-bottom: 5px; text-align: center; font-bold: true;';
    camWorld.bgColor = AnimatorSkin.BG_BOTTOM;
  }

  function onThemeChanged():Void
  {
    restyle();
    decor.refreshTheme();
    decorKey = '';
    renderDirty = true;
  }

  /**
   * Theme: presets and three colors (accent, second accent, background), applied as you pick them.
   */
  function openThemeDialog():Void
  {
    var before = AnimatorSkin.theme;
    var dialog = themePopup(new haxe.ui.containers.dialogs.Dialog());
    dialog.title = 'Animator Theme';
    dialog.buttons = DialogButton.CANCEL | 'Done';
    dialog.destroyOnClose = true;
    var box = new VBox();
    box.styleString = 'spacing: 8px;';
    var intro = new Label();
    intro.text = 'Pick a preset, or choose any colors below. Changes show right away.';
    intro.width = 340;
    intro.addClass('anim-note');
    box.addComponent(intro);

    var form = new QOLForm(110, 150);
    function apply(t:AnimTheme)
    {
      AnimatorSkin.applyTheme(t);
      onThemeChanged();
      form.refresh();
    }
    var grid = new VBox();
    grid.styleString = 'spacing: 4px;';
    var row:Null<HBox> = null;
    for (i in 0...AnimatorSkin.PRESETS.length)
    {
      var p = AnimatorSkin.PRESETS[i];
      if (i % 2 == 0)
      {
        row = new HBox();
        row.styleString = 'spacing: 4px;';
        grid.addComponent(row);
      }
      var b = new Button();
      b.text = p.name;
      b.width = 168;
      b.height = 28;
      b.icon = AnimatorSkin.themeSwatch(p);
      b.styleString = 'text-align: left;';
      b.onClick = _ -> apply(p);
      row.addComponent(b);
    }
    box.addComponent(grid);

    form.section('Your colors');
    form.colorField('Accent', () -> AnimatorSkin.theme.accent, v -> apply({
      name: 'Custom',
      accent: v,
      accent2: AnimatorSkin.theme.accent2,
      base: AnimatorSkin.theme.base
    }));
    form.colorField('Second accent', () -> AnimatorSkin.theme.accent2, v -> apply({
      name: 'Custom',
      accent: AnimatorSkin.theme.accent,
      accent2: v,
      base: AnimatorSkin.theme.base
    }));
    form.colorField('Background', () -> AnimatorSkin.theme.base, v -> apply({
      name: 'Custom',
      accent: AnimatorSkin.theme.accent,
      accent2: AnimatorSkin.theme.accent2,
      base: v
    }));
    form.note('The background color sets the panels\' tint; they always stay dark so drawings stand out.');
    form.buttons([
      {
        text: 'Surprise me!',
        cb: () -> {
          var h = Math.random() * 360;
          apply({
            name: 'Custom',
            accent: AnimatorSkin.fromHsl(h, 0.85, 0.62),
            accent2: AnimatorSkin.fromHsl((h + 40 + Math.random() * 80) % 360, 0.8, 0.62),
            base: AnimatorSkin.fromHsl((h + 180 + Math.random() * 60) % 360, 0.45, 0.16)
          });
        }
      },
      {text: 'Reset', cb: () -> apply(AnimatorSkin.PRESETS[0])}
    ]);
    box.addComponent(form);
    dialog.addComponent(box);
    dialog.onDialogClosed = function(e) {
      if (e.button == DialogButton.CANCEL)
      {
        AnimatorSkin.applyTheme(before);
        onThemeChanged();
      }
    };
    dialog.showDialog(true);
  }

  var layoutReady:Bool = false;

  override function onLayoutChanged():Void
  {
    if (!layoutReady) return;
    // The bar spans the whole bottom area (buttons outside a container's width can't be clicked).
    ctrlBar.left = 0;
    ctrlBar.top = workBottom;
    ctrlBar.width = FlxG.width;
    ctrlBar.height = CONTROLS_H;
    if (viewBar != null)
    {
      viewBar.left = workRight - (viewBar.width > 0 ? viewBar.width : 420) - 10;
      viewBar.top = workBottom - 34;
    }
    if (badge != null)
    {
      badge.left = FlxG.width - 128 - 8;
      badge.top = 5;
      themeButton.left = FlxG.width - 128 - 8 - 86 - 6;
      themeButton.top = 4;
    }
    timeline.setBounds(0, workBottom + CONTROLS_H, FlxG.width, FlxG.height - (workBottom + CONTROLS_H) - QOLEditorState.STATUSBAR_HEIGHT);
  }

  function buildMenus():Void
  {
    var file = addMenu('File');
    addMenuItem(file, 'New Animation...', 'Ctrl+N', newDocDialog);
    addMenuItem(file, 'Open...', 'Ctrl+O', openDialog);
    addMenuItem(file, 'Save', 'Ctrl+S', () -> doSave());
    addMenuItem(file, 'Save As...', null, () -> prompt('Save As', 'Animation name', doc.project.name, n -> {
      if (n == null || n == '') return;
      doc.project.name = n;
      doSave();
    }));
    addMenuSeparator(file);
    var imp = addSubMenu(file, 'Import');
    addMenuItem(imp, 'Image to Library (PNG)...', null, () -> AnimImport.importLibraryImage(this));
    addMenuItem(imp, 'Sparrow Spritesheet (PNG + XML)...', null, () -> AnimImport.importSparrow(this));
    addMenuItem(imp, 'Animate Texture Atlas (Animation.json)...', null, () -> AnimImport.importAnimateAtlas(this));
    addMenuItem(imp, 'PNG Sequence...', null, () -> AnimImport.importSequence(this));
    addMenuItem(imp, 'Sprite Sheet Grid...', null, () -> AnimImport.importGrid(this));
    addMenuItem(imp, 'Adobe Animate File (.fla / .xfl)...', null, () -> AnimImport.importFla(this));
    addMenuItem(imp, 'Photoshop / ToonSquid / ibisPaint (.psd)...', null, () -> AnimImport.importPsd(this));
    addMenuItem(imp, 'Video (MP4 / MOV)...', null, () -> AnimImport.importVideo(this));
    var exp = addSubMenu(file, 'Export');
    addMenuItem(exp, 'Sprite Atlas for the Game (Sparrow PNG + XML)...', null, () -> AnimExport.sparrowDialog(this));
    addMenuItem(exp, 'Animate Texture Atlas (Animation.json + spritemap)...', null, () -> AnimExport.animateDialog(this));
    addMenuItem(exp, 'PNG Sequence...', null, () -> AnimExport.sequenceDialog(this));
    addMenuItem(exp, 'Adobe Animate File (.fla)...', null, () -> AnimExport.flaDialog(this));
    addMenuItem(exp, 'Animated PSD (for ToonSquid)...', null, () -> AnimExport.psdDialog(this, true));
    addMenuItem(exp, 'Layered PSD per Frame (for ibisPaint)...', null, () -> AnimExport.psdDialog(this, false));

    var edit = addMenu('Edit');
    addMenuItem(edit, 'Undo', 'Ctrl+Z', undo);
    addMenuItem(edit, 'Redo', 'Ctrl+Y', redo);
    addMenuSeparator(edit);
    addMenuItem(edit, 'Cut', 'Ctrl+X', () -> {
      copySelection();
      deleteSelection();
    });
    addMenuItem(edit, 'Copy', 'Ctrl+C', copySelection);
    addMenuItem(edit, 'Paste', 'Ctrl+V', pasteSelection);
    addMenuItem(edit, 'Delete', 'Delete', deleteSelection);
    addMenuItem(edit, 'Select All', 'Ctrl+A', selectAll);
    addMenuSeparator(edit);
    addMenuItem(edit, 'Copy Frames', 'Ctrl+Alt+C', copyFrames);
    addMenuItem(edit, 'Paste Frames', 'Ctrl+Alt+V', pasteFrames);

    var modify = addMenu('Modify');
    addMenuItem(modify, 'Convert to Symbol', 'F8', convertToSymbol);
    addMenuItem(modify, 'Break Apart', 'Ctrl+B', breakApart);
    addMenuSeparator(modify);
    addMenuItem(modify, 'Flip Horizontal', null, () -> transformSelection(m -> m.scale(-1, 1)));
    addMenuItem(modify, 'Flip Vertical', null, () -> transformSelection(m -> m.scale(1, -1)));
    addMenuItem(modify, 'Rotate 90 Clockwise', null, () -> transformSelection(m -> m.rotate(Math.PI / 2)));
    addMenuItem(modify, 'Rotate 90 Counter-Clockwise', null, () -> transformSelection(m -> m.rotate(-Math.PI / 2)));
    addMenuSeparator(modify);
    addMenuItem(modify, 'Bring to Front', 'Ctrl+Shift+Up', () -> arrange(99999));
    addMenuItem(modify, 'Bring Forward', 'Ctrl+Up', () -> arrange(1));
    addMenuItem(modify, 'Send Backward', 'Ctrl+Down', () -> arrange(-1));
    addMenuItem(modify, 'Send to Back', 'Ctrl+Shift+Down', () -> arrange(-99999));

    var insert = addMenu('Timeline');
    addMenuItem(insert, 'Insert Frame', 'F5', () -> insertFrames(1));
    addMenuItem(insert, 'Remove Frames', 'Shift+F5', removeFrames);
    addMenuItem(insert, 'Insert Keyframe', 'F6', () -> insertKeyframe(false));
    addMenuItem(insert, 'Insert Blank Keyframe', 'F7', () -> insertKeyframe(true));
    addMenuItem(insert, 'Clear Keyframe', 'Shift+F6', clearKeyframe);
    addMenuSeparator(insert);
    addMenuItem(insert, 'Create Classic Tween', null, () -> setTween(true));
    addMenuItem(insert, 'Remove Tween', null, () -> setTween(false));
    addMenuItem(insert, 'Reverse Frames', null, reverseFrames);
    addMenuSeparator(insert);
    addMenuItem(insert, 'New Layer', null, () -> addLayer('vector'));
    addMenuItem(insert, 'New Bitmap Layer', null, () -> addLayer('bitmap'));
    addMenuItem(insert, 'Add Camera', null, () -> addCamera());
    addMenuItem(insert, 'Delete Layer', null, deleteLayer);
    addMenuItem(insert, 'Duplicate Layer', null, duplicateLayer);

    var view = addMenu('View');
    addMenuItem(view, 'Zoom In', 'Ctrl+=', () -> zoomAt(1.25, centerX(), centerY()));
    addMenuItem(view, 'Zoom Out', 'Ctrl+-', () -> zoomAt(0.8, centerX(), centerY()));
    addMenuItem(view, 'Fit Stage', 'Ctrl+0', fitView);
    addMenuItem(view, '100%', 'Ctrl+1', () -> {
      zoom = 1;
      centerStage();
    });
    addMenuSeparator(view);
    addMenuCheck(view, 'Onion Skin', onion, v -> {
      onion = v;
      renderDirty = true;
    });
    addMenuCheck(view, 'Loop Playback', loopPlayback, v -> loopPlayback = v);
    addMenuSeparator(view);
    addMenuItem(view, 'Theme...', null, () -> openThemeDialog());
    addMenuItem(view, 'Canvas Color...', null, () -> openCanvasColorDialog());
    addMenuSeparator(view);
    addMenuItem(view, 'Turn View Left', null, () -> rotateView(-15));
    addMenuItem(view, 'Turn View Right', null, () -> rotateView(15));
    addMenuItem(view, 'Straighten View', null, () -> rotateView(0, true));
    addMenuItem(view, 'Mirror View', null, () -> flipView());

    var control = addMenu('Control');
    addMenuItem(control, 'Play / Stop', 'Enter', togglePlay);
    addMenuItem(control, 'Next Frame', '.', () -> setFrame(frame + 1));
    addMenuItem(control, 'Previous Frame', ',', () -> setFrame(Std.int(Math.max(0, frame - 1))));
    addMenuItem(control, 'First Frame', 'Home', () -> setFrame(0));
    addMenuItem(control, 'Last Frame', 'End', () -> setFrame(AnimData.symbolLength(sym) - 1));
  }

  function buildToolsPanel():Void
  {
    toolsPanel = addDockPanel('tools', 'Tools', 150, 'left');
    var box = new VBox();
    box.styleString = 'spacing: 4px;';
    var row:Null<HBox> = null;
    for (i in 0...TOOLS.length)
    {
      var t = TOOLS[i];
      if (i % 3 == 0)
      {
        row = new HBox();
        row.styleString = 'spacing: 4px;';
        box.addComponent(row);
      }
      var b = new Button();
      b.width = 38;
      b.height = 36;
      b.addClass('anim-tool');
      b.icon = AnimatorSkin.icon(t.id, 22, AnimatorSkin.TOOL_COLORS.get(t.id));
      b.tooltip = '${t.name}  (${t.key})';
      var id = t.id;
      b.onClick = _ -> setTool(id);
      toolButtons.set(t.id, b);
      row.addComponent(b);
    }
    toolsPanel.content.addComponent(box);

    colorForm = new QOLForm(44, 72);
    colorForm.section('Colors');
    colorForm.colorField('Stroke', () -> strokeColor | 0xFF000000, v -> strokeColor = (strokeColor & 0xFF000000) | (v & 0xFFFFFF));
    colorForm.colorField('Fill', () -> fillColor | 0xFF000000, v -> fillColor = (fillColor & 0xFF000000) | (v & 0xFFFFFF));
    var swap = new Button();
    swap.text = 'Swap';
    swap.icon = AnimatorSkin.icon('swap', 14, 0xFFFFFFFF, false);
    swap.width = 122;
    swap.tooltip = 'Swap the stroke and fill colors (X)';
    swap.onClick = _ -> swapColors();
    colorForm.addComponent(swap);
    toolsPanel.content.addComponent(colorForm);

    // Quick palette: click = fill, right-click = stroke.
    var paletteBox = new VBox();
    paletteBox.styleString = 'spacing: 4px;';
    var prow:Null<HBox> = null;
    for (i in 0...AnimatorSkin.PALETTE.length)
    {
      var p = AnimatorSkin.PALETTE[i];
      if (i % 4 == 0)
      {
        prow = new HBox();
        prow.styleString = 'spacing: 4px;';
        paletteBox.addComponent(prow);
      }
      var sw = new Box();
      sw.width = 26;
      sw.height = 22;
      sw.addClass('anim-swatch');
      sw.styleString = 'background-color: #${StringTools.hex(p.color & 0xFFFFFF, 6)};';
      sw.tooltip = '${p.name}\nClick: fill  \u00B7  Right-click: stroke';
      var color = p.color;
      sw.onClick = _ -> {
        fillColor = (fillColor & 0xFF000000) | (color & 0xFFFFFF);
        colorForm.refresh();
      };
      sw.registerEvent(MouseEvent.RIGHT_CLICK, _ -> {
        strokeColor = (strokeColor & 0xFF000000) | (color & 0xFFFFFF);
        colorForm.refresh();
      });
      prow.addComponent(sw);
    }
    toolsPanel.content.addComponent(paletteBox);
    var tip = new Label();
    tip.text = 'Brush & bucket use Fill; pencil, lines and outlines use Stroke.';
    tip.width = 122;
    tip.addClass('anim-note');
    toolsPanel.content.addComponent(tip);
  }

  function swapColors():Void
  {
    var t = strokeColor;
    strokeColor = fillColor;
    fillColor = t;
    colorForm.refresh();
  }

  function buildInspector():Void
  {
    inspector = addDockPanel('inspector', 'Inspector', 330, 'right');
    tabs = new TabView();
    tabs.width = 330 - 28;
    tabs.height = 560;
    inspector.content.addComponent(tabs);

    var propsPage = new VBox();
    propsPage.text = 'Properties';
    propsPage.styleString = 'padding: 4px;';
    propsBox = new VBox();
    propsBox.width = 330 - 46;
    propsPage.addComponent(propsBox);
    tabs.addComponent(propsPage);

    var libPage = new VBox();
    libPage.text = 'Library';
    libPage.styleString = 'padding: 4px; spacing: 6px;';
    libList = new ListView();
    libList.width = 330 - 46;
    libList.height = 300;
    libList.onDblClick = _ -> libraryOpen();
    libPage.addComponent(libList);
    var libForm = new QOLForm(0, 330 - 52);
    libForm.buttons([
      {text: 'Place on stage', cb: libraryPlace},
      {text: 'Edit', cb: libraryOpen}
    ]);
    libForm.buttons([
      {text: 'New symbol', cb: newSymbol},
      {text: 'Rename', cb: libraryRename},
      {text: 'Duplicate', cb: libraryDuplicate}
    ]);
    libForm.buttons([{text: 'Delete', cb: libraryDelete}]);
    libForm.note('Symbols have their own timeline. Double-click one to edit it; place it on the stage to use it (tween it, add filters...).');
    libPage.addComponent(libForm);
    tabs.addComponent(libPage);

    var docPage = new VBox();
    docPage.text = 'Document';
    docPage.styleString = 'padding: 4px;';
    docForm = new QOLForm(110, 170);
    docForm.section('Animation');
    docForm.textField('Name', () -> doc.project.name, v -> doc.project.name = v);
    docForm.pair('Stage size', () -> doc.project.width, v -> resizeStage(Std.int(v), doc.project.height), () -> doc.project.height,
      v -> resizeStage(doc.project.width, Std.int(v)), 1, 0, 16, 4096);
    docForm.number('Frame rate', () -> doc.project.fps, v -> doc.project.fps = Math.max(1, v), 1, 120, 1, 0);
    docForm.colorField('Background', () -> doc.project.bg | 0xFF000000, v -> {
      doc.project.bg = (doc.project.bg & 0xFF000000) | (v & 0xFFFFFF);
      renderDirty = true;
    });
    docForm.check('Transparent background', () -> (doc.project.bg >>> 24) == 0, v -> {
      doc.project.bg = v ? (doc.project.bg & 0xFFFFFF) : (doc.project.bg | 0xFF000000);
      renderDirty = true;
    });
    docForm.section('Onion skin');
    docForm.check('Show onion skin', () -> onion, v -> {
      onion = v;
      renderDirty = true;
    });
    docForm.pair('Frames before / after', () -> onionBefore, v -> {
      onionBefore = Std.int(v);
      renderDirty = true;
    }, () -> onionAfter, v -> {
      onionAfter = Std.int(v);
      renderDirty = true;
    }, 1, 0, 0, 10);
    docForm.onAnyChange = () -> dirty = true;
    docPage.addComponent(docForm);
    tabs.addComponent(docPage);
  }

  function buildControls():Void
  {
    ctrlBar = new HBox();
    root.addComponent(ctrlBar);
    pathLabel = new Label();
    ctrlBar.addComponent(pathLabel);
    backButton = iconButton('back', 'Scene', 'Stop editing this symbol (Esc)', () -> exitSymbol(true));
    ctrlBar.addComponent(backButton);
    ctrlBar.addComponent(gap(6));
    ctrlBar.addComponent(iconButton('first', null, 'First frame (Home)', () -> setFrame(0)));
    ctrlBar.addComponent(iconButton('prev', null, 'Previous frame (,)', () -> setFrame(Std.int(Math.max(0, frame - 1)))));
    playButton = iconButton('play', null, 'Play / stop (Enter)', togglePlay, 18);
    playButton.width = 46;
    playButton.addClass('anim-play');
    ctrlBar.addComponent(playButton);
    ctrlBar.addComponent(iconButton('next', null, 'Next frame (.)', () -> setFrame(frame + 1)));
    ctrlBar.addComponent(iconButton('last', null, 'Last frame (End)', () -> setFrame(AnimData.symbolLength(sym) - 1)));
    loopButton = iconButton('loop', null, 'Loop playback', () -> {
      loopPlayback = !loopPlayback;
      updateToggles();
    });
    ctrlBar.addComponent(loopButton);
    onionButton = iconButton('onion', null, 'Onion skin: see the frames around this one', () -> {
      onion = !onion;
      renderDirty = true;
      docForm.refresh();
      updateToggles();
    });
    ctrlBar.addComponent(onionButton);
    frameLabel = new Label();
    frameLabel.width = 150;
    ctrlBar.addComponent(frameLabel);
    ctrlBar.addComponent(gap(10));
    ctrlBar.addComponent(colored(iconButton('layer', 'Layer', 'New vector layer', () -> addLayer('vector'), 16, AnimatorSkin.CYAN), 'cyan'));
    ctrlBar.addComponent(colored(iconButton('bitmap', 'Paint Layer', 'New bitmap layer, for painting pixels', () -> addLayer('bitmap'), 16, AnimatorSkin.GREEN), 'green'));
    ctrlBar.addComponent(colored(iconButton('camera', null, 'Camera: add an animatable camera (pan, zoom, turn)', () -> addCamera(), 16, AnimatorSkin.YELLOW), 'yellow'));
    ctrlBar.addComponent(colored(iconButton('trash', null, 'Delete the selected layer', deleteLayer, 16, 0xFFFF6B6B), 'red'));
    ctrlBar.addComponent(gap(10));
    ctrlBar.addComponent(colored(iconButton('frame', 'Frame', 'Insert frame (F5)', () -> insertFrames(1), 16, 0xFFEDE6FF), 'purple'));
    ctrlBar.addComponent(colored(iconButton('keyframe', 'Keyframe', 'Insert keyframe (F6)', () -> insertKeyframe(false), 16, AnimatorSkin.YELLOW), 'yellow'));
    ctrlBar.addComponent(colored(iconButton('blank', 'Blank', 'Insert blank keyframe (F7)', () -> insertKeyframe(true), 16, AnimatorSkin.YELLOW), 'yellow'));
    ctrlBar.addComponent(colored(iconButton('tween', 'Tween', 'Classic tween from this keyframe to the next', () -> setTween(true), 16, AnimatorSkin.PURPLE), 'purple'));
    updateToggles();
  }

  function iconButton(iconName:String, text:Null<String>, tip:String, cb:Void->Void, size:Int = 16, color:Int = 0xFFFFFFFF):Button
  {
    var b = new Button();
    if (text != null) b.text = text;
    b.icon = AnimatorSkin.icon(iconName, size, color, true);
    b.tooltip = tip;
    b.height = 26;
    if (text == null) b.width = 32;
    b.addClass('anim-icon-button');
    b.onClick = _ -> cb();
    return b;
  }

  static function colored(b:Button, name:String):Button
  {
    b.addClass('anim-btn-$name');
    return b;
  }

  static function gap(w:Int):Box
  {
    var g = new Box();
    g.width = w;
    g.height = 4;
    return g;
  }

  function updateToggles():Void
  {
    if (loopButton != null)
    {
      if (loopPlayback) loopButton.addClass('anim-on');
      else
        loopButton.removeClass('anim-on');
    }
    if (onionButton != null)
    {
      if (onion) onionButton.addClass('anim-on');
      else
        onionButton.removeClass('anim-on');
    }
  }

  function smallButton(text:String, tip:String, cb:Void->Void):Button
  {
    var b = new Button();
    b.text = text;
    b.tooltip = tip;
    b.onClick = _ -> cb();
    return b;
  }

  //
  // Document events
  //

  function onDocChanged():Void
  {
    renderDirty = true;
    dirty = true;
    clampState();
    refreshLibrary();
    refreshProps();
  }

  function clampState():Void
  {
    if (editPath.length > 0 && doc.symbol(editPath[editPath.length - 1]) == null) editPath = [];
    if (curLayer >= sym.layers.length) curLayer = sym.layers.length - 1;
    if (curLayer < 0) curLayer = 0;
    selection = [for (s in selection) if (validSel(s)) s];
  }

  function validSel(s:AnimSel):Bool
  {
    if (s.layer < 0 || s.layer >= sym.layers.length) return false;
    var key = AnimData.keyAt(sym.layers[s.layer], frame);
    return key != null && s.element >= 0 && s.element < key.elements.length;
  }

  function refreshAll():Void
  {
    clampState();
    renderDirty = true;
    refreshLibrary();
    refreshProps();
    docForm.refresh();
    colorForm.refresh();
    updateWindowTitle();
  }

  public function afterTimelineEdit():Void
  {
    renderDirty = true;
    dirty = true;
    refreshProps();
  }

  override function save():Bool
  {
    var path = AnimIO.save(doc);
    QOLConfig.setPref('animator.last', AnimIO.fileId(doc.project.name));
    notifySaved(path);
    return true;
  }

  function undo():Void
  {
    if (doc.undo())
    {
      selection = [];
      refreshAll();
    }
  }

  function redo():Void
  {
    if (doc.redo())
    {
      selection = [];
      refreshAll();
    }
  }

  function newDocDialog():Void
  {
    prompt('New animation', 'Name (saved in data/qol/animations/)', 'My Animation', name -> {
      if (name == null || name == '') return;
      function make()
      {
        doc = new AnimDoc(AnimData.newProject(name));
        doc.onChange = onDocChanged;
        renderer = new AnimRender(doc);
        editPath = [];
        frame = 0;
        curLayer = 0;
        selection = [];
        fitView();
        refreshAll();
        dirty = false;
      }
      if (dirty) confirm('Unsaved changes', 'Start a new animation without saving this one?', make);
      else
        make();
    });
  }

  function openDialog():Void
  {
    var ids = AnimIO.list();
    if (ids.length == 0)
    {
      alert('Nothing to open', 'This mod has no saved animations yet (they live in data/qol/animations/).');
      return;
    }
    chooseFromList('Open animation', ids, id -> {
      function open()
      {
        var loaded = AnimIO.load(id);
        if (loaded == null)
        {
          alert('Could not open', '$id.json could not be read.');
          return;
        }
        doc = loaded;
        doc.onChange = onDocChanged;
        renderer = new AnimRender(doc);
        editPath = [];
        frame = 0;
        curLayer = 0;
        selection = [];
        QOLConfig.setPref('animator.last', id);
        fitView();
        refreshAll();
        dirty = false;
      }
      if (dirty) confirm('Unsaved changes', 'Open another animation without saving this one?', open);
      else
        open();
    });
  }

  /**
   * Replace the open document (used by imports).
   */
  public function setDocument(d:AnimDoc):Void
  {
    doc = d;
    doc.onChange = onDocChanged;
    renderer = new AnimRender(doc);
    editPath = [];
    frame = 0;
    curLayer = 0;
    selection = [];
    fitView();
    refreshAll();
    dirty = true;
  }

  //
  // View
  //

  function centerX():Float
    return workLeft + (workRight - workLeft) / 2;

  function centerY():Float
    return QOLEditorState.MENUBAR_HEIGHT + (workBottom - QOLEditorState.MENUBAR_HEIGHT) / 2;

  public function fitView():Void
  {
    var w = Math.max(100, workRight - workLeft - 60);
    var h = Math.max(100, workBottom - QOLEditorState.MENUBAR_HEIGHT - 90);
    zoom = Math.min(w / doc.project.width, h / doc.project.height);
    zoom = Math.max(0.05, Math.min(8, zoom));
    centerStage();
  }

  function centerStage():Void
  {
    viewX = 0;
    viewY = 0;
    var p = stageMatrix().transformPoint(new Point(doc.project.width / 2, doc.project.height / 2));
    viewX = centerX() - p.x;
    viewY = centerY() - p.y;
  }

  function zoomAt(factor:Float, sx:Float, sy:Float):Void
  {
    var nz = Math.max(0.05, Math.min(16, zoom * factor));
    // Keep the point under the cursor still.
    keepPointWhile(sx, sy, () -> zoom = nz);
  }

  /**
   * Change the view while keeping the stage point under (sx, sy) where it is.
   */
  function keepPointWhile(sx:Float, sy:Float, change:Void->Void):Void
  {
    var inv = stageMatrix();
    inv.invert();
    var p = inv.transformPoint(new Point(sx, sy));
    change();
    var q = stageMatrix().transformPoint(p);
    viewX += sx - q.x;
    viewY += sy - q.y;
  }

  public function rotateView(deg:Float, ?absolute:Bool = false):Void
  {
    keepPointWhile(centerX(), centerY(), () -> {
      viewRotation = absolute ? deg : viewRotation + deg;
      viewRotation = ((viewRotation % 360) + 540) % 360 - 180;
      if (Math.abs(viewRotation) < 0.01) viewRotation = 0;
    });
  }

  public function flipView():Void
  {
    keepPointWhile(centerX(), centerY(), () -> viewFlip = !viewFlip);
  }

  /**
   * Stage coordinates -> screen (game) coordinates: zoom, rotation and flip around the stage's middle.
   */
  public function stageMatrix():Matrix
  {
    var w = doc.project.width, h = doc.project.height;
    var m = new Matrix();
    m.translate(-w / 2, -h / 2);
    if (viewFlip) m.scale(-1, 1);
    if (viewRotation != 0) m.rotate(viewRotation * Math.PI / 180);
    m.scale(zoom, zoom);
    m.translate(w / 2 * zoom + viewX, h / 2 * zoom + viewY);
    return m;
  }

  /**
   * The camera's world -> stage matrix while it's shown (main timeline only), or null.
   */
  function viewCamera():Null<Matrix>
  {
    if (!cameraView || editPath.length > 0) return null;
    return renderer.cameraMatrix(sym, frame);
  }

  /**
   * Symbol coordinates -> screen.
   */
  function fullMatrix():Matrix
  {
    var m = new Matrix();
    m.translate(symOffsetX(), symOffsetY());
    var cam = viewCamera();
    if (cam != null) m.concat(cam);
    m.concat(stageMatrix());
    return m;
  }

  /**
   * Where symbol (0, 0) is on the stage while editing a symbol (its registration point goes in the middle).
   */
  function symOffsetX():Float
    return editPath.length == 0 ? 0 : doc.project.width / 2;

  function symOffsetY():Float
    return editPath.length == 0 ? 0 : doc.project.height / 2;

  /**
   * Screen (game) position -> coordinates in the symbol being edited.
   */
  public function toLocal(sx:Float, sy:Float):Point
  {
    var m = fullMatrix();
    m.invert();
    return m.transformPoint(new Point(sx, sy));
  }

  public function toScreen(lx:Float, ly:Float):Point
    return fullMatrix().transformPoint(new Point(lx, ly));

  /**
   * Screen pixels per drawing pixel (zoom times the camera's zoom).
   */
  function screenScale():Float
  {
    var m = fullMatrix();
    return Math.sqrt(Math.abs(m.a * m.d - m.b * m.c));
  }

  /**
   * The stage's corners on screen.
   */
  function stageCorners():Array<Point>
  {
    var m = stageMatrix();
    var w = doc.project.width, h = doc.project.height;
    return [
      m.transformPoint(new Point(0, 0)),
      m.transformPoint(new Point(w, 0)),
      m.transformPoint(new Point(w, h)),
      m.transformPoint(new Point(0, h))
    ];
  }

  //
  // Frame update
  //

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);
    if (playtestPending) return;

    if (playing)
    {
      playTime += elapsed;
      var step = 1 / doc.project.fps;
      var len = AnimData.symbolLength(sym);
      while (playTime >= step)
      {
        playTime -= step;
        var next = frame + 1;
        if (next >= len)
        {
          if (loopPlayback) next = 0;
          else
          {
            next = len - 1;
            stop();
          }
        }
        setFrame(next, false);
      }
      timeline.follow(frame);
    }

    // Property edits made in one mouse press (or one typed value) undo together.
    if (!FlxG.mouse.pressed && !isTyping) editStarted = false;
    handleMouse();
    if (propsDirty && !playing) rebuildProps();
    renderCanvas();
    timeline.redraw();
    updateLabels();
    updateDecor();
    updateViewBar();
  }

  function updateLabels():Void
  {
    var len = AnimData.symbolLength(sym);
    var t = frame / doc.project.fps;
    var text = '${frame + 1} / $len  \u00B7  ${Std.string(Math.round(t * 100) / 100)}s';
    if (frameLabel.text != text) frameLabel.text = text;
    var path = editPath.length == 0 ? 'Scene' : 'Scene > ' + [for (id in editPath) doc.symbol(id)?.name ?? id].join(' > ');
    if (pathLabel.text != path) pathLabel.text = path;
    var inSymbol = editPath.length > 0;
    if (backButton.hidden == inSymbol) backButton.hidden = !inSymbol;
    updateToggles();
    if (playIconShown != playing)
    {
      playIconShown = playing;
      playButton.icon = AnimatorSkin.icon(playing ? 'pause' : 'play', 18, 0xFFFFFFFF, true);
    }
  }

  function renderCanvas():Void
  {
    var s = FlxG.scaleMode.scale;
    attachCanvas();
    canvasRoot.scaleX = s.x;
    canvasRoot.scaleY = s.y;
    canvasRoot.x = camCanvas.flashSprite.x - camCanvas.width * 0.5 * s.x;
    canvasRoot.y = camCanvas.flashSprite.y - camCanvas.height * 0.5 * s.y;
    stageHolder.transform.matrix = stageMatrix();
    var cam = viewCamera();
    worldHolder.transform.matrix = cam ?? new Matrix();
    worldHolder.mask = clipStage ? stageMask : null;
    stageMask.visible = clipStage;
    if (clipStage)
    {
      var mg = stageMask.graphics;
      mg.clear();
      mg.beginFill(0xFFFFFF, 1);
      mg.drawRect(0, 0, doc.project.width, doc.project.height);
      mg.endFill();
    }
    drawCameraFrame();
    drawStageDecor();

    if (renderDirty)
    {
      renderDirty = false;
      if (!playing) canvasEmpty = !hasAnyContent();
      drawChecker();
      contentHolder.removeChildren();
      var content = renderer.render(sym, frame, {collectHits: true});
      content.x = symOffsetX();
      content.y = symOffsetY();
      contentHolder.addChild(content);
      onionHolder.removeChildren();
      if (onion && !playing)
      {
        for (i in 1...onionBefore + 1)
          addOnion(frame - i, 0xFFFF5C7A, 0.45 / i);
        for (i in 1...onionAfter + 1)
          addOnion(frame + i, 0xFF5CE18B, 0.45 / i);
      }
    }
    drawOverlay();
  }

  /**
   * The canvas sits in the game's display list right above its camera (not inside the camera's sprite, whose clipping
   * mask confused the web renderer while menus and popups were open).
   */
  function attachCanvas():Void
  {
    var game = FlxG.game;
    if (camCanvas.flashSprite.parent != game) return;
    if (canvasRoot.parent == game && game.getChildIndex(canvasRoot) == game.getChildIndex(camCanvas.flashSprite) + 1) return;
    if (canvasRoot.parent != null) canvasRoot.parent.removeChild(canvasRoot);
    game.addChildAt(canvasRoot, game.getChildIndex(camCanvas.flashSprite) + 1);
  }

  function addOnion(f:Int, color:Int, alpha:Float):Void
  {
    if (f < 0 || f >= AnimData.symbolLength(sym)) return;
    var spr = new AnimRender(doc).render(sym, f, {});
    spr.x = symOffsetX();
    spr.y = symOffsetY();
    var ct = new ColorTransform(0.4, 0.4, 0.4, alpha, ((color >> 16) & 0xFF) * 0.6, ((color >> 8) & 0xFF) * 0.6, (color & 0xFF) * 0.6);
    spr.transform.colorTransform = ct;
    onionHolder.addChild(spr);
  }

  function drawChecker():Void
  {
    var g = checker.graphics;
    g.clear();
    var w = doc.project.width, h = doc.project.height;
    if ((doc.project.bg >>> 24) == 0)
    {
      g.beginBitmapFill(checkerTile(), null, true, false);
      g.drawRect(0, 0, w, h);
      g.endFill();
    }
    else
    {
      g.beginFill(doc.project.bg & 0xFFFFFF, 1);
      g.drawRect(0, 0, w, h);
      g.endFill();
    }
    if (editPath.length > 0)
    {
      // Registration point crosshair.
      g.lineStyle(1, 0x5CE1FF, 0.9);
      g.moveTo(w / 2 - 12, h / 2);
      g.lineTo(w / 2 + 12, h / 2);
      g.moveTo(w / 2, h / 2 - 12);
      g.lineTo(w / 2, h / 2 + 12);
      g.lineStyle();
    }
  }

  /**
   * Soft shadow and a glowing frame around the stage (screen space, so they look the same at any zoom).
   */
  var decorKey:String = '';

  function drawStageDecor():Void
  {
    var c = stageCorners();
    var key = [for (p in c) '${Math.round(p.x * 10)},${Math.round(p.y * 10)}'].join(';') + '$playing,${AnimatorSkin.version}';
    if (key == decorKey) return;
    decorKey = key;
    var g = stageDecor.graphics;
    g.clear();
    inline function poly(ox:Float, oy:Float, grow:Float)
    {
      // Grow the quad outward from its middle.
      var mx = (c[0].x + c[2].x) / 2, my = (c[0].y + c[2].y) / 2;
      for (i in 0...5)
      {
        var p = c[i % 4];
        var dx = p.x - mx, dy = p.y - my;
        var len = Math.sqrt(dx * dx + dy * dy);
        var k = len == 0 ? 0 : grow / len * 1.41;
        var px = p.x + dx * k + ox, py = p.y + dy * k + oy;
        if (i == 0) g.moveTo(px, py);
        else
          g.lineTo(px, py);
      }
    }
    for (i in 0...6)
    {
      g.beginFill(0x07040F, 0.09);
      poly(5, 9, 2 + i * 3);
      g.endFill();
    }
    g.lineStyle(5, AnimatorSkin.ACCENT & 0xFFFFFF, playing ? 0.32 : 0.16);
    poly(0, 0, 3.5);
    g.lineStyle(1.5, 0xFFFFFF, 0.5);
    poly(0, 0, 1);
    g.lineStyle();
  }

  /**
   * The camera's view as a frame: shown when looking past the camera, or while the camera layer is selected.
   */
  function drawCameraFrame():Void
  {
    var g = camFrame.graphics;
    g.clear();
    if (editPath.length > 0) return;
    var cam = renderer.cameraAt(sym, frame);
    if (cam == null) return;
    var layer = currentLayer();
    var selected = layer != null && layer.kind == 'camera';
    if (cameraView && !selected) return;
    // The stage rectangle, taken back into world coordinates.
    var inv = renderer.matrixOf(cam);
    inv.invert();
    var w = doc.project.width, h = doc.project.height;
    var corners:Array<Array<Float>> = [[0, 0], [w, 0], [w, h], [0, h]];
    var pts = [for (p in corners) inv.transformPoint(new Point(p[0], p[1]))];
    var lw = 2 / Math.max(0.01, screenScale());
    g.lineStyle(lw * 2, 0x000000, 0.35);
    g.moveTo(pts[0].x, pts[0].y);
    for (i in 1...5)
      g.lineTo(pts[i % 4].x, pts[i % 4].y);
    g.lineStyle(lw, AnimatorSkin.YELLOW & 0xFFFFFF, 1);
    g.moveTo(pts[0].x, pts[0].y);
    for (i in 1...5)
      g.lineTo(pts[i % 4].x, pts[i % 4].y);
    // Crosshair in the middle.
    var cx = (pts[0].x + pts[2].x) / 2, cy = (pts[0].y + pts[2].y) / 2;
    var arm = 14 / Math.max(0.01, screenScale());
    g.moveTo(cx - arm, cy);
    g.lineTo(cx + arm, cy);
    g.moveTo(cx, cy - arm);
    g.lineTo(cx, cy + arm);
    g.lineStyle();
  }

  var canvasEmpty:Bool = false;
  /**
   * Whether each canvas has any pixels (canvases never change once painted; painting makes a new one).
   */
  var canvasHasPixels:Map<String, Bool> = new Map<String, Bool>();

  /**
   * Whether anything has been drawn yet (for the "Blank canvas!" hint).
   */
  function hasAnyContent():Bool
  {
    var blankCanvases:Array<String> = [];
    for (sy in doc.project.symbols)
      for (l in sy.layers)
        for (k in l.frames)
        {
          if (k.elements.length > 0) return true;
          if (k.bitmap != null) blankCanvases.push(k.bitmap);
        }
    if (doc.project.symbols.length > 1) return true;
    for (id in blankCanvases)
    {
      var known = canvasHasPixels.get(id);
      if (known == true) return true;
      if (known == false) continue;
      var bmp = doc.getBitmap(id);
      if (bmp == null) continue;
      var r = bmp.getColorBoundsRect(0xFF000000, 0x00000000, false);
      var has = r.width > 0 && r.height > 0;
      // The canvas being painted right now still changes.
      if (bmp != paintBitmap || has) canvasHasPixels.set(id, has);
      if (has) return true;
    }
    return false;
  }

  function updateDecor():Void
  {
    var p = doc.project;
    var label = editPath.length == 0 ? '${p.name}  \u00B7  ${p.width} x ${p.height}  \u00B7  ${p.fps} fps' : 'Editing symbol: ${sym.name}';
    var corners = stageCorners();
    var minX = corners[0].x, minY = corners[0].y;
    for (c in corners)
    {
      if (c.x < minX) minX = c.x;
      if (c.y < minY) minY = c.y;
    }
    decor.setStageTag(minX, minY, label, workLeft + 8, QOLEditorState.MENUBAR_HEIGHT + 6, workRight - 8);
    var mid = stageMatrix().transformPoint(new Point(p.width / 2, p.height / 2));
    var cx = Math.max(workLeft + 200, Math.min(workRight - 200, mid.x));
    var cy = Math.max(QOLEditorState.MENUBAR_HEIGHT + 90, Math.min(workBottom - 60, mid.y));
    decor.setHint(canvasEmpty && !playing && !FlxG.mouse.pressed && editPath.length == 0, cx, cy);
  }

  static var _checker:Null<BitmapData> = null;

  static function checkerTile():BitmapData
  {
    if (_checker == null)
    {
      _checker = new BitmapData(32, 32, false, 0xFFFFFFFF);
      _checker.fillRect(new Rectangle(0, 0, 16, 16), 0xFFDCDCE4);
      _checker.fillRect(new Rectangle(16, 16, 16, 16), 0xFFDCDCE4);
    }
    return _checker;
  }

  //
  // Overlay (selection boxes, handles, brush cursor)
  //

  function drawOverlay():Void
  {
    var g = overlay.graphics;
    g.clear();
    // Selection.
    var b = selectionBounds();
    if (b != null && tool == 'select')
    {
      var hs = screenHandles(b);
      g.lineStyle(1, 0x5CE1FF, 1);
      g.moveTo(hs[0].x, hs[0].y);
      for (i in [2, 4, 6, 0])
        g.lineTo(hs[i].x, hs[i].y);
      for (h in hs)
      {
        g.beginFill(0xFFFFFF, 1);
        g.drawRect(h.x - 4, h.y - 4, 8, 8);
        g.endFill();
      }
      g.lineStyle();
    }
    // Marquee.
    if (drag == 'marquee')
    {
      g.lineStyle(1, 0xFFD84A, 1);
      g.beginFill(0xFFD84A, 0.08);
      g.drawRect(Math.min(cDragX, lastMX), Math.min(cDragY, lastMY), Math.abs(lastMX - cDragX), Math.abs(lastMY - cDragY));
      g.endFill();
      g.lineStyle();
    }
    // Brush cursor.
    if (overCanvas && (tool == 'brush' || tool == 'eraser' || tool == 'pencil'))
    {
      var size = toolSize() * screenScale();
      var paintColor = tool == 'pencil' ? strokeColor : fillColor;
      if (tool != 'eraser' && size > 6)
      {
        g.beginFill(paintColor & 0xFFFFFF, 0.25);
        g.drawCircle(lastMX, lastMY, size / 2);
        g.endFill();
      }
      g.lineStyle(1.5, 0xFFFFFF, 0.9);
      g.drawCircle(lastMX, lastMY, Math.max(1, size / 2));
      g.lineStyle(1, 0x1A1030, 0.6);
      g.drawCircle(lastMX, lastMY, Math.max(1, size / 2) + 1.5);
      g.lineStyle();
      if (tool != 'eraser')
      {
        g.beginFill(paintColor & 0xFFFFFF, 1);
        g.drawCircle(lastMX, lastMY, 1.8);
        g.endFill();
      }
    }
  }

  function toolSize():Float
  {
    return switch (tool)
    {
      case 'brush': brushSize;
      case 'eraser': eraserSize;
      case 'pencil': pencilSize;
      default: 1;
    }
  }

  /**
   * The 8 transform handles of a selection box (local coordinates), on screen.
   */
  function screenHandles(b:Rectangle):Array<Point>
    return [for (p in handlePoints(b.x, b.y, b.right, b.bottom)) toScreen(p.x, p.y)];

  static function handlePoints(x0:Float, y0:Float, x1:Float, y1:Float):Array<Point>
  {
    var mx = (x0 + x1) / 2, my = (y0 + y1) / 2;
    return [
      new Point(x0, y0), new Point(mx, y0), new Point(x1, y0), new Point(x1, my),
      new Point(x1, y1), new Point(mx, y1), new Point(x0, y1), new Point(x0, my)
    ];
  }

  /**
   * Bounds of the selected elements (in the edited symbol's coordinates).
   */
  public function selectionBounds():Null<Rectangle>
  {
    var r:Null<Rectangle> = null;
    for (s in selection)
    {
      var obj = hitObject(s);
      if (obj == null) continue;
      var b = obj.getBounds(contentHolder);
      b.x -= symOffsetX();
      b.y -= symOffsetY();
      r = r == null ? b : r.union(b);
    }
    return r;
  }

  function hitObject(s:AnimSel):Null<openfl.display.DisplayObject>
  {
    for (h in renderer.hits)
      if (h.layer == s.layer && h.element == s.element) return h.obj;
    return null;
  }

  //
  // Mouse
  //

  var drag:String = '';
  var cDragX:Float = 0;
  var cDragY:Float = 0;
  var lastMX:Float = 0;
  var lastMY:Float = 0;
  var cDragMoved:Bool = false;
  var dragOrig:Array<{sel:AnimSel, m:Matrix}> = [];
  var dragBounds:Null<Rectangle> = null;
  var dragHandle:Int = -1;
  var points:Array<AnimPoint> = [];
  var paintBitmap:Null<BitmapData> = null;
  var lastPaint:Null<Point> = null;
  var overCanvas:Bool = false;
  var lastClickTime:Float = 0;
  var spaceHand:Bool = false;

  function inWorkArea(mx:Float, my:Float):Bool
    return mx >= workLeft && mx < workRight && my >= QOLEditorState.MENUBAR_HEIGHT && my < workBottom;

  function handleMouse():Void
  {
    var pos = FlxG.mouse.getViewPosition(camUI);
    var mx = pos.x, my = pos.y;
    pos.put();
    lastMX = mx;
    lastMY = my;

    // Timeline gets the mouse first.
    if (drag == '' && (timeline.dragging || (timeline.contains(mx, my) && !mouseOverUI)))
    {
      overCanvas = false;
      timeline.handleMouse(mx, my);
      return;
    }

    var free = drag != '' || (inWorkArea(mx, my) && !mouseOverUI && !dialogOpen);
    overCanvas = free && drag == '' && inWorkArea(mx, my);
    if (!free) return;

    // Zoom & scroll.
    if (FlxG.mouse.wheel != 0 && drag == '')
    {
      var camLayer = currentLayer()?.kind == 'camera';
      if (ctrl() && FlxG.keys.pressed.SHIFT) rotateView(FlxG.mouse.wheel > 0 ? 15 : -15);
      else if (camLayer && !ctrl() && !FlxG.keys.pressed.ALT) zoomCamera(FlxG.mouse.wheel > 0 ? 1.1 : 1 / 1.1);
      else if (ctrl() || FlxG.keys.pressed.ALT) zoomAt(FlxG.mouse.wheel > 0 ? 1.15 : 1 / 1.15, mx, my);
      else if (FlxG.keys.pressed.SHIFT) viewX += FlxG.mouse.wheel * 40;
      else
        viewY += FlxG.mouse.wheel * 40;
    }

    // Panning: middle mouse, the hand tool, or space + drag.
    spaceHand = FlxG.keys.pressed.SPACE && !isTyping;
    if (drag == '' && (FlxG.mouse.justPressedMiddle || (FlxG.mouse.justPressed && (tool == 'hand' || spaceHand))))
    {
      drag = 'pan';
      cDragX = mx;
      cDragY = my;
      return;
    }
    if (drag == 'pan')
    {
      viewX += mx - cDragX;
      viewY += my - cDragY;
      cDragX = mx;
      cDragY = my;
      if (!FlxG.mouse.pressed && !FlxG.mouse.pressedMiddle) drag = '';
      return;
    }

    if (FlxG.mouse.justPressed && drag == '') mouseDown(mx, my);
    else if (drag != '' && FlxG.mouse.pressed) mouseMove(mx, my);
    else if (drag != '' && !FlxG.mouse.pressed) mouseUp(mx, my);
  }

  function currentLayer():Null<AnimLayer>
    return sym.layers[curLayer];

  /**
   * The keyframe drawing goes into (the layer is stretched to the playhead if it's too short). Null if the layer is
   * locked or hidden.
   */
  function drawKey(?forBitmap:Bool = false):Null<AnimKeyframe>
  {
    var layer = currentLayer();
    if (layer == null) return null;
    if (layer.locked)
    {
      setStatus('This layer is locked.');
      return null;
    }
    if (!layer.visible)
    {
      setStatus('This layer is hidden.');
      return null;
    }
    if (layer.kind == 'camera' || layer.kind == 'audio')
    {
      setStatus(layer.kind == 'camera' ? 'That\'s the camera layer: drag on the stage to move the camera, or pick another layer to draw on.' : 'Sound layers hold sounds, not drawings.');
      return null;
    }
    var key = AnimData.keyAt(layer, frame);
    if (key == null)
    {
      // Stretch the last keyframe out to the playhead.
      var last = layer.frames[layer.frames.length - 1];
      last.duration = frame - last.start + 1;
      key = last;
    }
    if (layer.kind == 'bitmap' && key.bitmap == null)
    {
      key.bitmap = doc.newCanvas();
      setCanvasPos(key);
    }
    return key;
  }

  /**
   * New canvases in symbols are centered on the symbol's origin (so they fill the stage while editing it).
   */
  function setCanvasPos(key:AnimKeyframe):Void
  {
    if (editPath.length > 0)
    {
      key.bx = -doc.project.width / 2;
      key.by = -doc.project.height / 2;
    }
  }

  var paintKey:Null<AnimKeyframe> = null;

  inline function canvasPoint(p:Point):Point
    return paintKey == null ? p : new Point(p.x - (paintKey.bx ?? 0), p.y - (paintKey.by ?? 0));

  function mouseDown(mx:Float, my:Float):Void
  {
    cDragX = mx;
    cDragY = my;
    cDragMoved = false;
    var local = toLocal(mx, my);
    var layer = currentLayer();
    var isBitmap = layer != null && layer.kind == 'bitmap';
    stop();
    if (layer != null && layer.kind == 'camera' && tool != 'hand' && tool != 'zoom')
    {
      beginCameraDrag(mx, my);
      return;
    }

    switch (tool)
    {
      case 'select':
        selectDown(mx, my, local);
      case 'brush' | 'pencil' | 'eraser':
        doc.checkpoint();
        var key = drawKey();
        if (key == null)
        {
          doc.dropCheckpoint();
          return;
        }
        if (isBitmap)
        {
          paintKey = key;
          paintBitmap = doc.editableBitmap(key);
          lastPaint = local;
          paintDab(local, local, true);
          renderDirty = true;
          drag = 'paint';
        }
        else
        {
          points = [{x: local.x, y: local.y, w: 1}];
          drag = tool == 'eraser' ? 'erase' : 'stroke';
          if (tool == 'eraser') eraseVectorAt(local);
        }
      case 'fill':
        bucket(local);
      case 'line' | 'rect' | 'oval' | 'poly':
        drag = 'shape';
      case 'text':
        addText(local);
      case 'picker':
        pickColor(mx, my, FlxG.keys.pressed.ALT);
      case 'zoom':
        zoomAt(FlxG.keys.pressed.ALT ? 0.8 : 1.25, mx, my);
      default:
    }
  }

  function mouseMove(mx:Float, my:Float):Void
  {
    if (Math.abs(mx - cDragX) + Math.abs(my - cDragY) > 2) cDragMoved = true;
    var local = toLocal(mx, my);
    switch (drag)
    {
      case 'move' | 'scale' | 'rotate':
        transformDrag(mx, my);
      case 'paint':
        if (lastPaint != null) paintDab(lastPaint, local, false);
        lastPaint = local;
      case 'stroke':
        var last = points[points.length - 1];
        var sc = screenScale();
        if ((last.x - local.x) * (last.x - local.x) + (last.y - local.y) * (last.y - local.y) >= 1 / (sc * sc))
        {
          points.push({x: local.x, y: local.y, w: 1});
          drawLiveStroke();
        }
      case 'erase':
        eraseVectorAt(local);
      case 'shape':
        drawLiveShape(toLocal(cDragX, cDragY), local);
      case 'campan' | 'camrotate':
        cameraDrag(mx, my);
      default:
    }
  }

  function mouseUp(mx:Float, my:Float):Void
  {
    var local = toLocal(mx, my);
    switch (drag)
    {
      case 'marquee':
        marqueeSelect(toLocal(cDragX, cDragY), local);
      case 'move' | 'scale' | 'rotate':
        if (cDragMoved) afterTimelineEdit();
      case 'paint':
        paintBitmap = null;
        paintKey = null;
        lastPaint = null;
        doc.changed();
      case 'stroke':
        finishStroke();
      case 'erase':
        doc.changed();
      case 'shape':
        finishShape(toLocal(cDragX, cDragY), local);
      case 'campan' | 'camrotate':
        camKey = null;
        if (cDragMoved) doc.changed();
        else
          doc.dropCheckpoint();
      default:
    }
    liveShape.graphics.clear();
    drag = '';
  }

  //
  // Camera
  //

  var camKey:Null<AnimKeyframe> = null;
  var camStart:Null<AnimCamera> = null;
  var camGrab:Null<Point> = null;
  var camAngle0:Float = 0;

  /**
   * The camera keyframe to change at the playhead (a tweened span gets a new keyframe here, like elements do).
   */
  function cameraKeyHere():Null<AnimKeyframe>
  {
    var layer = AnimData.cameraLayer(sym);
    if (layer == null || editPath.length > 0) return null;
    var cur = AnimData.copy(renderer.cameraAt(sym, frame) ?? AnimData.defaultCamera(doc.project));
    var key = AnimData.keyAt(layer, frame);
    if (key == null || (key.start != frame && key.tween != null))
    {
      var made = splitKeyAt(layer, frame, []);
      made.camera = cur;
      return made;
    }
    if (key.camera == null) key.camera = cur;
    return key;
  }

  function beginCameraDrag(mx:Float, my:Float):Void
  {
    if (editPath.length > 0) return;
    doc.checkpoint();
    camKey = cameraKeyHere();
    if (camKey == null)
    {
      doc.dropCheckpoint();
      return;
    }
    camStart = AnimData.copy(camKey.camera);
    var inv = stageMatrix();
    inv.invert();
    var stagePt = inv.transformPoint(new Point(mx, my));
    var camInv = renderer.matrixOf(camStart);
    camInv.invert();
    camGrab = cameraView ? camInv.transformPoint(stagePt) : stagePt;
    var mid = stageMatrix().transformPoint(new Point(doc.project.width / 2, doc.project.height / 2));
    camAngle0 = Math.atan2(my - mid.y, mx - mid.x);
    drag = FlxG.keys.pressed.SHIFT ? 'camrotate' : 'campan';
    renderDirty = true;
  }

  function cameraDrag(mx:Float, my:Float):Void
  {
    if (camKey == null || camStart == null || camGrab == null) return;
    var cam = camKey.camera;
    var inv = stageMatrix();
    inv.invert();
    var stagePt = inv.transformPoint(new Point(mx, my));
    if (drag == 'camrotate')
    {
      var mid = stageMatrix().transformPoint(new Point(doc.project.width / 2, doc.project.height / 2));
      var delta = (Math.atan2(my - mid.y, mx - mid.x) - camAngle0) * 180 / Math.PI;
      if (FlxG.keys.pressed.CONTROL) delta = Math.round(delta / 15) * 15;
      cam.rotation = camStart.rotation + (cameraView ? -delta : delta);
    }
    else if (cameraView)
    {
      // The picture follows the mouse: the camera moves the other way.
      var w = doc.project.width, h = doc.project.height;
      var dx = (stagePt.x - w / 2) / cam.zoom, dy = (stagePt.y - h / 2) / cam.zoom;
      var r = cam.rotation * Math.PI / 180;
      cam.x = camGrab.x - (dx * Math.cos(r) - dy * Math.sin(r));
      cam.y = camGrab.y - (dx * Math.sin(r) + dy * Math.cos(r));
    }
    else
    {
      // Looking past the camera: its frame follows the mouse.
      cam.x = camStart.x + stagePt.x - camGrab.x;
      cam.y = camStart.y + stagePt.y - camGrab.y;
    }
    renderDirty = true;
    dirty = true;
    propsForm?.refresh();
  }

  function zoomCamera(factor:Float):Void
  {
    editCamera(c -> c.zoom = Math.max(0.05, Math.min(20, c.zoom * factor)));
  }

  /**
   * Change the camera at the playhead (property edits made in one go undo together).
   */
  function editCamera(fn:AnimCamera->Void):Void
  {
    if (!editStarted)
    {
      doc.checkpoint();
      editStarted = true;
    }
    var key = cameraKeyHere();
    if (key == null) return;
    fn(key.camera);
    renderDirty = true;
    dirty = true;
    propsForm?.refresh();
  }

  /**
   * Add the camera layer (or select it).
   */
  public function addCamera():Void
  {
    if (editPath.length > 0)
    {
      alert('Camera', 'The camera belongs to the main timeline: go back to the Scene to add it.');
      return;
    }
    for (i in 0...sym.layers.length)
    {
      if (sym.layers[i].kind == 'camera')
      {
        selectLayer(i);
        return;
      }
    }
    doc.checkpoint();
    var layer = AnimData.newLayer('Camera', 'camera', 3);
    layer.color = 0xFFFFD84A;
    layer.frames[0].duration = AnimData.symbolLength(sym);
    layer.frames[0].camera = AnimData.defaultCamera(doc.project);
    sym.layers.insert(0, layer);
    curLayer = 0;
    cameraView = true;
    selection = [];
    doc.changed();
    notify('Camera added', 'Drag on the stage to move it, Shift + drag to turn it, the mouse wheel zooms it. Add keyframes and a tween to animate it.');
  }

  function buildCameraProps(form:QOLForm):Void
  {
    var cam = renderer.cameraAt(sym, frame) ?? AnimData.defaultCamera(doc.project);
    form.section('Camera at frame ${frame + 1}');
    form.number('X', () -> (renderer.cameraAt(sym, frame) ?? cam).x, v -> editCamera(c -> c.x = v), -100000, 100000, 1, 1);
    form.number('Y', () -> (renderer.cameraAt(sym, frame) ?? cam).y, v -> editCamera(c -> c.y = v), -100000, 100000, 1, 1);
    form.number('Zoom %', () -> (renderer.cameraAt(sym, frame) ?? cam).zoom * 100, v -> editCamera(c -> c.zoom = Math.max(0.05, v / 100)), 5, 2000, 5, 1);
    form.number('Rotation', () -> (renderer.cameraAt(sym, frame) ?? cam).rotation, v -> editCamera(c -> c.rotation = v), -3600, 3600, 1, 1);
    form.buttons([
      {
        text: 'Reset',
        cb: () -> {
          editStarted = false;
          editCamera(c -> {
            var d = AnimData.defaultCamera(doc.project);
            c.x = d.x;
            c.y = d.y;
            c.zoom = d.zoom;
            c.rotation = d.rotation;
          });
        }
      }
    ]);
    form.check('Show the stage through the camera', () -> cameraView, v -> {
      cameraView = v;
      renderDirty = true;
      updateViewBar();
    });
    form.note('Drag on the stage to move the camera, Shift + drag turns it, the mouse wheel zooms it. '
      + 'Add keyframes (F6) with a tween to animate it. Exports show what the camera sees.');
  }

  //
  // View bar (zoom, rotate, flip, fit, clip, camera, canvas color)
  //

  function buildViewBar():Void
  {
    viewBar = new HBox();
    viewBar.styleString = 'spacing: 3px;';
    function btn(icon:String, tip:String, cb:Void->Void):Button
    {
      var b = new Button();
      b.icon = AnimatorSkin.icon(icon, 14, 0xFFFFFFFF, true);
      b.tooltip = tip;
      b.width = 28;
      b.height = 24;
      b.addClass('anim-icon-button');
      b.onClick = _ -> cb();
      viewBar.addComponent(b);
      return b;
    }
    function textBtn(width:Int, tip:String, cb:Void->Void):Button
    {
      var b = new Button();
      b.width = width;
      b.height = 24;
      b.tooltip = tip;
      b.addClass('anim-icon-button');
      b.onClick = _ -> cb();
      viewBar.addComponent(b);
      return b;
    }
    btn('zoom-out', 'Zoom out (Ctrl + wheel)', () -> zoomAt(1 / 1.25, centerX(), centerY()));
    zoomLabel = textBtn(54, 'Zoom: click for 100%', () -> keepPointWhile(centerX(), centerY(), () -> zoom = 1));
    btn('zoom-in', 'Zoom in (Ctrl + wheel)', () -> zoomAt(1.25, centerX(), centerY()));
    btn('rotate-left', 'Turn the view left (Ctrl + Shift + wheel)', () -> rotateView(-15));
    rotLabel = textBtn(46, 'View angle: click to straighten', () -> rotateView(0, true));
    btn('rotate-right', 'Turn the view right (Ctrl + Shift + wheel)', () -> rotateView(15));
    flipButton = btn('flip', 'Mirror the view (checks your drawing; doesn\'t change it)', () -> {
      flipView();
      updateViewBar();
    });
    btn('fit', 'Fit the stage in the window (Ctrl + 0)', () -> {
      viewRotation = 0;
      viewFlip = false;
      fitView();
      updateViewBar();
    });
    clipButton = btn('clip', 'Hide everything outside the stage', () -> {
      clipStage = !clipStage;
      renderDirty = true;
      updateViewBar();
    });
    camViewButton = btn('camera', 'Camera: add one, or switch between the camera\'s view and the whole drawing', () -> {
      if (AnimData.cameraLayer(sym) == null || editPath.length > 0) addCamera();
      else
        cameraView = !cameraView;
      renderDirty = true;
      decorKey = '';
      propsForm?.refresh();
      updateViewBar();
    });
    canvasButton = textBtn(84, 'Canvas color', openCanvasColorDialog);
    canvasButton.text = 'Canvas';
    root.addComponent(viewBar);
    updateViewBar();
  }

  var viewBarState:String = '';

  function updateViewBar():Void
  {
    if (viewBar == null) return;
    var z = '${Math.round(zoom * 100)}%';
    var r = '${Math.round(viewRotation)}\u00B0';
    var hasCam = AnimData.cameraLayer(doc.main) != null;
    var state = '$z|$r|$viewFlip|$clipStage|$cameraView|$hasCam|${doc.project.bg}';
    if (state == viewBarState) return;
    viewBarState = state;
    zoomLabel.text = z;
    rotLabel.text = r;
    toggleClass(flipButton, viewFlip);
    toggleClass(clipButton, clipStage);
    toggleClass(camViewButton, hasCam && cameraView);
    canvasButton.icon = canvasSwatch(doc.project.bg);
  }

  static function toggleClass(b:Button, on:Bool):Void
  {
    if (on) b.addClass('anim-on');
    else
      b.removeClass('anim-on');
  }

  static function canvasSwatch(bg:Int):flixel.graphics.frames.FlxFrame
  {
    var key = 'qol-anim-canvas-swatch-${StringTools.hex(bg, 8)}';
    return QOLTheme.cached(key, () -> {
      var b = new BitmapData(16, 16, true, 0);
      if ((bg >>> 24) == 0)
      {
        b.fillRect(new Rectangle(1, 1, 14, 14), 0xFFFFFFFF);
        b.fillRect(new Rectangle(1, 1, 7, 7), 0xFFC8C8D0);
        b.fillRect(new Rectangle(8, 8, 7, 7), 0xFFC8C8D0);
      }
      else
        b.fillRect(new Rectangle(1, 1, 14, 14), bg | 0xFF000000);
      // Outline.
      for (i in 0...16)
      {
        b.setPixel32(i, 0, 0xFF1A1030);
        b.setPixel32(i, 15, 0xFF1A1030);
        b.setPixel32(0, i, 0xFF1A1030);
        b.setPixel32(15, i, 0xFF1A1030);
      }
      return b;
    }).imageFrame.frame;
  }

  public static final CANVAS_PRESETS:Array<{name:String, color:Int}> = [
    {name: 'Transparent', color: 0x00FFFFFF},
    {name: 'White', color: 0xFFFFFFFF},
    {name: 'Paper', color: 0xFFF4EBDD},
    {name: 'Light gray', color: 0xFFC8C8CC},
    {name: 'Dark', color: 0xFF26232E},
    {name: 'Black', color: 0xFF000000},
    {name: 'Green screen', color: 0xFF00B140},
    {name: 'Blue screen', color: 0xFF0047BB},
    {name: 'Sky', color: 0xFF8FD3FF},
    {name: 'Week 1 stage', color: 0xFF2A2440}
  ];

  function setCanvasColor(c:Int):Void
  {
    if (c == doc.project.bg) return;
    doc.checkpoint();
    doc.project.bg = c;
    renderDirty = true;
    dirty = true;
    docForm.refresh();
    updateViewBar();
  }

  function openCanvasColorDialog():Void
  {
    var dialog = themePopup(new haxe.ui.containers.dialogs.Dialog());
    dialog.title = 'Canvas Color';
    dialog.buttons = DialogButton.OK;
    dialog.destroyOnClose = true;
    var box = new VBox();
    box.styleString = 'spacing: 8px;';
    var grid = new VBox();
    grid.styleString = 'spacing: 4px;';
    var row:Null<HBox> = null;
    var form = new QOLForm(110, 150);
    for (i in 0...CANVAS_PRESETS.length)
    {
      var p = CANVAS_PRESETS[i];
      if (i % 2 == 0)
      {
        row = new HBox();
        row.styleString = 'spacing: 4px;';
        grid.addComponent(row);
      }
      var b = new Button();
      b.text = p.name;
      b.icon = canvasSwatch(p.color);
      b.width = 150;
      b.height = 26;
      b.styleString = 'text-align: left;';
      b.onClick = _ -> {
        setCanvasColor(p.color);
        form.refresh();
      };
      row.addComponent(b);
    }
    box.addComponent(grid);
    form.section('Any color');
    form.colorField('Color', () -> doc.project.bg | 0xFF000000, v -> setCanvasColor((v & 0xFFFFFF) | 0xFF000000));
    form.check('Transparent', () -> (doc.project.bg >>> 24) == 0, v -> setCanvasColor(v ? (doc.project.bg & 0xFFFFFF) : (doc.project.bg | 0xFF000000)));
    form.note('The canvas color is saved with the animation and used by exports (transparent keeps exports see-through).');
    box.addComponent(form);
    dialog.addComponent(box);
    dialog.showDialog(true);
  }

  //
  // Select / transform
  //

  function selectDown(mx:Float, my:Float, local:Point):Void
  {
    // Transform handles first.
    var b = selectionBounds();
    if (b != null)
    {
      var hs = screenHandles(b);
      for (i in 0...hs.length)
      {
        if (Math.abs(mx - hs[i].x) <= 6 && Math.abs(my - hs[i].y) <= 6)
        {
          beginTransform('scale', b, i);
          return;
        }
      }
      // Just outside a corner rotates.
      for (i in [0, 2, 4, 6])
      {
        var d = Math.sqrt((mx - hs[i].x) * (mx - hs[i].x) + (my - hs[i].y) * (my - hs[i].y));
        if (d > 6 && d < 22 && !b.contains(local.x, local.y))
        {
          beginTransform('rotate', b, i);
          return;
        }
      }
    }

    var hit = hitTest();
    if (hit != null)
    {
      var now = haxe.Timer.stamp();
      var key = AnimData.keyAt(sym.layers[hit.layer], frame);
      var el = key?.elements[hit.element];
      if (now - lastClickTime < 0.35 && el != null && el.type == 'symbol' && el.symbol != null)
      {
        enterSymbol(el.symbol);
        return;
      }
      lastClickTime = now;
      if (FlxG.keys.pressed.SHIFT)
      {
        var existing = Lambda.find(selection, s -> s.layer == hit.layer && s.element == hit.element);
        if (existing != null) selection.remove(existing);
        else
          selection.push(hit);
      }
      else if (Lambda.find(selection, s -> s.layer == hit.layer && s.element == hit.element) == null)
      {
        selection = [hit];
      }
      curLayer = hit.layer;
      refreshProps();
      beginTransform('move', selectionBounds(), -1);
      return;
    }
    if (!FlxG.keys.pressed.SHIFT) selection = [];
    refreshProps();
    drag = 'marquee';
  }

  function hitTest():Null<AnimSel>
  {
    var stageX = FlxG.stage.mouseX, stageY = FlxG.stage.mouseY;
    var i = renderer.hits.length - 1;
    // Hits are bottom layer first; walk from the top.
    var best:Null<AnimSel> = null;
    var hits = renderer.hits.copy();
    hits.reverse();
    for (h in hits)
    {
      var layer = sym.layers[h.layer];
      if (layer == null || layer.locked || !layer.visible) continue;
      if (h.obj.hitTestPoint(stageX, stageY, true)) return {layer: h.layer, element: h.element};
    }
    return best;
  }

  function beginTransform(mode:String, bounds:Null<Rectangle>, handle:Int):Void
  {
    drag = mode;
    dragBounds = bounds;
    dragHandle = handle;
    transformCheckpointed = false;
    dragOrig = [];
    for (s in selection)
    {
      var el = elementOf(s);
      if (el != null) dragOrig.push({sel: s, m: AnimGeom.matrixOf(el)});
    }
    cDragMoved = false;
  }

  function elementOf(s:Null<AnimSel>):Null<AnimElement>
  {
    // Property fields can still ask for the selection right after it was cleared.
    if (s == null || s.layer < 0 || s.layer >= sym.layers.length) return null;
    var layer = sym.layers[s.layer];
    if (layer == null) return null;
    var key = AnimData.keyAt(layer, frame);
    return key == null ? null : key.elements[s.element];
  }

  var transformCheckpointed:Bool = false;

  function transformDrag(mx:Float, my:Float):Void
  {
    if (!cDragMoved || dragOrig.length == 0 || dragBounds == null) return;
    if (!transformCheckpointed)
    {
      doc.checkpoint();
      transformCheckpointed = true;
      // Editing between keyframes of a tween adds a keyframe here (like Animate does).
      autoKeyframes();
      // A new keyframe may have been made: start from its (tweened) state.
      dragOrig = [for (o in dragOrig) {sel: o.sel, m: elementOf(o.sel) != null ? AnimGeom.matrixOf(elementOf(o.sel)) : o.m}];
    }
    var a = toLocal(cDragX, cDragY);
    var b = toLocal(mx, my);
    var t = new Matrix();
    var bb = dragBounds;
    switch (drag)
    {
      case 'move':
        var dx = b.x - a.x, dy = b.y - a.y;
        if (FlxG.keys.pressed.SHIFT)
        {
          if (Math.abs(dx) > Math.abs(dy)) dy = 0;
          else
            dx = 0;
        }
        t.translate(dx, dy);
      case 'scale':
        // Opposite handle stays put (Alt scales from the center).
        var hx = [bb.x, bb.x + bb.width / 2, bb.right, bb.right, bb.right, bb.x + bb.width / 2, bb.x, bb.x][dragHandle];
        var hy = [bb.y, bb.y, bb.y, bb.y + bb.height / 2, bb.bottom, bb.bottom, bb.bottom, bb.y + bb.height / 2][dragHandle];
        var ax = FlxG.keys.pressed.ALT ? bb.x + bb.width / 2 : bb.x + bb.right - hx;
        var ay = FlxG.keys.pressed.ALT ? bb.y + bb.height / 2 : bb.y + bb.bottom - hy;
        var sx = (hx - ax) == 0 ? 1 : (b.x - ax) / (hx - ax);
        var sy = (hy - ay) == 0 ? 1 : (b.y - ay) / (hy - ay);
        if (dragHandle == 1 || dragHandle == 5) sx = 1;
        if (dragHandle == 3 || dragHandle == 7) sy = 1;
        if (FlxG.keys.pressed.SHIFT && dragHandle % 2 == 0)
        {
          var s = Math.max(Math.abs(sx), Math.abs(sy));
          sx = s * (sx < 0 ? -1 : 1);
          sy = s * (sy < 0 ? -1 : 1);
        }
        if (Math.abs(sx) < 0.01) sx = 0.01;
        if (Math.abs(sy) < 0.01) sy = 0.01;
        t.translate(-ax, -ay);
        t.scale(sx, sy);
        t.translate(ax, ay);
      case 'rotate':
        var cx = bb.x + bb.width / 2, cy = bb.y + bb.height / 2;
        var a0 = Math.atan2(a.y - cy, a.x - cx);
        var a1 = Math.atan2(b.y - cy, b.x - cx);
        var ang = a1 - a0;
        if (FlxG.keys.pressed.SHIFT) ang = Math.round(ang / (Math.PI / 12)) * (Math.PI / 12);
        t.translate(-cx, -cy);
        t.rotate(ang);
        t.translate(cx, cy);
    }
    for (o in dragOrig)
    {
      var el = elementOf(o.sel);
      if (el == null) continue;
      var m = o.m.clone();
      m.concat(t);
      AnimGeom.setMatrix(el, m);
    }
    renderDirty = true;
    dirty = true;
  }

  /**
   * If the playhead is inside a tweened span (not on its keyframe), add a keyframe here holding the tweened state.
   */
  function autoKeyframes():Void
  {
    var layers = new Map<Int, Bool>();
    for (s in selection)
      layers.set(s.layer, true);
    for (li in layers.keys())
    {
      var layer = sym.layers[li];
      var key = AnimData.keyAt(layer, frame);
      if (key == null || key.start == frame || key.tween == null) continue;
      var tweened = renderer.tweenedElements(layer, key, frame);
      splitKeyAt(layer, frame, AnimData.copy(tweened));
    }
  }

  /**
   * Split the keyframe covering `f` so a new keyframe starts at `f` (with the given elements).
   */
  function splitKeyAt(layer:AnimLayer, f:Int, elements:Array<AnimElement>, ?bitmap:String):AnimKeyframe
  {
    var key = AnimData.keyAt(layer, f);
    if (key == null)
    {
      var last = layer.frames[layer.frames.length - 1];
      var end = last.start + last.duration;
      if (f > end) last.duration = f - last.start;
      var nk:AnimKeyframe = {start: f, duration: 1, elements: elements};
      if (bitmap != null) nk.bitmap = bitmap;
      layer.frames.push(nk);
      return nk;
    }
    if (key.start == f)
    {
      key.elements = elements;
      if (bitmap != null) key.bitmap = bitmap;
      return key;
    }
    var end = key.start + key.duration;
    key.duration = f - key.start;
    var nk:AnimKeyframe = {start: f, duration: end - f, elements: elements};
    if (key.tween != null) nk.tween = AnimData.copy(key.tween);
    if (bitmap != null) nk.bitmap = bitmap;
    layer.frames.insert(layer.frames.indexOf(key) + 1, nk);
    return nk;
  }

  function marqueeSelect(a:Point, b:Point):Void
  {
    var r = new Rectangle(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y));
    if (r.width < 2 && r.height < 2) return;
    for (h in renderer.hits)
    {
      var layer = sym.layers[h.layer];
      if (layer == null || layer.locked || !layer.visible) continue;
      var bb = h.obj.getBounds(contentHolder);
      bb.x -= symOffsetX();
      bb.y -= symOffsetY();
      if (r.intersects(bb) && Lambda.find(selection, s -> s.layer == h.layer && s.element == h.element) == null)
        selection.push({layer: h.layer, element: h.element});
    }
    if (selection.length > 0) curLayer = selection[0].layer;
    refreshProps();
  }

  function transformSelection(fn:Matrix->Void):Void
  {
    var b = selectionBounds();
    if (b == null) return;
    doc.checkpoint();
    var cx = b.x + b.width / 2, cy = b.y + b.height / 2;
    var t = new Matrix();
    t.translate(-cx, -cy);
    fn(t);
    t.translate(cx, cy);
    for (s in selection)
    {
      var el = elementOf(s);
      if (el == null) continue;
      var m = AnimGeom.matrixOf(el);
      m.concat(t);
      AnimGeom.setMatrix(el, m);
    }
    doc.changed();
  }

  function nudge(dx:Float, dy:Float):Void
  {
    if (selection.length == 0) return;
    doc.checkpoint();
    autoKeyframes();
    for (s in selection)
    {
      var el = elementOf(s);
      if (el == null) continue;
      el.tx += dx;
      el.ty += dy;
    }
    doc.changed();
  }

  function arrange(delta:Int):Void
  {
    if (selection.length != 1) return;
    var s = selection[0];
    var key = AnimData.keyAt(sym.layers[s.layer], frame);
    if (key == null) return;
    doc.checkpoint();
    var el = key.elements[s.element];
    key.elements.remove(el);
    var idx = Std.int(Math.max(0, Math.min(key.elements.length, s.element + delta)));
    key.elements.insert(idx, el);
    s.element = idx;
    doc.changed();
  }

  //
  // Drawing
  //

  static inline final MAX_CANVAS:Int = 8192;

  var warnedCanvasSize:Bool = false;

  /**
   * Paint layers grow when you draw past their edge (so you can draw outside the stage).
   */
  function growCanvasFor(a:Point, b:Point, r:Float):Void
  {
    if (paintBitmap == null || paintKey == null) return;
    var bx = paintKey.bx ?? 0, by = paintKey.by ?? 0;
    var minX = Math.min(a.x, b.x) - r - bx, minY = Math.min(a.y, b.y) - r - by;
    var maxX = Math.max(a.x, b.x) + r - bx, maxY = Math.max(a.y, b.y) + r - by;
    var w = paintBitmap.width, h = paintBitmap.height;
    if (minX >= 0 && minY >= 0 && maxX <= w && maxY <= h) return;
    var pad = 256;
    var x0 = minX < 0 ? Math.floor(minX) - pad : 0.0;
    var y0 = minY < 0 ? Math.floor(minY) - pad : 0.0;
    var x1 = maxX > w ? Math.ceil(maxX) + pad : w;
    var y1 = maxY > h ? Math.ceil(maxY) + pad : h;
    var nw = Std.int(x1 - x0), nh = Std.int(y1 - y0);
    if (nw > MAX_CANVAS || nh > MAX_CANVAS)
    {
      if (!warnedCanvasSize) setStatus('This paint layer is as big as it can get ($MAX_CANVAS px).');
      warnedCanvasSize = true;
      return;
    }
    var grown = new BitmapData(nw, nh, true, 0);
    grown.copyPixels(paintBitmap, paintBitmap.rect, new Point(-x0, -y0));
    // The old canvas was this stroke's own copy (see editableBitmap), so nothing else uses it.
    var old = paintBitmap;
    doc.replaceBitmap(paintKey.bitmap, grown);
    old.dispose();
    paintKey.bx = bx + x0;
    paintKey.by = by + y0;
    paintBitmap = grown;
    renderDirty = true;
  }

  function paintDab(from:Point, to:Point, first:Bool):Void
  {
    if (paintBitmap == null) return;
    if (tool != 'eraser') growCanvasFor(from, to, toolSize() / 2 + 2);
    from = canvasPoint(from);
    to = canvasPoint(to);
    // Bitmap canvases sit at the symbol's origin.
    switch (tool)
    {
      case 'pencil':
        if (pixelPencil) AnimPaint.pixelLine(paintBitmap, from.x, from.y, to.x, to.y, Std.int(Math.max(1, pencilSize)), strokeColor, false);
        else
          AnimPaint.strokeLine(paintBitmap, from.x, from.y, to.x, to.y, pencilSize, strokeColor, opacity, 1, false, !first);
      case 'eraser':
        if (pixelPencil) AnimPaint.pixelLine(paintBitmap, from.x, from.y, to.x, to.y, Std.int(Math.max(1, eraserSize)), 0, true);
        else
          AnimPaint.strokeLine(paintBitmap, from.x, from.y, to.x, to.y, eraserSize, 0, 1, hardness, true, !first);
      default:
        AnimPaint.strokeLine(paintBitmap, from.x, from.y, to.x, to.y, brushSize, fillColor, opacity, hardness, false, !first);
    }
  }

  function drawLiveStroke():Void
  {
    var g = liveShape.graphics;
    g.clear();
    if (points.length < 2) return;
    var color = tool == 'brush' ? fillColor : strokeColor;
    var w = tool == 'brush' ? brushSize : pencilSize;
    liveShape.x = symOffsetX();
    liveShape.y = symOffsetY();
    g.lineStyle(w, color & 0xFFFFFF, tool == 'brush' ? opacity : 1, false, NORMAL, ROUND, ROUND);
    g.moveTo(points[0].x, points[0].y);
    for (i in 1...points.length)
      g.lineTo(points[i].x, points[i].y);
  }

  function finishStroke():Void
  {
    var key = drawKey();
    if (key == null || points.length == 0)
    {
      points = [];
      return;
    }
    var pts = AnimGeom.thin(points, 1.2 / screenScale());
    pts = AnimGeom.smooth(pts, smoothing);
    var path:AnimPath;
    if (tool == 'brush')
    {
      if (taper && pts.length > 4)
      {
        var n = pts.length;
        var ramp = Std.int(Math.max(2, n * 0.18));
        for (i in 0...n)
        {
          var a = i < ramp ? 0.25 + 0.75 * i / ramp : 1.0;
          var b = i > n - 1 - ramp ? 0.25 + 0.75 * (n - 1 - i) / ramp : 1.0;
          pts[i].w = Math.min(a, b);
        }
      }
      var alpha = Std.int(Math.round(opacity * 255)) << 24;
      path = {fill: (fillColor & 0xFFFFFF) | alpha, d: AnimGeom.brushOutline(pts, brushSize)};
    }
    else
    {
      path = {stroke: strokeColor | 0xFF000000, width: pencilSize, d: AnimGeom.curveThrough(pts)};
    }
    var el = AnimData.identity('shape');
    el.paths = [path];
    key.elements.push(el);
    points = [];
    doc.changed();
  }

  function eraseVectorAt(local:Point):Void
  {
    var key = AnimData.keyAt(currentLayer(), frame);
    if (key == null) return;
    var r = eraserSize / 2;
    var changed = false;
    var i = key.elements.length - 1;
    while (i >= 0)
    {
      var el = key.elements[i];
      if (el.type == 'shape' && el.paths != null)
      {
        var inv = AnimGeom.matrixOf(el);
        inv.invert();
        var p = inv.transformPoint(local);
        var j = el.paths.length - 1;
        while (j >= 0)
        {
          var path = el.paths[j];
          var hit = AnimGeom.distanceToPath(path, p.x, p.y) <= r + (path.width ?? 0) / 2;
          if (!hit && path.fill != null) hit = AnimGeom.pathContains(path, p.x, p.y);
          if (hit)
          {
            el.paths.splice(j, 1);
            changed = true;
          }
          j--;
        }
        if (el.paths.length == 0) key.elements.splice(i, 1);
      }
      i--;
    }
    if (changed)
    {
      selection = [];
      renderDirty = true;
      dirty = true;
    }
  }

  function shapePath(a:Point, b:Point):Array<Float>
  {
    var x0 = a.x, y0 = a.y, x1 = b.x, y1 = b.y;
    var shift = FlxG.keys.pressed.SHIFT;
    if (shift && tool != 'line')
    {
      var s = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0));
      x1 = x0 + s * (x1 < x0 ? -1 : 1);
      y1 = y0 + s * (y1 < y0 ? -1 : 1);
    }
    return switch (tool)
    {
      case 'line':
        if (shift)
        {
          var ang = Math.round(Math.atan2(y1 - y0, x1 - x0) / (Math.PI / 4)) * (Math.PI / 4);
          var len = Math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
          x1 = x0 + Math.cos(ang) * len;
          y1 = y0 + Math.sin(ang) * len;
        }
        [0, x0, y0, 1, x1, y1];
      case 'rect': AnimGeom.rectPath(x0, y0, x1 - x0, y1 - y0, cornerRadius);
      case 'oval': AnimGeom.ellipsePath(Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0));
      default:
        var r = Math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
        AnimGeom.polygonPath(x0, y0, r, polySides, polyStar, Math.atan2(y1 - y0, x1 - x0) * 180 / Math.PI);
    }
  }

  function shapeDef(a:Point, b:Point):AnimPath
  {
    var d = shapePath(a, b);
    if (tool == 'line') return {stroke: strokeColor | 0xFF000000, width: shapeStroke, d: d};
    var p:AnimPath = {d: d};
    if (fillOn) p.fill = fillColor | 0xFF000000;
    if (strokeOn && shapeStroke > 0)
    {
      p.stroke = strokeColor | 0xFF000000;
      p.width = shapeStroke;
    }
    if (p.fill == null && p.stroke == null)
    {
      p.stroke = strokeColor | 0xFF000000;
      p.width = Math.max(1, shapeStroke);
    }
    return p;
  }

  function drawLiveShape(a:Point, b:Point):Void
  {
    var g = liveShape.graphics;
    g.clear();
    liveShape.x = symOffsetX();
    liveShape.y = symOffsetY();
    AnimGeom.drawPath(g, shapeDef(a, b));
  }

  function finishShape(a:Point, b:Point):Void
  {
    if (Math.abs(b.x - a.x) < 1 && Math.abs(b.y - a.y) < 1) return;
    doc.checkpoint();
    var key = drawKey();
    if (key == null)
    {
      doc.dropCheckpoint();
      return;
    }
    var path = shapeDef(a, b);
    if (currentLayer().kind == 'bitmap')
    {
      paintKey = key;
      paintBitmap = doc.editableBitmap(key);
      var pb = AnimGeom.pathBounds(path);
      growCanvasFor(new Point(pb.x, pb.y), new Point(pb.right, pb.bottom), (path.width ?? 0) + 2);
      var bmp = paintBitmap;
      paintKey = null;
      paintBitmap = null;
      var s = new Shape();
      AnimGeom.drawPath(s.graphics, path);
      s.x = -(key.bx ?? 0);
      s.y = -(key.by ?? 0);
      var holder = new Sprite();
      holder.addChild(s);
      AnimPaint.drawShape(bmp, holder);
    }
    else
    {
      var el = AnimData.identity('shape');
      el.paths = [path];
      key.elements.push(el);
    }
    doc.changed();
  }

  function addText(local:Point):Void
  {
    var layer = currentLayer();
    if (layer == null || layer.kind == 'bitmap')
    {
      setStatus('Text goes on vector layers.');
      return;
    }
    prompt('Text', 'What should it say?', '', text -> {
      if (text == null || text == '') return;
      doc.checkpoint();
      var key = drawKey();
      if (key == null) return;
      var el = AnimData.identity('text');
      el.text = text;
      el.size = textSize;
      el.color = fillColor | 0xFF000000;
      el.font = '_sans';
      el.tx = local.x;
      el.ty = local.y;
      key.elements.push(el);
      doc.changed();
    });
  }

  function bucket(local:Point):Void
  {
    var layer = currentLayer();
    if (layer == null) return;
    if (layer.kind == 'bitmap')
    {
      doc.checkpoint();
      var key = drawKey();
      if (key == null)
      {
        doc.dropCheckpoint();
        return;
      }
      var bmp = doc.editableBitmap(key);
      var cx = local.x - (key.bx ?? 0), cy = local.y - (key.by ?? 0);
      if (!AnimPaint.floodFill(bmp, Std.int(cx), Std.int(cy), fillColor, fillTolerance, fillGap))
      {
        doc.dropCheckpoint();
        return;
      }
      doc.changed();
      return;
    }

    var key = AnimData.keyAt(layer, frame);
    // Clicking an existing fill recolors it.
    if (key != null)
    {
      var i = key.elements.length - 1;
      while (i >= 0)
      {
        var el = key.elements[i];
        i--;
        if (el.type != 'shape' || el.paths == null) continue;
        var inv = AnimGeom.matrixOf(el);
        inv.invert();
        var p = inv.transformPoint(local);
        for (path in el.paths)
        {
          if (path.fill != null && AnimGeom.pathContains(path, p.x, p.y))
          {
            doc.checkpoint();
            path.fill = fillColor | 0xFF000000;
            doc.changed();
            return;
          }
        }
      }
    }

    // Otherwise fill the closed area around the click with a new vector shape.
    var w = doc.project.width, h = doc.project.height;
    var res = w * h > 1500000 ? 0.5 : 1.0;
    var bw = Std.int(Math.max(1, w * res)), bh = Std.int(Math.max(1, h * res));
    var bmp = new BitmapData(bw, bh, true, 0);
    if (key != null)
    {
      var m = new Matrix();
      m.scale(res, res);
      m.translate(symOffsetX() * res, symOffsetY() * res);
      for (el in key.elements)
      {
        var obj = renderer.elementObject(el, frame - key.start, {}, 0, false, 0);
        if (obj == null) continue;
        var holder = new Sprite();
        holder.addChild(obj);
        bmp.draw(holder, m, null, null, null, true);
      }
    }
    var cx = Std.int((local.x + symOffsetX()) * res), cy = Std.int((local.y + symOffsetY()) * res);
    if (cx < 0 || cy < 0 || cx >= bw || cy >= bh)
    {
      setStatus('Click inside the stage to fill.');
      return;
    }
    var mask = AnimPaint.fillMask(bmp, cx, cy, fillTolerance);
    bmp.dispose();
    if (mask == null) return;
    // Open areas leak to the edge of the stage: refuse those.
    for (x in 0...bw)
      if (mask.get(x) != 0 || mask.get((bh - 1) * bw + x) != 0)
      {
        notify('Not a closed area', 'The paint bucket only fills areas closed by lines. Close the gap, or use a bitmap layer.');
        return;
      }
    mask = AnimPaint.grow(mask, bw, bh, Std.int(Math.max(1, fillGap + 1)));
    var loops = AnimGeom.traceMask(mask, bw, bh);
    if (loops.length == 0) return;
    var d:Array<Float> = [];
    for (loop in loops)
    {
      var simple = AnimGeom.simplify(loop, 0.9);
      var smooth = AnimGeom.smoothClosed(simple, 1 / res, -symOffsetX(), -symOffsetY());
      for (v in smooth)
        d.push(v);
    }
    doc.checkpoint();
    var target = drawKey();
    if (target == null)
    {
      doc.dropCheckpoint();
      return;
    }
    var el = AnimData.identity('shape');
    el.paths = [{fill: fillColor | 0xFF000000, d: d}];
    // Fills go under the lines.
    target.elements.insert(0, el);
    selection = [];
    doc.changed();
  }

  function pickColor(mx:Float, my:Float, toStroke:Bool):Void
  {
    var local = toLocal(mx, my);
    var bmp = new BitmapData(1, 1, true, 0);
    var m = new Matrix();
    m.translate(-(local.x + symOffsetX()), -(local.y + symOffsetY()));
    bmp.draw(contentHolder, m);
    var c = bmp.getPixel32(0, 0);
    bmp.dispose();
    if (((c >>> 24) & 0xFF) == 0)
    {
      setStatus('Nothing there to pick.');
      return;
    }
    if (toStroke) strokeColor = c | 0xFF000000;
    else
      fillColor = c | 0xFF000000;
    colorForm.refresh();
    setStatus('Picked #${StringTools.hex(c & 0xFFFFFF, 6)} for the ${toStroke ? 'stroke' : 'fill'}.');
  }

  //
  // Selection actions
  //

  function copySelection():Void
  {
    var els = [for (s in selection) elementOf(s)].filter(e -> e != null);
    if (els.length == 0) return;
    clipboard = haxe.Json.stringify(els);
    setStatus('Copied ${els.length} item(s).');
  }

  function pasteSelection():Void
  {
    if (clipboard == null) return;
    var layer = currentLayer();
    if (layer == null || layer.kind == 'bitmap') return;
    doc.checkpoint();
    var key = drawKey();
    if (key == null)
    {
      doc.dropCheckpoint();
      return;
    }
    var els:Array<AnimElement> = haxe.Json.parse(clipboard);
    selection = [];
    for (el in els)
    {
      el.tx += 10;
      el.ty += 10;
      key.elements.push(el);
      selection.push({layer: curLayer, element: key.elements.length - 1});
    }
    clipboard = haxe.Json.stringify(els);
    setTool('select');
    doc.changed();
  }

  function deleteSelection():Void
  {
    if (selection.length == 0) return;
    doc.checkpoint();
    // Remove from the end so indexes stay valid.
    var sorted = selection.copy();
    sorted.sort((a, b) -> a.layer == b.layer ? b.element - a.element : a.layer - b.layer);
    for (s in sorted)
    {
      var key = AnimData.keyAt(sym.layers[s.layer], frame);
      if (key != null && s.element < key.elements.length) key.elements.splice(s.element, 1);
    }
    selection = [];
    doc.changed();
  }

  function selectAll():Void
  {
    selection = [];
    for (li in 0...sym.layers.length)
    {
      var layer = sym.layers[li];
      if (layer.locked || !layer.visible) continue;
      var key = AnimData.keyAt(layer, frame);
      if (key == null) continue;
      for (ei in 0...key.elements.length)
        selection.push({layer: li, element: ei});
    }
    setTool('select');
    refreshProps();
  }

  /**
   * Turn the selected items into a new symbol (F8), leaving an instance of it in their place.
   */
  function convertToSymbol():Void
  {
    if (selection.length == 0)
    {
      notify('Nothing selected', 'Select some shapes or objects first (Select tool, V).');
      return;
    }
    var b = selectionBounds();
    prompt('Convert to Symbol', 'Symbol name', 'Symbol ${doc.project.symbols.length}', name -> {
      if (name == null || name == '' || selection.length == 0) return;
      doc.checkpoint();
      var layerIdx = selection[0].layer;
      var key = AnimData.keyAt(sym.layers[layerIdx], frame);
      if (key == null) return;
      var picked = [for (s in selection) if (s.layer == layerIdx) s.element];
      picked.sort((a, b) -> a - b);
      var els = [for (i in picked) key.elements[i]];
      // Registration point: the middle of the selection.
      var cx = b != null ? b.x + b.width / 2 : 0, cy = b != null ? b.y + b.height / 2 : 0;
      var symbol = AnimData.newSymbol(AnimData.makeId('sym'), name);
      for (el in els)
      {
        el.tx -= cx;
        el.ty -= cy;
        symbol.layers[0].frames[0].elements.push(el);
      }
      doc.project.symbols.push(symbol);
      var i = picked.length - 1;
      while (i >= 0)
        key.elements.splice(picked[i--], 1);
      var inst = AnimData.identity('symbol');
      inst.symbol = symbol.id;
      inst.loop = 'loop';
      inst.firstFrame = 0;
      inst.tx = cx;
      inst.ty = cy;
      var at = picked.length > 0 ? picked[0] : key.elements.length;
      key.elements.insert(at, inst);
      selection = [{layer: layerIdx, element: at}];
      doc.changed();
      notify('Symbol made', '"$name" is in the Library. Double-click it on the stage to edit its own timeline.');
    });
  }

  /**
   * Replace a symbol instance with what it shows (Ctrl+B).
   */
  function breakApart():Void
  {
    if (selection.length != 1) return;
    var s = selection[0];
    var key = AnimData.keyAt(sym.layers[s.layer], frame);
    var el = key?.elements[s.element];
    if (el == null || el.type != 'symbol') return;
    var child = doc.symbol(el.symbol);
    if (child == null) return;
    doc.checkpoint();
    var m = AnimGeom.matrixOf(el);
    var out:Array<AnimElement> = [];
    var f = el.firstFrame ?? 0;
    var i = child.layers.length - 1;
    while (i >= 0)
    {
      var l = child.layers[i--];
      var k = AnimData.keyAt(l, f);
      if (k == null) continue;
      for (ce in renderer.tweenedElements(l, k, f))
      {
        var copy = AnimData.copy(ce);
        var cm = AnimGeom.matrixOf(copy);
        cm.concat(m);
        AnimGeom.setMatrix(copy, cm);
        out.push(copy);
      }
    }
    key.elements.splice(s.element, 1);
    for (j in 0...out.length)
      key.elements.insert(s.element + j, out[j]);
    selection = [for (j in 0...out.length) {layer: s.layer, element: s.element + j}];
    doc.changed();
  }

  //
  // Symbols
  //

  public function enterSymbol(id:String):Void
  {
    if (doc.symbol(id) == null) return;
    editPath.push(id);
    frame = 0;
    curLayer = 0;
    selection = [];
    selStart = selEnd = 0;
    timeline.scrollFrame = 0;
    timeline.scrollRow = 0;
    refreshAll();
    setStatus('Editing symbol "${sym.name}". Esc or "Back to Scene" returns.');
  }

  function exitSymbol(all:Bool):Void
  {
    if (editPath.length == 0) return;
    if (all) editPath = [];
    else
      editPath.pop();
    frame = 0;
    curLayer = 0;
    selection = [];
    refreshAll();
  }

  function newSymbol():Void
  {
    prompt('New Symbol', 'Symbol name', 'Symbol ${doc.project.symbols.length}', name -> {
      if (name == null || name == '') return;
      doc.checkpoint();
      var s = AnimData.newSymbol(AnimData.makeId('sym'), name);
      doc.project.symbols.push(s);
      doc.changed();
      enterSymbol(s.id);
    });
  }

  function refreshLibrary():Void
  {
    if (libList == null) return;
    var ds = new ArrayDataSource<Dynamic>();
    libIds = [];
    for (i in 1...doc.project.symbols.length)
    {
      var s = doc.project.symbols[i];
      ds.add({text: 'Symbol   ${s.name}   (${AnimData.symbolLength(s)}f)'});
      libIds.push('sym:' + s.id);
    }
    for (b in doc.project.bitmaps)
    {
      if (b.library != true) continue;
      ds.add({text: 'Image    ${b.name}   ${b.width}x${b.height}'});
      libIds.push('bmp:' + b.id);
    }
    libList.dataSource = ds;
  }

  function libSelected():Null<String>
  {
    var i = libList.selectedIndex;
    return i >= 0 && i < libIds.length ? libIds[i] : null;
  }

  function libraryOpen():Void
  {
    var id = libSelected();
    if (id != null && StringTools.startsWith(id, 'sym:')) enterSymbol(id.substr(4));
  }

  public function libraryPlace():Void
  {
    var id = libSelected();
    if (id == null) return;
    var layer = currentLayer();
    if (layer == null || layer.kind == 'bitmap')
    {
      notify('Pick a vector layer', 'Symbols and images are placed on vector layers.');
      return;
    }
    doc.checkpoint();
    var key = drawKey();
    if (key == null)
    {
      doc.dropCheckpoint();
      return;
    }
    var el:AnimElement;
    var cx = editPath.length == 0 ? doc.project.width / 2 : 0.0;
    var cy = editPath.length == 0 ? doc.project.height / 2 : 0.0;
    if (StringTools.startsWith(id, 'sym:'))
    {
      el = AnimData.identity('symbol');
      el.symbol = id.substr(4);
      el.loop = 'loop';
      el.firstFrame = 0;
      el.tx = cx;
      el.ty = cy;
    }
    else
    {
      var info = doc.bitmapInfo(id.substr(4));
      el = AnimData.identity('bitmap');
      el.bitmap = id.substr(4);
      el.tx = cx - (info?.width ?? 0) / 2;
      el.ty = cy - (info?.height ?? 0) / 2;
    }
    key.elements.push(el);
    selection = [{layer: curLayer, element: key.elements.length - 1}];
    setTool('select');
    doc.changed();
  }

  function libraryRename():Void
  {
    var id = libSelected();
    if (id == null) return;
    if (StringTools.startsWith(id, 'sym:'))
    {
      var s = doc.symbol(id.substr(4));
      if (s == null) return;
      prompt('Rename symbol', 'Name', s.name, n -> {
        if (n == null || n == '') return;
        doc.checkpoint();
        s.name = n;
        doc.changed();
      });
    }
    else
    {
      var b = doc.bitmapInfo(id.substr(4));
      if (b == null) return;
      prompt('Rename image', 'Name', b.name, n -> {
        if (n == null || n == '') return;
        doc.checkpoint();
        b.name = n;
        doc.changed();
      });
    }
  }

  function libraryDuplicate():Void
  {
    var id = libSelected();
    if (id == null || !StringTools.startsWith(id, 'sym:')) return;
    var s = doc.symbol(id.substr(4));
    if (s == null) return;
    doc.checkpoint();
    var copy:AnimSymbol = AnimData.copy(s);
    copy.id = AnimData.makeId('sym');
    copy.name = s.name + ' copy';
    doc.project.symbols.push(copy);
    doc.changed();
  }

  function libraryDelete():Void
  {
    var id = libSelected();
    if (id == null) return;
    confirm('Delete', 'Delete this from the library? Every placed copy is removed too.', () -> {
      doc.checkpoint();
      var key = id.substr(4);
      var isSym = StringTools.startsWith(id, 'sym:');
      if (isSym) doc.project.symbols = [for (s in doc.project.symbols) if (s.id != key) s];
      else
        doc.project.bitmaps = [for (b in doc.project.bitmaps) if (b.id != key) b];
      for (s in doc.project.symbols)
        for (l in s.layers)
          for (k in l.frames)
            k.elements = [for (e in k.elements) if (!(isSym ? e.symbol == key : e.bitmap == key)) e];
      selection = [];
      doc.changed();
    });
  }

  //
  // Layers
  //

  public function selectLayer(i:Int):Void
  {
    if (i == curLayer) return;
    curLayer = i;
    selection = [for (s in selection) if (s.layer == i) s];
    refreshProps();
  }

  public function addLayer(kind:String):Void
  {
    doc.checkpoint();
    var count = 1;
    for (l in sym.layers)
      if (l.kind == kind) count++;
    var layer = AnimData.newLayer((kind == 'bitmap' ? 'Bitmap ' : 'Layer ') + count, kind, sym.layers.length);
    // Same length as the timeline.
    layer.frames[0].duration = AnimData.symbolLength(sym);
    if (kind == 'bitmap')
    {
      layer.frames[0].bitmap = doc.newCanvas();
      setCanvasPos(layer.frames[0]);
    }
    sym.layers.insert(curLayer, layer);
    selection = [];
    doc.changed();
  }

  function deleteLayer():Void
  {
    if (sym.layers.length <= 1)
    {
      notify('Last layer', 'A timeline needs at least one layer.');
      return;
    }
    doc.checkpoint();
    sym.layers.splice(curLayer, 1);
    selection = [];
    doc.changed();
  }

  function duplicateLayer():Void
  {
    var layer = currentLayer();
    if (layer == null) return;
    doc.checkpoint();
    var copy:AnimLayer = AnimData.copy(layer);
    copy.name = layer.name + ' copy';
    sym.layers.insert(curLayer, copy);
    doc.changed();
  }

  public function moveLayer(from:Int, to:Int):Void
  {
    if (from == to || to < 0 || to >= sym.layers.length) return;
    doc.checkpoint();
    var l = sym.layers[from];
    sym.layers.splice(from, 1);
    sym.layers.insert(to, l);
    curLayer = to;
    selection = [];
    doc.changed();
  }

  public function toggleLayer(i:Int, flag:String):Void
  {
    var l = sym.layers[i];
    if (l == null) return;
    doc.checkpoint();
    switch (flag)
    {
      case 'visible': l.visible = !l.visible;
      case 'locked': l.locked = !l.locked;
      default: l.outline = !(l.outline == true);
    }
    selection = [for (s in selection) if (s.layer != i || (l.visible && !l.locked)) s];
    doc.changed();
  }

  public function renameLayer(i:Int):Void
  {
    var l = sym.layers[i];
    if (l == null) return;
    prompt('Rename layer', 'Layer name', l.name, n -> {
      if (n == null || n == '') return;
      doc.checkpoint();
      l.name = n;
      doc.changed();
    });
  }

  //
  // Frames
  //

  public function setFrame(f:Int, ?resetSel:Bool = true):Void
  {
    if (f < 0) f = 0;
    if (resetSel) selStart = selEnd = f;
    if (f == frame) return;
    frame = f;
    clampState();
    renderDirty = true;
    if (!playing) refreshProps();
    timeline.follow(frame);
  }

  public function selectFrames(layer:Int, a:Int, b:Int):Void
  {
    curLayer = layer;
    selStart = a;
    selEnd = b;
  }

  function togglePlay():Void
  {
    if (playing) stop();
    else
    {
      playing = true;
      playTime = 0;
      selection = [];
      renderDirty = true;
    }
  }

  function stop():Void
  {
    if (!playing) return;
    playing = false;
    renderDirty = true;
    refreshProps();
  }

  /**
   * F5: add frames after the playhead on the selected layer (or stretch the layer to the playhead).
   */
  function insertFrames(n:Int):Void
  {
    var layer = currentLayer();
    if (layer == null) return;
    doc.checkpoint();
    var key = AnimData.keyAt(layer, frame);
    if (key == null)
    {
      var last = layer.frames[layer.frames.length - 1];
      last.duration = frame - last.start + 1;
    }
    else
    {
      key.duration += n;
      for (k in layer.frames)
        if (k.start > key.start) k.start += n;
    }
    doc.changed();
  }

  function removeFrames():Void
  {
    var layer = currentLayer();
    if (layer == null) return;
    var a = Std.int(Math.min(selStart, selEnd)), b = Std.int(Math.max(selStart, selEnd));
    if (a > frame || b < frame)
    {
      a = frame;
      b = frame;
    }
    doc.checkpoint();
    var count = b - a + 1;
    for (f in 0...count)
    {
      var k = AnimData.keyAt(layer, a);
      if (k == null) break;
      if (layer.frames.length == 1 && k.duration == 1) break;
      k.duration--;
      if (k.duration <= 0) layer.frames.remove(k);
      for (o in layer.frames)
        if (o.start > a) o.start--;
    }
    // A layer must start with a keyframe at frame 0.
    if (layer.frames.length > 0 && layer.frames[0].start > 0)
    {
      layer.frames[0].duration += layer.frames[0].start;
      layer.frames[0].start = 0;
    }
    if (frame >= AnimData.symbolLength(sym)) frame = AnimData.symbolLength(sym) - 1;
    selStart = selEnd = frame;
    doc.changed();
  }

  /**
   * F6 (copy of what's there) or F7 (blank).
   */
  function insertKeyframe(blank:Bool):Void
  {
    var layer = currentLayer();
    if (layer == null) return;
    var camNow = layer.kind == 'camera' ? AnimData.copy(renderer.cameraAt(sym, frame) ?? AnimData.defaultCamera(doc.project)) : null;
    doc.checkpoint();
    var key = AnimData.keyAt(layer, frame);
    var src = key ?? layer.frames[layer.frames.length - 1];
    var elements:Array<AnimElement> = blank ? [] : AnimData.copy(key != null ? renderer.tweenedElements(layer, key, frame) : src.elements);
    var bitmap:Null<String> = null;
    if (layer.kind == 'bitmap')
    {
      if (blank) bitmap = doc.newCanvas();
      else
      {
        var old = doc.getBitmap(src.bitmap);
        bitmap = doc.addBitmap(old != null ? old.clone() : new BitmapData(doc.project.width, doc.project.height, true, 0), 'canvas', false);
      }
    }
    var made:AnimKeyframe;
    if (key != null && key.start == frame)
    {
      // Already a keyframe: F6 on a keyframe adds one on the next frame (like Animate).
      if (frame + 1 < key.start + key.duration) made = splitKeyAt(layer, frame + 1, elements, bitmap);
      else
      {
        var nk:AnimKeyframe = {start: frame + 1, duration: 1, elements: elements};
        if (bitmap != null) nk.bitmap = bitmap;
        for (k in layer.frames)
          if (k.start > key.start) k.start++;
        layer.frames.insert(layer.frames.indexOf(key) + 1, nk);
        made = nk;
      }
      setFrame(frame + 1);
    }
    else
      made = splitKeyAt(layer, frame, elements, bitmap);
    if (layer.kind == 'bitmap')
    {
      if (src.bx != null) made.bx = src.bx;
      if (src.by != null) made.by = src.by;
      if (blank && made.bx == null) setCanvasPos(made);
    }
    if (camNow != null) made.camera = blank ? AnimData.defaultCamera(doc.project) : camNow;
    doc.changed();
  }

  function clearKeyframe():Void
  {
    var layer = currentLayer();
    if (layer == null) return;
    var idx = AnimData.keyIndexAt(layer, frame);
    if (idx <= 0) return;
    var key = layer.frames[idx];
    if (key.start != frame) return;
    doc.checkpoint();
    layer.frames[idx - 1].duration += key.duration;
    layer.frames.splice(idx, 1);
    doc.changed();
  }

  function setTween(on:Bool):Void
  {
    var layer = currentLayer();
    if (layer == null) return;
    var a = Std.int(Math.min(selStart, selEnd)), b = Std.int(Math.max(selStart, selEnd));
    if (a > frame || b < frame) a = b = frame;
    doc.checkpoint();
    var count = 0;
    for (k in layer.frames)
    {
      if (k.start + k.duration <= a || k.start > b) continue;
      if (on)
      {
        if (k.tween == null) k.tween = {ease: 'linear'};
        // Tweens animate symbols and images; shapes need to be inside a symbol.
        for (e in k.elements)
          if (e.type == 'shape') count++;
      }
      else
        k.tween = null;
    }
    doc.changed();
    if (on && count > 0) notify('Tip', 'Classic tweens move symbols and images. Select shapes and press F8 to make them a symbol first.');
  }

  function reverseFrames():Void
  {
    var layer = currentLayer();
    if (layer == null) return;
    doc.checkpoint();
    var contents = [for (k in layer.frames) {e: k.elements, b: k.bitmap, d: k.duration}];
    contents.reverse();
    var start = 0;
    for (i in 0...layer.frames.length)
    {
      var k = layer.frames[i];
      k.elements = contents[i].e;
      k.bitmap = contents[i].b;
      k.duration = contents[i].d;
      k.start = start;
      start += k.duration;
    }
    doc.changed();
  }

  public function moveKeyframe(layerIdx:Int, key:AnimKeyframe, newStart:Int):Void
  {
    var layer = sym.layers[layerIdx];
    if (layer == null) return;
    var idx = layer.frames.indexOf(key);
    if (idx <= 0) return; // The first keyframe stays at frame 1.
    var prev = layer.frames[idx - 1];
    var next = idx + 1 < layer.frames.length ? layer.frames[idx + 1] : null;
    var end = key.start + key.duration;
    newStart = Std.int(Math.max(prev.start + 1, newStart));
    if (next != null) newStart = Std.int(Math.min(next.start - 1, newStart));
    if (newStart == key.start) return;
    prev.duration = newStart - prev.start;
    if (next != null) key.duration = next.start - newStart;
    key.start = newStart;
    setFrame(newStart, false);
    selStart = selEnd = newStart;
    renderDirty = true;
  }

  function copyFrames():Void
  {
    var layer = currentLayer();
    if (layer == null) return;
    var a = Std.int(Math.min(selStart, selEnd)), b = Std.int(Math.max(selStart, selEnd));
    var out:Array<Dynamic> = [];
    for (f in a...b + 1)
    {
      var k = AnimData.keyAt(layer, f);
      if (k == null) continue;
      out.push({elements: renderer.tweenedElements(layer, k, f), bitmap: k.bitmap, bx: k.bx, by: k.by, key: k.start == f});
    }
    frameClipboard = haxe.Json.stringify(out);
    setStatus('Copied ${out.length} frame(s).');
  }

  function pasteFrames():Void
  {
    var layer = currentLayer();
    if (layer == null || frameClipboard == null) return;
    var frames:Array<Dynamic> = haxe.Json.parse(frameClipboard);
    if (frames.length == 0) return;
    doc.checkpoint();
    for (i in 0...frames.length)
    {
      var fr = frames[i];
      var f = frame + i;
      var bmp:Null<String> = null;
      if (layer.kind == 'bitmap' && fr.bitmap != null)
      {
        var src = doc.getBitmap(fr.bitmap);
        if (src != null) bmp = doc.addBitmap(src.clone(), 'canvas', false);
      }
      var k = splitKeyAt(layer, f, AnimData.copy(fr.elements), bmp);
      if (bmp != null)
      {
        k.bx = fr.bx;
        k.by = fr.by;
      }
      // Keep pasted frames one frame long; the next one starts right after.
      var after = AnimData.keyAt(layer, f + 1);
      if (after == k && i < frames.length - 1) splitKeyAt(layer, f + 1, AnimData.copy(fr.elements), bmp);
    }
    doc.changed();
  }

  /**
   * Right-click menu on the timeline.
   */
  public function openFrameMenu():Void
  {
    var menu = new Menu();
    addMenuItem(menu, 'Insert Frame', 'F5', () -> insertFrames(1));
    addMenuItem(menu, 'Remove Frames', 'Shift+F5', removeFrames);
    addMenuItem(menu, 'Insert Keyframe', 'F6', () -> insertKeyframe(false));
    addMenuItem(menu, 'Insert Blank Keyframe', 'F7', () -> insertKeyframe(true));
    addMenuItem(menu, 'Clear Keyframe', 'Shift+F6', clearKeyframe);
    addMenuSeparator(menu);
    addMenuItem(menu, 'Create Classic Tween', null, () -> setTween(true));
    addMenuItem(menu, 'Remove Tween', null, () -> setTween(false));
    addMenuSeparator(menu);
    addMenuItem(menu, 'Copy Frames', null, copyFrames);
    addMenuItem(menu, 'Paste Frames', null, pasteFrames);
    addMenuItem(menu, 'Reverse Frames', null, reverseFrames);
    var pos = FlxG.mouse.getViewPosition(camUI);
    menu.left = Math.min(pos.x, FlxG.width - 220);
    menu.top = Math.min(pos.y, FlxG.height - 330);
    pos.put();
    menu.show();
  }

  function resizeStage(w:Int, h:Int):Void
  {
    w = Std.int(Math.max(16, Math.min(4096, w)));
    h = Std.int(Math.max(16, Math.min(4096, h)));
    if (w == doc.project.width && h == doc.project.height) return;
    doc.checkpoint();
    doc.project.width = w;
    doc.project.height = h;
    doc.changed();
    fitView();
  }

  //
  // Tools
  //

  public function setTool(id:String, quiet:Bool = false):Void
  {
    var changed = tool != id;
    tool = id;
    for (tid => b in toolButtons)
    {
      var on = tid == id;
      var cls = 'anim-tool-on-$tid';
      if (on == b.hasClass(cls) && !(on && quiet)) continue;
      if (on) b.addClass(cls);
      else
        b.removeClass(cls);
      b.icon = on ? AnimatorSkin.icon(tid, 22, 0xFFFFFFFF) : AnimatorSkin.icon(tid, 22, AnimatorSkin.TOOL_COLORS.get(tid));
    }
    if (id != 'select') selection = [];
    if (changed && !quiet && decor != null)
    {
      var t = Lambda.find(TOOLS, t -> t.id == id);
      if (t != null) decor.showTool(id, t.name, t.key, centerX(), workBottom - 62);
    }
    refreshProps();
  }

  //
  // Properties panel
  //

  var propsDirty:Bool = false;

  /**
   * Rebuild the Properties tab (at most once a frame).
   */
  public function refreshProps():Void
  {
    propsDirty = true;
  }

  function rebuildProps():Void
  {
    propsDirty = false;
    if (propsBox == null) return;
    // Not disposed: HaxeUI may still have the old controls queued for an update this frame.
    propsBox.removeAllComponents(false);
    var form = new QOLForm(110, 170);
    propsForm = form;
    var layer = currentLayer();
    var key = layer != null ? AnimData.keyAt(layer, frame) : null;

    if (layer != null && layer.kind == 'camera')
    {
      buildCameraProps(form);
    }
    else if (selection.length > 0 && tool == 'select')
    {
      buildElementProps(form);
    }
    else
    {
      buildToolProps(form, layer);
    }

    if (layer != null)
    {
      form.section('Layer: ${layer.name}');
      form.textField('Name', () -> layer.name, v -> layer.name = v);
      form.slider('Opacity', () -> layer.alpha, v -> {
        layer.alpha = v;
        renderDirty = true;
      }, 0, 1, 0.05);
      form.dropdown('Blend', () -> AnimRender.BLEND_NAMES, () -> layer.blend ?? 'normal', v -> {
        layer.blend = v == 'normal' ? null : v;
        renderDirty = true;
      });
      form.check('Guide (not exported)', () -> layer.guide == true, v -> {
        layer.guide = v;
        renderDirty = true;
      });
    }

    if (key != null && layer != null && layer.kind != 'bitmap')
    {
      form.section('Keyframe at frame ${key.start + 1}');
      form.textField('Label', () -> key.label ?? '', v -> key.label = v == '' ? null : v);
      form.check('Classic tween', () -> key.tween != null, v -> {
        doc.checkpoint();
        key.tween = v ? {ease: 'linear'} : null;
        doc.changed();
      });
      if (key.tween != null)
      {
        form.ease('Ease', () -> key.tween?.ease ?? 'linear', v -> {
          if (key.tween != null) key.tween.ease = v;
          renderDirty = true;
        }, false, true);
        form.number('Extra spins', () -> key.tween?.spins ?? 0, v -> {
          if (key.tween != null) key.tween.spins = Std.int(v);
          renderDirty = true;
        }, -20, 20, 1, 0);
      }
    }
    form.onAnyChange = () -> {
      dirty = true;
      renderDirty = true;
    };
    propsBox.addComponent(form);
    if (inspector != null) form.fitDelta(inspector.panelWidth - inspector.naturalWidth);
  }

  function buildToolProps(form:QOLForm, layer:Null<AnimLayer>):Void
  {
    var bitmap = layer != null && layer.kind == 'bitmap';
    var name = Lambda.find(TOOLS, t -> t.id == tool)?.name ?? tool;
    form.section('$name ${bitmap ? '(bitmap layer)' : ''}');
    switch (tool)
    {
      case 'brush':
        form.slider('Size', () -> brushSize, v -> brushSize = v, 1, 200, 1);
        form.slider('Opacity', () -> opacity, v -> opacity = v, 0.05, 1, 0.05);
        if (bitmap) form.slider('Hardness', () -> hardness, v -> hardness = v, 0, 1, 0.05);
        else
        {
          form.slider('Smoothing', () -> smoothing, v -> smoothing = v, 0, 1, 0.05);
          form.check('Taper ends', () -> taper, v -> taper = v);
        }
        form.note('Paints with the Fill color. [ and ] change the size.');
      case 'pencil':
        form.slider('Size', () -> pencilSize, v -> pencilSize = v, 1, 64, 1);
        if (bitmap) form.check('Hard pixels (pixel art)', () -> pixelPencil, v -> pixelPencil = v);
        else
          form.slider('Smoothing', () -> smoothing, v -> smoothing = v, 0, 1, 0.05);
        form.note('Draws with the Stroke color.');
      case 'eraser':
        form.slider('Size', () -> eraserSize, v -> eraserSize = v, 1, 300, 1);
        if (bitmap)
        {
          form.slider('Hardness', () -> hardness, v -> hardness = v, 0, 1, 0.05);
          form.check('Hard pixels', () -> pixelPencil, v -> pixelPencil = v);
        }
        else
          form.note('Removes whole strokes and fills it touches.');
      case 'fill':
        form.slider('Tolerance', () -> fillTolerance, v -> fillTolerance = Std.int(v), 0, 255, 1);
        form.slider('Grow under lines', () -> fillGap, v -> fillGap = Std.int(v), 0, 6, 1);
        form.note(bitmap ? 'Fills connected pixels of a similar color.' : 'Fills an area closed by lines with a vector fill (click a fill to recolor it).');
      case 'line' | 'rect' | 'oval' | 'poly':
        if (tool != 'line')
        {
          form.check('Fill', () -> fillOn, v -> fillOn = v);
          form.check('Outline', () -> strokeOn, v -> strokeOn = v);
        }
        form.slider('Line width', () -> shapeStroke, v -> shapeStroke = v, 0, 40, 0.5);
        if (tool == 'rect') form.slider('Corner radius', () -> cornerRadius, v -> cornerRadius = v, 0, 200, 1);
        if (tool == 'poly')
        {
          form.slider('Sides', () -> polySides, v -> polySides = Std.int(v), 3, 16, 1);
          form.check('Star', () -> polyStar, v -> polyStar = v);
        }
        form.note('Shift keeps it square / round / at 45 degrees.');
      case 'text':
        form.slider('Size', () -> textSize, v -> textSize = v, 6, 200, 1);
        form.note('Click the stage to add text (Fill color).');
      case 'picker':
        form.note('Click to pick the Fill color, Alt+click for the Stroke color.');
      case 'select':
        form.note('Click to select (Shift adds), drag to move, drag the handles to scale, just outside a corner to rotate. '
          + 'Double-click a symbol to edit it. F8 makes a symbol.');
      default:
        form.note('Space + drag or the middle mouse button pans anywhere; Ctrl + wheel zooms.');
    }
  }

  function buildElementProps(form:QOLForm):Void
  {
    var els = [for (s in selection) elementOf(s)].filter(e -> e != null);
    if (els.length == 0) return;
    var el = els[0];
    var count = els.length;
    form.section(count > 1 ? '$count items' : switch (el.type)
    {
      case 'symbol': 'Symbol: ${doc.symbol(el.symbol)?.name ?? '?'}';
      case 'bitmap': 'Image';
      case 'text': 'Text';
      default: 'Shape';
    });
    function edit(fn:AnimElement->Void)
    {
      if (!editStarted)
      {
        doc.checkpoint();
        autoKeyframes();
        editStarted = true;
      }
      for (s in selection)
      {
        var e = elementOf(s);
        if (e != null) fn(e);
      }
      renderDirty = true;
      dirty = true;
    }
    form.pair('Position', () -> AnimGeom.decomposeEl(elementOf(selection[0]) ?? el).x, v -> edit(e -> e.tx = v),
      () -> AnimGeom.decomposeEl(elementOf(selection[0]) ?? el).y, v -> edit(e -> e.ty = v), 1, 1);
    form.pair('Scale %', () -> AnimGeom.decomposeEl(elementOf(selection[0]) ?? el).scaleX * 100, v -> edit(e -> {
      var d = AnimGeom.decomposeEl(e);
      d.scaleX = v / 100;
      AnimGeom.setMatrix(e, AnimGeom.compose(d));
    }), () -> AnimGeom.decomposeEl(elementOf(selection[0]) ?? el).scaleY * 100, v -> edit(e -> {
      var d = AnimGeom.decomposeEl(e);
      d.scaleY = v / 100;
      AnimGeom.setMatrix(e, AnimGeom.compose(d));
    }), 1, 1);
    form.number('Rotation', () -> AnimGeom.decomposeEl(elementOf(selection[0]) ?? el).rotation, v -> edit(e -> {
      var d = AnimGeom.decomposeEl(e);
      d.rotation = v;
      AnimGeom.setMatrix(e, AnimGeom.compose(d));
    }), -360, 360, 1, 1);
    form.number('Skew', () -> AnimGeom.decomposeEl(elementOf(selection[0]) ?? el).skew, v -> edit(e -> {
      var d = AnimGeom.decomposeEl(e);
      d.skew = v;
      AnimGeom.setMatrix(e, AnimGeom.compose(d));
    }), -89, 89, 1, 1);
    form.section('Color effect');
    form.slider('Alpha', () -> el.alpha ?? 1, v -> edit(e -> e.alpha = v), 0, 1, 0.01);
    form.slider('Brightness', () -> el.brightness ?? 0, v -> edit(e -> e.brightness = v), -1, 1, 0.01);
    form.colorField('Tint', () -> (el.tint ?? 0xFFFFFFFF) | 0xFF000000, v -> edit(e -> e.tint = v | 0xFF000000));
    form.slider('Tint amount', () -> el.tintAmount ?? 0, v -> edit(e -> {
      e.tintAmount = v;
      if (e.tint == null) e.tint = 0xFFFFFFFF;
    }), 0, 1, 0.01);
    form.dropdown('Blend', () -> AnimRender.BLEND_NAMES, () -> el.blend ?? 'normal', v -> edit(e -> e.blend = v == 'normal' ? null : v));

    if (el.type == 'symbol')
    {
      form.section('Playback');
      form.dropdown('Loop', () -> ['loop', 'once', 'single'], () -> el.loop ?? 'loop', v -> edit(e -> e.loop = v), () -> ['Loop', 'Play once', 'Single frame']);
      form.number('First frame', () -> (el.firstFrame ?? 0) + 1, v -> edit(e -> e.firstFrame = Std.int(Math.max(0, v - 1))), 1, 9999, 1, 0);
    }
    if (el.type == 'text')
    {
      form.section('Text');
      form.textArea('Text', () -> el.text ?? '', v -> edit(e -> e.text = v), 60);
      form.number('Size', () -> el.size ?? 32, v -> edit(e -> e.size = v), 4, 400, 1, 0);
      form.colorField('Color', () -> (el.color ?? 0xFF000000) | 0xFF000000, v -> edit(e -> e.color = v | 0xFF000000));
      form.textField('Font', () -> el.font ?? '_sans', v -> edit(e -> e.font = v));
    }
    if (el.type == 'shape' && el.paths != null && el.paths.length > 0)
    {
      form.section('Shape');
      var p = el.paths[0];
      if (p.fill != null) form.colorField('Fill', () -> (el.paths[0].fill ?? 0xFF000000) | 0xFF000000, v -> edit(e -> {
        for (pp in e.paths ?? [])
          if (pp.fill != null) pp.fill = (pp.fill & 0xFF000000) | (v & 0xFFFFFF);
      }));
      if (p.stroke != null)
      {
        form.colorField('Stroke', () -> (el.paths[0].stroke ?? 0xFF000000) | 0xFF000000, v -> edit(e -> {
          for (pp in e.paths ?? [])
            if (pp.stroke != null) pp.stroke = (pp.stroke & 0xFF000000) | (v & 0xFFFFFF);
        }));
        form.number('Line width', () -> el.paths[0].width ?? 1, v -> edit(e -> {
          for (pp in e.paths ?? [])
            if (pp.stroke != null) pp.width = v;
        }), 0, 100, 0.5, 1);
      }
    }

    form.section('Filters');
    var filters = el.filters ?? [];
    for (fi in 0...filters.length)
    {
      var f = filters[fi];
      form.note('${fi + 1}. ${filterName(f.type)}');
      switch (f.type)
      {
        case 'blur':
          form.pair('Blur X / Y', () -> f.blurX ?? 6, v -> edit(e -> e.filters[fi].blurX = v), () -> f.blurY ?? 6, v -> edit(e -> e.filters[fi].blurY = v), 1, 0, 0, 255);
        case 'glow' | 'shadow':
          form.colorField('Color', () -> (f.color ?? 0) | 0xFF000000, v -> edit(e -> e.filters[fi].color = v | 0xFF000000));
          form.pair('Blur X / Y', () -> f.blurX ?? 6, v -> edit(e -> e.filters[fi].blurX = v), () -> f.blurY ?? 6, v -> edit(e -> e.filters[fi].blurY = v), 1, 0, 0, 255);
          form.slider('Strength', () -> f.strength ?? 1, v -> edit(e -> e.filters[fi].strength = v), 0, 10, 0.1);
          form.slider('Alpha', () -> f.alpha ?? 1, v -> edit(e -> e.filters[fi].alpha = v), 0, 1, 0.01);
          if (f.type == 'shadow')
          {
            form.pair('Distance / angle', () -> f.distance ?? 6, v -> edit(e -> e.filters[fi].distance = v), () -> f.angle ?? 45,
              v -> edit(e -> e.filters[fi].angle = v), 1, 0);
          }
          form.check('Inner', () -> f.inner == true, v -> edit(e -> e.filters[fi].inner = v));
          form.check('Knockout', () -> f.knockout == true, v -> edit(e -> e.filters[fi].knockout = v));
        case 'adjust':
          form.slider('Brightness', () -> f.brightness ?? 0, v -> edit(e -> e.filters[fi].brightness = v), -100, 100, 1);
          form.slider('Contrast', () -> f.contrast ?? 0, v -> edit(e -> e.filters[fi].contrast = v), -100, 100, 1);
          form.slider('Saturation', () -> f.saturation ?? 0, v -> edit(e -> e.filters[fi].saturation = v), -100, 100, 1);
          form.slider('Hue', () -> f.hue ?? 0, v -> edit(e -> e.filters[fi].hue = v), -180, 180, 1);
      }
      form.button('Remove ${filterName(f.type)}', () -> {
        edit(e -> if (e.filters != null && fi < e.filters.length) e.filters.splice(fi, 1));
        refreshProps();
      });
    }
    form.buttons([
      {text: '+ Blur', cb: () -> addFilter({type: 'blur', blurX: 6, blurY: 6})},
      {text: '+ Glow', cb: () -> addFilter({type: 'glow', color: 0xFFFFFFFF, blurX: 10, blurY: 10, strength: 2, alpha: 1})}
    ]);
    form.buttons([
      {text: '+ Shadow', cb: () -> addFilter({type: 'shadow', color: 0xFF000000, blurX: 6, blurY: 6, distance: 6, angle: 45, alpha: 0.6, strength: 1})},
      {text: '+ Adjust', cb: () -> addFilter({type: 'adjust', brightness: 0, contrast: 0, saturation: 0, hue: 0})}
    ]);
  }

  var editStarted:Bool = false;

  static function filterName(type:String):String
  {
    return switch (type)
    {
      case 'glow': 'Glow';
      case 'shadow': 'Drop shadow';
      case 'adjust': 'Adjust color';
      default: 'Blur';
    }
  }

  function addFilter(f:AnimFilter):Void
  {
    doc.checkpoint();
    autoKeyframes();
    for (s in selection)
    {
      var e = elementOf(s);
      if (e == null) continue;
      if (e.filters == null) e.filters = [];
      e.filters.push(AnimData.copy(f));
    }
    doc.changed();
  }

  //
  // Keyboard
  //

  override function handleShortcuts():Void
  {
    var k = FlxG.keys;
    var c = ctrl();
    if (c)
    {
      if (k.justPressed.Z) k.pressed.SHIFT ? redo() : undo();
      if (k.justPressed.Y) redo();
      if (k.justPressed.C && k.pressed.ALT) copyFrames();
      else if (k.justPressed.C) copySelection();
      if (k.justPressed.V && k.pressed.ALT) pasteFrames();
      else if (k.justPressed.V) pasteSelection();
      if (k.justPressed.X)
      {
        copySelection();
        deleteSelection();
      }
      if (k.justPressed.A) selectAll();
      if (k.justPressed.B) breakApart();
      if (k.justPressed.N) newDocDialog();
      if (k.justPressed.O) openDialog();
      if (k.justPressed.ZERO) fitView();
      if (k.justPressed.ONE)
      {
        zoom = 1;
        centerStage();
      }
      if (k.justPressed.PLUS) zoomAt(1.25, centerX(), centerY());
      if (k.justPressed.MINUS) zoomAt(0.8, centerX(), centerY());
      if (k.justPressed.UP) arrange(k.pressed.SHIFT ? 99999 : 1);
      if (k.justPressed.DOWN) arrange(k.pressed.SHIFT ? -99999 : -1);
      return;
    }
    if (k.justPressed.F5) k.pressed.SHIFT ? removeFrames() : insertFrames(1);
    if (k.justPressed.F6) k.pressed.SHIFT ? clearKeyframe() : insertKeyframe(false);
    if (k.justPressed.F7) insertKeyframe(true);
    if (k.justPressed.F8) convertToSymbol();
    if (k.justPressed.ENTER) togglePlay();
    if (k.justPressed.COMMA) setFrame(Std.int(Math.max(0, frame - 1)));
    if (k.justPressed.PERIOD) setFrame(frame + 1);
    if (k.justPressed.HOME) setFrame(0);
    if (k.justPressed.END) setFrame(AnimData.symbolLength(sym) - 1);
    if (k.justPressed.DELETE || k.justPressed.BACKSPACE) deleteSelection();
    if (k.justPressed.X) swapColors();
    if (k.justPressed.LBRACKET) adjustSize(-1);
    if (k.justPressed.RBRACKET) adjustSize(1);
    var step = k.pressed.SHIFT ? 10 : 1;
    if (k.justPressed.LEFT) nudge(-step, 0);
    if (k.justPressed.RIGHT) nudge(step, 0);
    if (k.justPressed.UP) nudge(0, -step);
    if (k.justPressed.DOWN) nudge(0, step);
    if (!k.pressed.SPACE)
    {
      for (t in TOOLS)
        if (k.anyJustPressed([flixel.input.keyboard.FlxKey.fromString(t.key)])) setTool(t.id);
    }
  }

  override public function exitEditor():Void
  {
    // Escape leaves symbol editing first.
    if (editPath.length > 0)
    {
      exitSymbol(false);
      return;
    }
    if (playing)
    {
      stop();
      return;
    }
    super.exitEditor();
  }

  function adjustSize(dir:Int):Void
  {
    function f(v:Float):Float
      return Math.max(1, Math.round(v * (dir > 0 ? 1.2 : 1 / 1.2)));
    switch (tool)
    {
      case 'brush': brushSize = f(brushSize);
      case 'eraser': eraserSize = f(eraserSize);
      case 'pencil': pencilSize = f(pencilSize);
      default:
    }
    propsForm?.refresh();
  }

  override public function destroy():Void
  {
    QOLSlice.editorOwnsFunctionKeys = false;
    if (canvasRoot != null && canvasRoot.parent != null) canvasRoot.parent.removeChild(canvasRoot);
    super.destroy();
  }
}
#end
