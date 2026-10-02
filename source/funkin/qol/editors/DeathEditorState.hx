package funkin.qol.editors;

#if FEATURE_HAXEUI
import flixel.FlxCamera;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.audio.FunkinSound;
import funkin.data.character.CharacterData.CharacterDataParser;
import funkin.play.character.BaseCharacter;
import funkin.qol.runtime.QOLDeath;
import funkin.qol.ui.QOLEditorState;
import funkin.qol.ui.QOLForm;
import funkin.qol.ui.QOLTheme;
import funkin.qol.util.QOLJson;
import haxe.ui.components.Button;
import haxe.ui.components.Label;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ListView;
import haxe.ui.data.ArrayDataSource;

/**
 * The Death Animation Editor: build custom game over sequences with overlays (images, animated
 * sprites, text, solid boxes) and timed actions (tweens with any ease, sounds, flashes, shakes,
 * zooms, animations), then preview the whole thing exactly as it plays in game.
 *
 * Saves to `mods/<mod>/data/qol/deaths/<character>.json` (or `default.json` for every character).
 */
class DeathEditorState extends QOLEditorState
{
  static inline final PREVIEW_MARGIN:Int = 10;
  static inline final TIMELINE_H:Int = 150;
  static inline final TIMELINE_SECONDS:Float = 6;
  static final TWEEN_PROPS:Array<String> = ['x', 'y', 'alpha', 'angle', 'scale'];

  var charId:String = 'bf';
  var forEveryone:Bool = false;
  var data:QOLDeathData;
  var stageZoom:Float = 1.0;

  var camGame:FlxCamera;
  var camOverlay:FlxCamera;
  var previewScale:Float = 0.46;
  var previewX:Float;
  var previewY:Float;
  var previewW:Int;
  var previewH:Int;

  var bg:FlxSprite;
  var char:Null<BaseCharacter> = null;
  var followPoint:FlxObject;
  var runtime:Null<QOLDeath> = null;

  var settingsForm:QOLForm;
  var overlayList:ListView;
  var overlayForm:QOLForm;
  var actionList:ListView;
  var actionForm:QOLForm;
  var selectedOverlay:Int = -1;
  var selectedAction:Int = -1;

  // Playback.
  var phase:String = 'idle';
  var phaseTime:Float = 0;
  var music:Null<FunkinSound> = null;
  var phaseLabel:FlxText;

  // Timeline.
  var timelineX:Float;
  var timelineY:Float;
  var timelineW:Float;
  var markers:Array<{sprite:FlxSprite, index:Int}> = [];
  var playhead:FlxSprite;
  var draggingMarker:Int = -1;
  var draggingOverlay:Int = -1;
  var dragOffset:Array<Float> = [0, 0];

  public function new(?characterId:String)
  {
    super();
    editorName = 'Death Animation Editor';
    leftPanelWidth = 330;
    rightPanelWidth = 340;
    leftPanelTitle = 'Death Settings';
    rightPanelTitle = 'Overlays & Actions';
    if (characterId != null) charId = characterId;
  }

  override function guidePage():String
    return 'death';

  override function buildEditor():Void
  {
    data = QOLDeath.defaults();
    gridBG.visible = false;
    camWorld.bgColor = 0xFF151022;

    // Preview cameras, scaled to show a whole game screen inside the work area.
    computePreviewLayout();

    // Full-size 1280x720 cameras at normal zoom, shrunk into the preview box by scaling their display.
    // This keeps the view math identical to the real game (overlays stay in screen space).
    camGame = new FlxCamera(0, 0, FlxG.width, FlxG.height);
    camGame.bgColor = FlxColor.BLACK;
    placePreviewCamera(camGame);
    camOverlay = new FlxCamera(0, 0, FlxG.width, FlxG.height);
    camOverlay.bgColor = FlxColor.TRANSPARENT;
    placePreviewCamera(camOverlay);
    previewDisplay = new funkin.qol.ui.QOLScaledCameras([camGame, camOverlay], previewX, previewY, previewScale);
    FlxG.cameras.remove(camUI, false);
    FlxG.cameras.add(camGame, false);
    FlxG.cameras.add(camOverlay, false);
    FlxG.cameras.add(camUI, false);

    bg = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
    bg.setGraphicSize(FlxG.width * 6, FlxG.height * 6);
    bg.updateHitbox();
    bg.screenCenter();
    bg.scrollFactor.set();
    bg.cameras = [camGame];
    add(bg);

    followPoint = new FlxObject(0, 0, 1, 1);
    add(followPoint);


    previewTitle = QOLTheme.outlinedText(previewX, QOLEditorState.MENUBAR_HEIGHT + 8, previewW, 'Game over preview (${FlxG.width}x${FlxG.height})', 15, QOLTheme.TEXT_DIM, 1.5);
    previewTitle.cameras = [camUI];
    add(previewTitle);
    phaseLabel = QOLTheme.outlinedText(previewX, QOLEditorState.MENUBAR_HEIGHT + 8, previewW, '', 15, QOLTheme.ACCENT_YELLOW, 1.5);
    phaseLabel.alignment = RIGHT;
    phaseLabel.cameras = [camUI];
    add(phaseLabel);

    buildTimeline();
    buildMenus();
    buildSettings();
    buildLists();

    load(charId);
  }

  function buildMenus()
  {
    var file = addMenu('File');
    addMenuItem(file, 'Open Character...', 'Ctrl+O', () -> {
      chooseFromList('Edit the death of...', CharacterDataParser.listCharacterIds(), id -> load(id), charId);
    });
    addMenuItem(file, 'Save', 'Ctrl+S', () -> doSave());
    addMenuItem(file, 'Delete This Death Sequence', null, () -> confirm('Delete', 'Delete ${fileId()}.json from your mod?', () -> {
      ModWorkspace.delete('data/qol/deaths/${fileId()}.json');
      notify('Deleted', 'data/qol/deaths/${fileId()}.json');
      load(charId);
    }));
    var playMenu = addMenu('Preview');
    addMenuItem(playMenu, 'Play Death', 'Space', () -> startPhase('start'));
    addMenuItem(playMenu, 'Press Retry', 'Enter', () -> startPhase('retry'));
    addMenuItem(playMenu, 'Stop', 'Backspace', () -> stopPreview());
  }

  var previewDisplay:Null<funkin.qol.ui.QOLScaledCameras> = null;
  var previewTitle:Null<FlxText> = null;
  var timelineSprites:Array<FlxSprite> = [];

  /**
   * Fit the preview (and the timeline under it) into the space between the panels.
   */
  function computePreviewLayout():Void
  {
    var areaW = Math.max(200, workRight - workLeft - PREVIEW_MARGIN * 2);
    // Leave room for the timeline (3 rows + ruler) under the preview.
    var areaH = FlxG.height - QOLEditorState.MENUBAR_HEIGHT - QOLEditorState.STATUSBAR_HEIGHT - 34 - 150;
    previewScale = Math.min(areaW / FlxG.width, areaH / FlxG.height);
    previewW = Std.int(FlxG.width * previewScale);
    previewH = Std.int(FlxG.height * previewScale);
    previewX = workLeft + PREVIEW_MARGIN + (areaW - previewW) / 2;
    previewY = QOLEditorState.MENUBAR_HEIGHT + 34;
  }

  override function onLayoutChanged():Void
  {
    if (previewDisplay == null) return;
    computePreviewLayout();
    previewDisplay.x = previewX;
    previewDisplay.y = previewY;
    previewDisplay.scale = previewScale;
    previewDisplay.place();
    if (previewTitle != null)
    {
      previewTitle.x = previewX;
      previewTitle.fieldWidth = previewW;
    }
    if (phaseLabel != null)
    {
      phaseLabel.x = previewX;
      phaseLabel.fieldWidth = previewW;
    }
    for (spr in timelineSprites)
    {
      remove(spr, true);
      spr.destroy();
    }
    timelineSprites = [];
    var playheadVisible = playhead != null && playhead.visible;
    buildTimeline();
    playhead.visible = playheadVisible;
    rebuildMarkers();
  }

  function placePreviewCamera(cam:FlxCamera)
  {
    // Cameras keep x/y = 0; QOLScaledCameras shrinks them into the preview box.
    cam.x = 0;
    cam.y = 0;
    cam.flashSprite.scaleX = cam.flashSprite.scaleY = previewScale;
  }

  /**
   * Mouse position in the 1280x720 preview "screen".
   */
  function previewMouse():Array<Float>
  {
    return [(FlxG.mouse.viewX - previewX) / previewScale, (FlxG.mouse.viewY - previewY) / previewScale];
  }

  function fileId():String
    return forEveryone ? 'default' : charId;

  //
  // Panels
  //

  function buildSettings()
  {
    settingsForm = new QOLForm(118, 170);
    settingsForm.onAnyChange = () -> {
      dirty = true;
      rebuildRuntime();
    };
    settingsForm.section('Who dies');
    settingsForm.dropdown('Character', () -> CharacterDataParser.listCharacterIds(), () -> charId, v -> {
      charId = v;
      buildCharacter();
    });
    settingsForm.check('Use for everyone', () -> forEveryone, v -> forEveryone = v);
    settingsForm.note('On: saves as default.json and plays for every character without their own death.');

    settingsForm.section('Animations');
    settingsForm.dropdown('Death', charAnims, () -> data.firstAnim ?? 'firstDeath', v -> data.firstAnim = v);
    settingsForm.dropdown('Loop', charAnims, () -> data.loopAnim ?? 'deathLoop', v -> data.loopAnim = v);
    settingsForm.dropdown('Retry', charAnims, () -> data.confirmAnim ?? 'deathConfirm', v -> data.confirmAnim = v);
    settingsForm.check('Hide character', () -> data.hideCharacter == true, v -> data.hideCharacter = v);

    settingsForm.section('Sound & music');
    settingsForm.file('Death sound', () -> data.startSound ?? '', v -> data.startSound = v,
      cb -> browseModFile('Death sound', 'sounds', ['ogg', 'mp3'], cb));
    settingsForm.file('Loop music', () -> data.music ?? '', v -> data.music = v, cb -> browseModFile('Game over music', 'music', ['ogg', 'mp3'], cb));
    settingsForm.file('Retry music', () -> data.endMusic ?? '', v -> data.endMusic = v,
      cb -> browseModFile('Retry music', 'music', ['ogg', 'mp3'], cb));
    settingsForm.slider('Music volume', () -> data.musicVolume ?? 1, v -> data.musicVolume = v, 0, 1, 0.05);

    settingsForm.section('Screen');
    settingsForm.colorField('Background', () -> QOLDeath.colorOf(data.bgColor, FlxColor.BLACK), v -> data.bgColor = '#' + StringTools.hex(v & 0xFFFFFF, 6));
    settingsForm.slider('Background alpha', () -> data.bgAlpha ?? 1, v -> data.bgAlpha = v, 0, 1, 0.05);
    settingsForm.pair('Camera offset', () -> arr('cameraOffsets')[0], v -> arr('cameraOffsets')[0] = v, () -> arr('cameraOffsets')[1],
      v -> arr('cameraOffsets')[1] = v);
    settingsForm.number('Camera zoom', () -> data.cameraZoom ?? 1, v -> data.cameraZoom = v, 0.1, 10, 0.05, 2);
    settingsForm.number('Camera speed', () -> data.cameraSpeed ?? 1, v -> data.cameraSpeed = v, 0, 20, 0.1, 2);
    settingsForm.number('Stage zoom (preview)', () -> stageZoom, v -> stageZoom = v, 0.1, 5, 0.05, 2);

    settingsForm.section('Retry');
    settingsForm.colorField('Fade color', () -> QOLDeath.colorOf(data.retryFadeColor, FlxColor.BLACK),
      v -> data.retryFadeColor = '#' + StringTools.hex(v & 0xFFFFFF, 6));
    settingsForm.number('Fade time (s)', () -> data.retryFadeTime ?? 2, v -> data.retryFadeTime = v, 0, 20, 0.1, 2);
    settingsForm.number('Delay before fade', () -> data.retryDelay ?? 0.7, v -> data.retryDelay = v, 0, 20, 0.1, 2);
    leftPanel.addComponent(settingsForm);
  }

  function arr(field:String):Array<Float>
  {
    var v:Array<Float> = Reflect.field(data, field);
    if (v == null || v.length < 2)
    {
      v = [0, 0];
      Reflect.setField(data, field, v);
    }
    return v;
  }

  function charAnims():Array<String>
  {
    if (char == null) return ['firstDeath', 'deathLoop', 'deathConfirm'];
    var names = char.animation.getNameList();
    names.sort((a, b) -> a < b ? -1 : 1);
    return names;
  }

  function buildLists()
  {
    // Overlays.
    var oTitle = new Label();
    oTitle.text = 'Overlays (drawn on top of the screen)';
    oTitle.styleString = 'font-bold: true; color: #FF8FB8;';
    rightPanel.addComponent(oTitle);
    overlayList = new ListView();
    overlayList.width = rightPanelWidth - 30;
    overlayList.height = 90;
    overlayList.onChange = _ -> {
      if (overlayList.selectedIndex != selectedOverlay)
      {
        selectedOverlay = overlayList.selectedIndex;
        overlayForm.refresh();
      }
    };
    rightPanel.addComponent(overlayList);
    var oRow = new HBox();
    oRow.addComponent(btn('+ Image', () -> addOverlay('image')));
    oRow.addComponent(btn('+ Anim', () -> addOverlay('animated')));
    oRow.addComponent(btn('+ Text', () -> addOverlay('text')));
    oRow.addComponent(btn('+ Box', () -> addOverlay('solid')));
    oRow.addComponent(btn('Delete', removeOverlay));
    rightPanel.addComponent(oRow);

    overlayForm = new QOLForm(92, 200);
    overlayForm.onAnyChange = () -> {
      dirty = true;
      refreshOverlayList();
      rebuildRuntime();
    };
    overlayForm.textField('ID', () -> ov()?.id ?? '', v -> {
      var o = ov();
      if (o == null) return;
      for (a in data.actions ?? [])
        if (a.target == o.id) a.target = v;
      o.id = v;
    });
    overlayForm.dropdown('Type', () -> QOLDeath.OVERLAY_TYPES, () -> ov()?.type ?? 'image', v -> if (ov() != null) ov().type = v);
    overlayForm.file('Image', () -> ov()?.image ?? '', v -> if (ov() != null) ov().image = v,
      cb -> browseModFile('Overlay image', 'images', ['png'], cb));
    overlayForm.textField('Anim prefix', () -> ov()?.anim ?? '', v -> if (ov() != null) ov().anim = v);
    overlayForm.textField('Text', () -> ov()?.text ?? '', v -> if (ov() != null) ov().text = v);
    overlayForm.dropdown('Font', () -> ['', 'vcr.ttf', 'pixel.otf', 'Quantico-Bold.ttf', 'Quantico-Regular.ttf', 'Inconsolata-Bold.ttf', '5by7.ttf'],
      () -> ov()?.font ?? '', v -> if (ov() != null) ov().font = v);
    overlayForm.number('Text size', () -> ov()?.size ?? 48, v -> if (ov() != null) ov().size = Std.int(v), 4, 400, 1, 0);
    overlayForm.colorField('Color', () -> QOLDeath.colorOf(ov()?.color, FlxColor.WHITE), v -> if (ov() != null) ov().color = '#' + StringTools.hex(v & 0xFFFFFF, 6));
    overlayForm.pair('Box size', () -> ov()?.width ?? 200, v -> if (ov() != null) ov().width = Std.int(v), () -> ov()?.height ?? 100,
      v -> if (ov() != null) ov().height = Std.int(v), 1, 0, 1, 4000);
    overlayForm.pair('Position', () -> ov()?.x ?? 0, v -> if (ov() != null) ov().x = v, () -> ov()?.y ?? 0, v -> if (ov() != null) ov().y = v);
    overlayForm.number('Scale', () -> ov()?.scale ?? 1, v -> if (ov() != null) ov().scale = v, 0.01, 50, 0.05, 2);
    overlayForm.slider('Alpha', () -> ov()?.alpha ?? 1, v -> if (ov() != null) ov().alpha = v, 0, 1, 0.05);
    overlayForm.number('Angle', () -> ov()?.angle ?? 0, v -> if (ov() != null) ov().angle = v, -360, 360, 1, 1);
    overlayForm.check('Visible at start', () -> ov()?.visible != false, v -> if (ov() != null) ov().visible = v);
    overlayForm.dropdown('Blend', () -> ['normal', 'add', 'multiply', 'screen', 'lighten', 'darken', 'difference', 'overlay'],
      () -> ov()?.blend ?? 'normal', v -> if (ov() != null) ov().blend = v);
    rightPanel.addComponent(overlayForm);

    // Actions.
    var aTitle = new Label();
    aTitle.text = 'Timed actions';
    aTitle.styleString = 'font-bold: true; color: #FF8FB8; padding-top: 8px;';
    rightPanel.addComponent(aTitle);
    actionList = new ListView();
    actionList.width = rightPanelWidth - 30;
    actionList.height = 110;
    actionList.onChange = _ -> {
      if (actionList.selectedIndex != selectedAction) selectAction(actionList.selectedIndex);
    };
    rightPanel.addComponent(actionList);
    var aRow = new HBox();
    aRow.addComponent(btn('+ Action', addAction));
    aRow.addComponent(btn('Copy', duplicateAction));
    aRow.addComponent(btn('Delete', removeAction));
    rightPanel.addComponent(aRow);

    actionForm = new QOLForm(92, 200);
    actionForm.onAnyChange = () -> {
      dirty = true;
      refreshActionList();
      rebuildRuntime();
    };
    actionForm.dropdown('When', () -> QOLDeath.TRIGGERS, () -> act()?.trigger ?? 'start', v -> if (act() != null) act().trigger = v,
      () -> ['After dying', 'When the loop starts', 'After pressing retry']);
    actionForm.number('Time (s)', () -> act()?.time ?? 0, v -> if (act() != null) act().time = v, 0, 120, 0.05, 2);
    actionForm.dropdown('Action', () -> QOLDeath.ACTION_TYPES, () -> act()?.type ?? 'tween', v -> if (act() != null) act().type = v,
      () -> ['Tween', 'Show', 'Hide', 'Play animation', 'Play sound', 'Flash', 'Shake camera', 'Zoom camera']);
    actionForm.dropdown('Target', () -> ['character', 'camera'].concat([for (o in data.overlays ?? []) o.id]), () -> act()?.target ?? 'character',
      v -> if (act() != null) act().target = v);
    actionForm.dropdown('Tween property', () -> TWEEN_PROPS, () -> tweenProp(act()), v -> setTweenProp(act(), v, tweenValue(act())));
    actionForm.number('Tween to', () -> tweenValue(act()), v -> setTweenProp(act(), tweenProp(act()), v), -99999, 99999, 1, 2);
    actionForm.number('Duration (s)', () -> act()?.duration ?? 1, v -> if (act() != null) act().duration = v, 0, 60, 0.05, 2);
    actionForm.ease('Ease', () -> act()?.ease ?? 'linear', v -> if (act() != null) act().ease = v);
    actionForm.textField('Animation', () -> act()?.anim ?? '', v -> if (act() != null) act().anim = v);
    actionForm.file('Sound', () -> act()?.sound ?? '', v -> if (act() != null) act().sound = v, cb -> browseModFile('Sound', 'sounds', ['ogg', 'mp3'], cb));
    actionForm.slider('Volume', () -> act()?.volume ?? 1, v -> if (act() != null) act().volume = v, 0, 1, 0.05);
    actionForm.colorField('Flash color', () -> QOLDeath.colorOf(act()?.color, FlxColor.WHITE),
      v -> if (act() != null) act().color = '#' + StringTools.hex(v & 0xFFFFFF, 6));
    actionForm.number('Shake amount', () -> act()?.intensity ?? 0.02, v -> if (act() != null) act().intensity = v, 0, 1, 0.005, 3);
    actionForm.number('Zoom to (x)', () -> act()?.zoom ?? 1, v -> if (act() != null) act().zoom = v, 0.05, 20, 0.05, 2);
    actionForm.note('Space: play the death  ·  Enter: press retry  ·  Backspace: stop\nDrag overlays in the preview, drag markers on the timeline.');
    rightPanel.addComponent(actionForm);
  }

  function btn(text:String, cb:Void->Void):Button
  {
    var b = new Button();
    b.text = text;
    b.onClick = _ -> cb();
    return b;
  }

  function ov():Null<QOLDeathOverlay>
  {
    var list = data.overlays ?? [];
    return selectedOverlay >= 0 && selectedOverlay < list.length ? list[selectedOverlay] : null;
  }

  function act():Null<QOLDeathAction>
  {
    var list = data.actions ?? [];
    return selectedAction >= 0 && selectedAction < list.length ? list[selectedAction] : null;
  }

  static function tweenProp(a:Null<QOLDeathAction>):String
  {
    if (a == null) return 'x';
    for (p in TWEEN_PROPS)
      if (Reflect.field(a, p) != null) return p;
    return 'x';
  }

  static function tweenValue(a:Null<QOLDeathAction>):Float
  {
    if (a == null) return 0;
    var v:Null<Float> = Reflect.field(a, tweenProp(a));
    return v ?? 0;
  }

  static function setTweenProp(a:Null<QOLDeathAction>, prop:String, value:Float)
  {
    if (a == null) return;
    for (p in TWEEN_PROPS)
      Reflect.deleteField(a, p);
    Reflect.setField(a, prop, value);
  }

  //
  // Overlays & actions
  //

  function refreshOverlayList()
  {
    var ds = new ArrayDataSource<Dynamic>();
    for (o in data.overlays ?? [])
      ds.add({text: '${o.id}  (${o.type})'});
    overlayList.dataSource = ds;
    if (selectedOverlay >= 0) overlayList.selectedIndex = selectedOverlay;
  }

  function addOverlay(type:String)
  {
    if (data.overlays == null) data.overlays = [];
    var n = data.overlays.length + 1;
    var o:QOLDeathOverlay = {
      id: '$type$n',
      type: type,
      x: 440,
      y: 300
    };
    switch (type)
    {
      case 'text':
        o.text = 'GAME OVER';
        o.size = 64;
        o.font = 'vcr.ttf';
        o.color = '#FFFFFF';
        o.x = 460;
        o.y = 120;
      case 'solid':
        o.width = 1280;
        o.height = 720;
        o.x = 0;
        o.y = 0;
        o.color = '#FF0000';
        o.alpha = 0.3;
        o.blend = 'add';
      default:
        o.image = 'menuDesat';
    }
    data.overlays.push(o);
    selectedOverlay = data.overlays.length - 1;
    refreshOverlayList();
    overlayForm.refresh();
    actionForm.refresh();
    dirty = true;
    rebuildRuntime();
  }

  function removeOverlay()
  {
    var o = ov();
    if (o == null) return;
    data.overlays.remove(o);
    selectedOverlay = -1;
    refreshOverlayList();
    overlayForm.refresh();
    dirty = true;
    rebuildRuntime();
  }

  function refreshActionList()
  {
    var ds = new ArrayDataSource<Dynamic>();
    for (a in data.actions ?? [])
      ds.add({text: '${a.trigger ?? 'start'} @ ${a.time}s  ·  ${a.type} ${a.target ?? ''}'});
    actionList.dataSource = ds;
    if (selectedAction >= 0) actionList.selectedIndex = selectedAction;
    rebuildMarkers();
  }

  function selectAction(index:Int)
  {
    selectedAction = index;
    if (actionList.selectedIndex != index) actionList.selectedIndex = index;
    actionForm.refresh();
    rebuildMarkers();
  }

  function addAction()
  {
    if (data.actions == null) data.actions = [];
    data.actions.push({
      time: Math.round(phaseTime * 20) / 20,
      trigger: phase == 'loop' || phase == 'retry' ? phase : 'start',
      type: 'tween',
      target: (data.overlays ?? []).length > 0 ? data.overlays[0].id : 'character',
      alpha: 1,
      duration: 1,
      ease: 'quadOut'
    });
    selectAction(data.actions.length - 1);
    refreshActionList();
    dirty = true;
  }

  function duplicateAction()
  {
    var a = act();
    if (a == null) return;
    var copy:QOLDeathAction = QOLJson.clone(a);
    copy.time += 0.5;
    data.actions.push(copy);
    selectAction(data.actions.length - 1);
    refreshActionList();
    dirty = true;
  }

  function removeAction()
  {
    var a = act();
    if (a == null) return;
    data.actions.remove(a);
    selectedAction = -1;
    refreshActionList();
    actionForm.refresh();
    dirty = true;
  }

  //
  // Timeline
  //

  function buildTimeline()
  {
    timelineX = previewX + 70;
    timelineY = previewY + previewH + 40;
    timelineW = previewW - 80;
    var rows = ['Dying', 'Loop', 'Retry'];
    var key = 'qol-death-timeline-${Std.int(timelineW)}';
    var ruler = new FlxSprite(timelineX, timelineY).loadGraphic(QOLTheme.cached(key, () -> {
      var bmp = new openfl.display.BitmapData(Std.int(timelineW), 3 * 30 + 4, true, 0);
      for (r in 0...3)
        bmp.fillRect(new openfl.geom.Rectangle(0, r * 30 + 2, timelineW, 26), r % 2 == 0 ? 0xFF2B2340 : 0xFF241D36);
      var s = 0.0;
      while (s <= TIMELINE_SECONDS)
      {
        var x = Std.int(s / TIMELINE_SECONDS * (timelineW - 1));
        var whole = Math.abs(s - Math.round(s)) < 0.001;
        bmp.fillRect(new openfl.geom.Rectangle(x, 0, 1, whole ? 94 : 6), whole ? 0xFF5A4F80 : 0xFF3F3760);
        s += 0.25;
      }
      return bmp;
    }));
    ruler.cameras = [camUI];
    add(ruler);
    timelineSprites.push(ruler);
    for (i in 0...rows.length)
    {
      var l = QOLTheme.outlinedText(previewX, timelineY + i * 30 + 7, 66, rows[i], 13, QOLTheme.TEXT_DIM, 1);
      l.cameras = [camUI];
      add(l);
      timelineSprites.push(l);
    }
    var s = 0;
    while (s <= TIMELINE_SECONDS)
    {
      var l = QOLTheme.text(timelineX + s / TIMELINE_SECONDS * timelineW - 10, timelineY - 18, 30, '${s}s', 11, QOLTheme.FONT_MONO, QOLTheme.TEXT_DIM);
      l.cameras = [camUI];
      add(l);
      timelineSprites.push(l);
      s++;
    }
    playhead = new FlxSprite().makeGraphic(2, 96, 0xFFFF3355);
    playhead.cameras = [camUI];
    playhead.visible = false;
    add(playhead);
    timelineSprites.push(playhead);
  }

  function rebuildMarkers()
  {
    for (m in markers)
    {
      remove(m.sprite, true);
      m.sprite.destroy();
    }
    markers = [];
    var actions = data.actions ?? [];
    for (i in 0...actions.length)
    {
      var a = actions[i];
      var row = QOLDeath.TRIGGERS.indexOf(a.trigger ?? 'start');
      var color:FlxColor = switch (a.type)
      {
        case 'tween' | 'zoom': 0xFFB59BFF;
        case 'sound': 0xFF5CE1FF;
        case 'flash' | 'shake': 0xFFFFD84A;
        default: 0xFF7CE38B;
      };
      var d = QOLTheme.diamond(16, color, i == selectedAction ? 0xFFFFFFFF : 0xFF1A1030);
      d.setPosition(timelineX + Math.min(a.time, TIMELINE_SECONDS) / TIMELINE_SECONDS * timelineW - 8, timelineY + row * 30 + 7);
      d.cameras = [camUI];
      add(d);
      markers.push({sprite: d, index: i});
    }
  }

  //
  // Loading & preview
  //

  function load(id:String)
  {
    stopPreview();
    charId = id;
    var raw:Dynamic = ModWorkspace.getJson('data/qol/deaths/$id.json');
    forEveryone = false;
    if (raw == null)
    {
      var existing = QOLDeath.load(id);
      raw = existing != null ? QOLJson.clone(existing) : null;
    }
    data = raw != null ? raw : QOLDeath.defaults();
    selectedOverlay = -1;
    selectedAction = -1;
    buildCharacter();
    settingsForm.refresh();
    refreshOverlayList();
    overlayForm.refresh();
    refreshActionList();
    actionForm.refresh();
    dirty = false;
  }

  function buildCharacter()
  {
    if (char != null)
    {
      remove(char, true);
      char.destroy();
      char = null;
    }
    try
    {
      char = CharacterDataParser.fetchCharacter(charId, true);
      if (char != null)
      {
        char.cameras = [camGame];
        char.flipX = !char.getDataFlipX();
        char.resetCharacter(true);
        char.x = 900 - char.characterOrigin.x;
        char.y = 880 - char.characterOrigin.y;
        char.originalPosition.set(char.x, char.y);
        char.resetCameraFocusPoint();
        insert(members.indexOf(bg) + 1, char);
      }
    }
    catch (e)
    {
      trace('[QOL] Death preview character failed: $e');
    }
    settingsForm?.refresh();
    rebuildRuntime();
    snapCamera();
  }

  function rebuildRuntime()
  {
    if (runtime != null)
    {
      remove(runtime.overlays, true);
      runtime.destroy();
    }
    if (char != null) char.visible = true;
    runtime = new QOLDeath(data, char, camGame, camOverlay);
    add(runtime.overlays);
    bg.color = QOLDeath.colorOf(data.bgColor, FlxColor.BLACK);
    bg.alpha = data.bgAlpha ?? 1;
  }

  function targetZoom():Float
  {
    var deathZoom = 1.0;
    @:privateAccess if (char != null) deathZoom = char.getDeathCameraZoom();
    return stageZoom * deathZoom * (data.cameraZoom ?? 1) * (runtime?.zoomMultiplier ?? 1);
  }

  function cameraTarget():Array<Float>
  {
    if (char == null) return [FlxG.width / 2, FlxG.height / 2];
    var cx = char.originalPosition.x + char.width / 2;
    var cy = char.originalPosition.y + char.height / 2;
    var death = char.getDeathCameraOffsets();
    var extra = arr('cameraOffsets');
    return [cx + death[0] + extra[0], cy + death[1] + extra[1]];
  }

  function snapCamera()
  {
    var t = cameraTarget();
    followPoint.setPosition(t[0], t[1]);
    camGame.zoom = targetZoom();
    camGame.focusOn(followPoint.getMidpoint());
  }

  function startPhase(name:String)
  {
    if (name == 'start')
    {
      stopPreview();
      rebuildRuntime();
      if (char != null)
      {
        char.canPlayOtherAnims = true;
        char.playAnimation(data.firstAnim ?? 'firstDeath', true, true);
      }
      var s = data.startSound;
      if (s != null && s != '' && Assets.exists(Paths.sound(s))) FunkinSound.playOnce(Paths.sound(s));
    }
    else if (name == 'loop')
    {
      if (char != null)
      {
        char.canPlayOtherAnims = true;
        char.playAnimation(data.loopAnim ?? 'deathLoop', true);
      }
      playMusic(data.music, true);
    }
    else if (name == 'retry')
    {
      if (phase == 'idle') return;
      if (char != null)
      {
        char.canPlayOtherAnims = true;
        char.playAnimation(data.confirmAnim ?? 'deathConfirm', true);
      }
      playMusic(data.endMusic, false);
      var color = QOLDeath.colorOf(data.retryFadeColor, FlxColor.BLACK);
      new flixel.util.FlxTimer().start(data.retryDelay ?? 0.7, _ -> {
        if (phase == 'retry') camGame.fade(color, data.retryFadeTime ?? 2, false, () -> {
          stopPreview();
        }, true);
      });
    }
    phase = name;
    phaseTime = 0;
    runtime?.trigger(name);
  }

  function playMusic(key:Null<String>, loop:Bool)
  {
    if (music != null) music.stop();
    music = null;
    if (key == null || key == '' || !Assets.exists(Paths.music(key))) return;
    music = FunkinSound.load(Paths.music(key));
    if (music == null) return;
    music.volume = data.musicVolume ?? 1;
    music.looped = loop;
    music.play();
  }

  function stopPreview()
  {
    phase = 'idle';
    phaseTime = 0;
    if (music != null) music.stop();
    music = null;
    camGame?.stopFX();
    if (data != null) rebuildRuntime();
    if (char != null)
    {
      char.canPlayOtherAnims = true;
      char.dance(true);
    }
  }

  override function save():Bool
  {
    data.version = '1.0.0';
    var path = ModWorkspace.saveJson('data/qol/deaths/${fileId()}.json', data, [
      'version', 'firstAnim', 'loopAnim', 'confirmAnim', 'startSound', 'music', 'endMusic', 'overlays', 'actions', 'id', 'type', 'trigger', 'time'
    ]);
    notifySaved(path);
    return true;
  }

  override function afterSaveReload():Void
  {
    // Keep the preview character; just make the game see the new file.
    ModWorkspace.reloadGameData();
    buildCharacter();
  }

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);

    // Camera follow & zoom, like the real game over screen.
    var t = cameraTarget();
    followPoint.setPosition(t[0], t[1]);
    var speed = 0.04 / 2 * 60 * (data.cameraSpeed ?? 1);
    var mid = followPoint.getMidpoint();
    camGame.zoom = funkin.util.MathUtil.smoothLerpPrecision(camGame.zoom, targetZoom(), elapsed, 0.5);
    var desiredX = mid.x - camGame.width / 2;
    var desiredY = mid.y - camGame.height / 2;
    camGame.scroll.x += (desiredX - camGame.scroll.x) * Math.min(1, elapsed * speed);
    camGame.scroll.y += (desiredY - camGame.scroll.y) * Math.min(1, elapsed * speed);
    mid.put();

    if (phase != 'idle')
    {
      phaseTime += elapsed;
      runtime?.update(elapsed);
      if (phase == 'start' && char != null && char.isAnimationFinished()) startPhase('loop');
    }
    var row = QOLDeath.TRIGGERS.indexOf(phase);
    playhead.visible = row >= 0;
    if (row >= 0) playhead.setPosition(timelineX + Math.min(phaseTime, TIMELINE_SECONDS) / TIMELINE_SECONDS * timelineW - 1, timelineY - 1);
    var label = phase == 'idle' ? 'Press Space to play' : '${phase.toUpperCase()}  ${Math.round(phaseTime * 10) / 10}s';
    if (phaseLabel.text != label) phaseLabel.text = label;

    handleMouse();
  }

  function handleMouse()
  {
    if (dialogOpen) return;
    var mx = FlxG.mouse.viewX;
    var my = FlxG.mouse.viewY;

    // Timeline markers.
    if (FlxG.mouse.justPressed && !mouseOverUI)
    {
      for (m in markers)
      {
        if (mx >= m.sprite.x && mx <= m.sprite.x + m.sprite.width && my >= m.sprite.y && my <= m.sprite.y + m.sprite.height)
        {
          selectAction(m.index);
          draggingMarker = m.index;
          return;
        }
      }
      // Overlays inside the preview.
      if (mx >= previewX && mx <= previewX + previewW && my >= previewY && my <= previewY + previewH && runtime != null)
      {
        var pm = previewMouse();
        var lx = pm[0];
        var ly = pm[1];
        var list = data.overlays ?? [];
        var i = list.length - 1;
        while (i >= 0)
        {
          var spr = runtime.overlayMap.get(list[i].id);
          if (spr != null && lx >= spr.x && lx <= spr.x + spr.width && ly >= spr.y && ly <= spr.y + spr.height)
          {
            selectedOverlay = i;
            refreshOverlayList();
            overlayForm.refresh();
            draggingOverlay = i;
            dragOffset = [lx - list[i].x, ly - list[i].y];
            break;
          }
          i--;
        }
      }
    }

    if (draggingMarker >= 0)
    {
      var a = data.actions[draggingMarker];
      a.time = Math.max(0, Math.round((mx - timelineX) / timelineW * TIMELINE_SECONDS * 20) / 20);
      var row = Std.int(Math.max(0, Math.min(2, (my - timelineY) / 30)));
      a.trigger = QOLDeath.TRIGGERS[row];
      var m = markers[draggingMarker];
      m.sprite.setPosition(timelineX + Math.min(a.time, TIMELINE_SECONDS) / TIMELINE_SECONDS * timelineW - 8, timelineY + row * 30 + 7);
      if (!FlxG.mouse.pressed)
      {
        draggingMarker = -1;
        dirty = true;
        refreshActionList();
        actionForm.refresh();
      }
    }

    if (draggingOverlay >= 0)
    {
      var o = data.overlays[draggingOverlay];
      var pm = previewMouse();
      o.x = Math.round(pm[0] - dragOffset[0]);
      o.y = Math.round(pm[1] - dragOffset[1]);
      var spr = runtime?.overlayMap.get(o.id);
      if (spr != null) spr.setPosition(o.x, o.y);
      if (!FlxG.mouse.pressed)
      {
        draggingOverlay = -1;
        dirty = true;
        overlayForm.refresh();
      }
    }
  }

  override function handleShortcuts():Void
  {
    if (FlxG.keys.justPressed.SPACE) startPhase('start');
    if (FlxG.keys.justPressed.ENTER) startPhase('retry');
    if (FlxG.keys.justPressed.BACKSPACE) stopPreview();
    if (ctrl() && FlxG.keys.justPressed.O) chooseFromList('Edit the death of...', CharacterDataParser.listCharacterIds(), id -> load(id), charId);
  }

  override public function destroy():Void
  {
    previewDisplay?.destroy();
    if (music != null) music.stop();
    runtime?.destroy();
    super.destroy();
  }
}
#end
