package funkin.qol.editors;

#if FEATURE_HAXEUI
import flixel.FlxBasic;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSort;
import funkin.data.character.CharacterData.CharacterDataParser;
import funkin.data.stage.StageRegistry;
import funkin.play.character.BaseCharacter;
import funkin.play.stage.Bopper;
import funkin.play.stage.StageProp;
import funkin.qol.runtime.QOLStageEvents;
import funkin.qol.ui.QOLEditorState;
import funkin.qol.ui.QOLForm;
import funkin.qol.ui.QOLTheme;
import funkin.qol.util.QOLAssets;
import funkin.qol.util.QOLJson;
import funkin.util.SortUtil;
import funkin.util.assets.FlxAnimationUtil;
import haxe.ui.components.Button;
import haxe.ui.components.Label;
import haxe.ui.containers.Box;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ListView;
import haxe.ui.containers.TabView;
import haxe.ui.containers.VBox;
import haxe.ui.data.ArrayDataSource;
import openfl.display.BlendMode;

/**
 * The Background (stage) Editor.
 *
 * Place and style props (images, animated sprites, solid colors), position the characters and
 * their cameras, set the camera zoom, and build **stage events**: little scripted sequences
 * (move a prop, play an animation, flash the camera...) that charts can trigger with the
 * "Stage Event" chart event.
 *
 * Saves to `data/stages/<id>.json` (V-Slice format) and `data/qol/stage-events/<id>.json`.
 */
class BackgroundEditorState extends QOLEditorState
{
  static inline final MAX_UNDO:Int = 150;
  static final CHAR_KEYS:Array<String> = ['bf', 'gf', 'dad'];
  static final BLENDS:Array<String> = ['normal', 'add', 'multiply', 'screen', 'lighten', 'darken', 'difference', 'overlay', 'subtract', 'invert'];

  var stageId:String = 'my-stage';
  var data:Dynamic;
  var events:QOLStageEventFile = {version: '1.0.0', events: []};

  var stageGroup:FlxTypedGroup<FlxSprite>;
  var propSprites:Array<Null<StageProp>> = [];
  var chars:Map<String, BaseCharacter> = new Map<String, BaseCharacter>();
  var previewChars:Dynamic;

  // Selection: a prop index, or a character key.
  var selectedProp:Int = -1;
  var selectedChar:Null<String> = null;
  var selectionBox:FlxSprite;
  var camFrame:FlxSprite;
  var camFrameKey:String = '';
  var camMarkers:Map<String, FlxSprite> = new Map<String, FlxSprite>();
  var infoText:FlxText;

  var stageForm:QOLForm;
  var charForm:QOLForm;
  var propList:ListView;
  var propForm:QOLForm;
  var animList:ListView;
  var animForm:QOLForm;
  var selectedPropAnim:Int = 0;
  var eventList:ListView;
  var eventForm:QOLForm;
  var stepList:ListView;
  var stepForm:QOLForm;
  var selectedEvent:Int = -1;
  var selectedStep:Int = -1;

  var camFocus:FlxPoint = FlxPoint.get(640, 400);
  var zoom:Float = 0.5;
  var parallax:Bool = false;
  var showCamera:Bool = true;
  var bopPreview:Bool = false;
  var bopTimer:Float = 0;
  var bopBeat:Int = 0;
  var dragMode:String = '';
  var dragLast:FlxPoint = FlxPoint.get();

  var player:Null<QOLStageEventPlayer> = null;
  var eventZoom:Float = 1;

  var undoStack:Array<String> = [];
  var redoStack:Array<String> = [];
  var lastSnapshot:String = '';
  var lastSnapshotTime:Float = 0;
  var time:Float = 0;

  public function new(?id:String)
  {
    super();
    editorName = 'Background Editor';
    leftPanelWidth = 320;
    rightPanelWidth = 360;
    if (id != null) stageId = id;
  }

  override function guidePage():String
    return 'stage';

  override function buildEditor():Void
  {
    data = defaultData();
    previewChars = QOLConfig.getPref('stageEditor.chars', {bf: 'bf', gf: 'gf', dad: 'dad'});

    stageGroup = new FlxTypedGroup<FlxSprite>();
    stageGroup.cameras = [camWorld];
    add(stageGroup);

    camFrame = new FlxSprite();
    camFrame.cameras = [camWorld];
    add(camFrame);

    selectionBox = new FlxSprite();
    selectionBox.cameras = [camWorld];
    selectionBox.visible = false;
    add(selectionBox);

    infoText = QOLTheme.text(leftPanelWidth + 12, QOLEditorState.MENUBAR_HEIGHT + 8, 520, '', 13, QOLTheme.FONT_MONO, 0xFFE8E0FF);
    infoText.setBorderStyle(OUTLINE, 0xFF000000, 1);
    infoText.cameras = [camUI];
    add(infoText);

    buildMenus();
    buildLeftPanel();
    buildRightPanel();

    var last:String = QOLConfig.getPref('stageEditor.last', null);
    loadStage(last ?? 'mainStage', true);
  }

  //
  // Menus & panels
  //

  function buildMenus()
  {
    var file = addMenu('File');
    addMenuItem(file, 'New Stage', 'Ctrl+N', newStage);
    addMenuItem(file, 'Open Stage...', 'Ctrl+O', () -> {
      var ids = StageRegistry.instance.listEntryIds();
      for (f in ModWorkspace.listRecursive('data/stages', ['json']))
      {
        var id = haxe.io.Path.withoutExtension(f);
        if (!ids.contains(id)) ids.push(id);
      }
      ids.sort((a, b) -> a.toLowerCase() < b.toLowerCase() ? -1 : 1);
      chooseFromList('Open stage', ids, id -> loadStage(id, false), stageId);
    });
    addMenuItem(file, 'Save', 'Ctrl+S', () -> doSave());
    addMenuItem(file, 'Save As New ID...', null, () -> prompt('Save as', 'New stage ID:', stageId, id -> {
      id = ModWorkspace.sanitizeFolderName(id);
      if (id == '') return;
      stageId = id;
      stageForm.refresh();
      doSave();
    }));

    var edit = addMenu('Edit');
    addMenuItem(edit, 'Undo', 'Ctrl+Z', undo);
    addMenuItem(edit, 'Redo', 'Ctrl+Y', redo);
    addMenuSeparator(edit);
    addMenuItem(edit, 'Duplicate Prop', 'Ctrl+D', duplicateProp);
    addMenuItem(edit, 'Delete Prop', 'Delete', deleteProp);

    var view = addMenu('View');
    addMenuCheck(view, 'Parallax (real scroll factors)', parallax, v -> {
      parallax = v;
      applyScrollFactors();
    });
    addMenuCheck(view, 'Show game camera frame', showCamera, v -> showCamera = v);
    addMenuCheck(view, 'Bop props & characters (100 BPM)', bopPreview, v -> bopPreview = v);
    addMenuItem(view, 'Reset Camera', 'R', resetCamera);
    addMenuItem(view, 'Reset Stage (undo event preview)', null, () -> rebuildAll());
  }

  function buildLeftPanel()
  {
    stageForm = new QOLForm(110, 170);
    stageForm.onAnyChange = () -> committed();
    stageForm.section('Stage');
    stageForm.textField('ID (file name)', () -> stageId, v -> stageId = v.trim());
    stageForm.textField('Display name', () -> data.name, v -> data.name = v);
    stageForm.number('Camera zoom', () -> data.cameraZoom ?? 1, v -> data.cameraZoom = v, 0.05, 10, 0.05, 2);
    stageForm.dropdown('Asset library', () -> ['shared', 'week1', 'week2', 'week3', 'week4', 'week5', 'week6', 'week7', 'weekend1', 'tutorial'],
      () -> data.directory ?? 'shared', v -> {
        data.directory = v;
        rebuildAll();
      });
    stageForm.note('Where the stage\'s images are. Your mod\'s images/ folder always works.');

    stageForm.section('Preview characters');
    for (key in CHAR_KEYS)
    {
      var k = key;
      stageForm.dropdown(k.toUpperCase(), () -> CharacterDataParser.listCharacterIds(), () -> Reflect.field(previewChars, k) ?? k, v -> {
        Reflect.setField(previewChars, k, v);
        QOLConfig.setPref('stageEditor.chars', previewChars);
        buildCharacter(k);
        sortStage();
      });
    }
    leftPanel.addComponent(stageForm);

    charForm = new QOLForm(110, 170);
    charForm.onAnyChange = () -> committed();
    charForm.section('Selected character');
    charForm.dropdown('Character', () -> CHAR_KEYS, () -> selectedChar ?? 'bf', v -> selectChar(v), () -> ['Boyfriend (player)', 'Girlfriend', 'Dad (opponent)']);
    charForm.pair('Position (feet)', () -> charArr('position')[0], v -> {
      charArr('position')[0] = v;
      placeCharacter(selectedChar);
    }, () -> charArr('position')[1], v -> {
      charArr('position')[1] = v;
      placeCharacter(selectedChar);
    });
    charForm.number('Z index', () -> charData()?.zIndex ?? 0, v -> {
      if (charData() == null) return;
      charData().zIndex = Std.int(v);
      placeCharacter(selectedChar);
      sortStage();
    }, -10000, 10000, 10, 0);
    charForm.number('Scale', () -> charData()?.scale ?? 1, v -> {
      if (charData() == null) return;
      charData().scale = v;
      placeCharacter(selectedChar);
    }, 0.05, 20, 0.05, 2);
    charForm.pair('Camera offset', () -> charArr('cameraOffsets')[0], v -> {
      charArr('cameraOffsets')[0] = v;
      placeCharacter(selectedChar);
    }, () -> charArr('cameraOffsets')[1], v -> {
      charArr('cameraOffsets')[1] = v;
      placeCharacter(selectedChar);
    });
    charForm.pair('Scroll factor', () -> charArr('scroll', 1)[0], v -> {
      charArr('scroll', 1)[0] = v;
      applyScrollFactors();
    }, () -> charArr('scroll', 1)[1], v -> {
      charArr('scroll', 1)[1] = v;
      applyScrollFactors();
    }, 0.05, 2);
    charForm.slider('Alpha', () -> charData()?.alpha ?? 1, v -> {
      if (charData() == null) return;
      charData().alpha = v;
      placeCharacter(selectedChar);
    }, 0, 1, 0.05);
    charForm.number('Angle', () -> charData()?.angle ?? 0, v -> {
      if (charData() == null) return;
      charData().angle = v;
      placeCharacter(selectedChar);
    }, -360, 360, 1, 1);
    charForm.note('Click a character to select it, drag to move. Drag the cross to move its camera point.');
    leftPanel.addComponent(charForm);
  }

  function buildRightPanel()
  {
    var tabs = new TabView();
    tabs.width = rightPanelWidth - 26;
    tabs.height = FlxG.height - QOLEditorState.MENUBAR_HEIGHT - QOLEditorState.STATUSBAR_HEIGHT - 26;
    rightPanel.addComponent(tabs);

    // Props tab.
    var propsPage = new VBox();
    propsPage.text = 'Props';
    propsPage.styleString = 'spacing: 5px; padding: 6px;';
    tabs.addComponent(propsPage);

    propList = new ListView();
    propList.width = rightPanelWidth - 50;
    propList.height = 150;
    propList.onChange = _ -> {
      if (propList.selectedIndex >= 0 && propList.selectedIndex != selectedProp) selectProp(propList.selectedIndex);
    };
    propsPage.addComponent(propList);
    var row = new HBox();
    row.styleString = 'spacing: 2px;';
    row.addComponent(btn('+ Image', () -> addProp('image')));
    row.addComponent(btn('+ Anim', () -> addProp('animated')));
    row.addComponent(btn('+ Color', () -> addProp('solid')));
    row.addComponent(btn('Copy', duplicateProp));
    row.addComponent(btn('Del', deleteProp));
    propsPage.addComponent(row);

    propForm = new QOLForm(96, 196);
    propForm.onAnyChange = () -> committed();
    propForm.textField('Name', () -> prop()?.name ?? '', v -> {
      if (prop() == null) return;
      for (e in events.events)
        for (s in e.steps)
          if (s.target == prop().name) s.target = v;
      prop().name = v;
      refreshPropList();
    });
    propForm.file('Image / color', () -> prop()?.assetPath ?? '', v -> {
      if (prop() == null) return;
      prop().assetPath = v;
      rebuildProp(selectedProp);
    }, cb -> browseModFile('Prop image', 'images', ['png'], cb));
    propForm.dropdown('Atlas type', () -> ['sparrow', 'packer', 'animateatlas'], () -> prop()?.animType ?? 'sparrow', v -> {
      if (prop() == null) return;
      prop().animType = v;
      rebuildProp(selectedProp);
    });
    propForm.pair('Position', () -> propArr('position')[0], v -> {
      propArr('position')[0] = v;
      placeProp(selectedProp);
    }, () -> propArr('position')[1], v -> {
      propArr('position')[1] = v;
      placeProp(selectedProp);
    });
    propForm.pair('Scale / size', () -> propArr('scale', 1)[0], v -> {
      propArr('scale', 1)[0] = v;
      rebuildProp(selectedProp);
    }, () -> propArr('scale', 1)[1], v -> {
      propArr('scale', 1)[1] = v;
      rebuildProp(selectedProp);
    }, 0.05, 2);
    propForm.pair('Scroll factor', () -> propArr('scroll', 1)[0], v -> {
      propArr('scroll', 1)[0] = v;
      applyScrollFactors();
    }, () -> propArr('scroll', 1)[1], v -> {
      propArr('scroll', 1)[1] = v;
      applyScrollFactors();
    }, 0.05, 2);
    propForm.number('Z index', () -> prop()?.zIndex ?? 0, v -> {
      if (prop() == null) return;
      prop().zIndex = Std.int(v);
      placeProp(selectedProp);
      sortStage();
      refreshPropList();
    }, -10000, 10000, 10, 0);
    propForm.slider('Alpha', () -> prop()?.alpha ?? 1, v -> {
      if (prop() == null) return;
      prop().alpha = v;
      placeProp(selectedProp);
    }, 0, 1, 0.05);
    propForm.number('Angle', () -> prop()?.angle ?? 0, v -> {
      if (prop() == null) return;
      prop().angle = v;
      placeProp(selectedProp);
    }, -360, 360, 1, 1);
    propForm.colorField('Tint', () -> {
      var c = FlxColor.fromString(prop()?.color ?? '#FFFFFF');
      return c == null ? FlxColor.WHITE : c;
    }, v -> {
      if (prop() == null) return;
      prop().color = '#' + StringTools.hex(v & 0xFFFFFF, 6);
      placeProp(selectedProp);
    });
    propForm.dropdown('Blend mode', () -> BLENDS, () -> (prop()?.blend ?? '') == '' ? 'normal' : prop().blend, v -> {
      if (prop() == null) return;
      prop().blend = v == 'normal' ? '' : v;
      placeProp(selectedProp);
    });
    propForm.check('Flip X', () -> prop()?.flipX == true, v -> {
      if (prop() == null) return;
      prop().flipX = v;
      placeProp(selectedProp);
    });
    propForm.check('Flip Y', () -> prop()?.flipY == true, v -> {
      if (prop() == null) return;
      prop().flipY = v;
      placeProp(selectedProp);
    });
    propForm.check('Pixel art', () -> prop()?.isPixel == true, v -> {
      if (prop() == null) return;
      prop().isPixel = v;
      placeProp(selectedProp);
    });
    propForm.number('Bop every (beats)', () -> prop()?.danceEvery ?? 0, v -> {
      if (prop() == null) return;
      prop().danceEvery = v;
      rebuildProp(selectedProp);
    }, 0, 16, 0.5, 1);
    propsPage.addComponent(propForm);

    var animTitle = new Label();
    animTitle.text = 'Prop animations';
    animTitle.styleString = 'font-bold: true; color: #FF8FB8;';
    propsPage.addComponent(animTitle);
    animList = new ListView();
    animList.width = rightPanelWidth - 50;
    animList.height = 70;
    animList.onChange = _ -> {
      if (animList.selectedIndex >= 0)
      {
        selectedPropAnim = animList.selectedIndex;
        animForm.refresh();
        var a = propAnim();
        var spr = propSprites[selectedProp];
        if (a != null && Std.isOfType(spr, Bopper)) (cast spr : Bopper).playAnimation(a.name, true);
      }
    };
    propsPage.addComponent(animList);
    var arow = new HBox();
    arow.addComponent(btn('+ Animation', addPropAnim));
    arow.addComponent(btn('Delete', () -> {
      var a = propAnim();
      if (a == null) return;
      changing();
      propAnims().remove(a);
      refreshAnimList();
      rebuildProp(selectedProp);
      committed();
    }));
    propsPage.addComponent(arow);
    animForm = new QOLForm(96, 196);
    animForm.onAnyChange = () -> committed();
    animForm.textField('Name', () -> propAnim()?.name ?? '', v -> {
      if (propAnim() == null) return;
      propAnim().name = v;
      refreshAnimList();
      rebuildPropSoon();
    });
    animForm.textField('Prefix', () -> propAnim()?.prefix ?? '', v -> {
      if (propAnim() == null) return;
      propAnim().prefix = v;
      rebuildPropSoon();
    });
    animForm.textField('Frame indices', () -> CharacterEditorState_indices(propAnim()?.frameIndices), v -> {
      if (propAnim() == null) return;
      propAnim().frameIndices = parseIndices(v);
      rebuildPropSoon();
    }, 'e.g. 0-5, 8 (empty = all)');
    animForm.number('Frame rate', () -> propAnim()?.frameRate ?? 24, v -> {
      if (propAnim() == null) return;
      propAnim().frameRate = Std.int(v);
      rebuildPropSoon();
    }, 1, 240, 1, 0);
    animForm.check('Loop', () -> propAnim()?.looped == true, v -> {
      if (propAnim() == null) return;
      propAnim().looped = v;
      rebuildPropSoon();
    });
    animForm.pair('Offsets', () -> animOffsets()[0], v -> {
      animOffsets()[0] = v;
      rebuildPropSoon();
    }, () -> animOffsets()[1], v -> {
      animOffsets()[1] = v;
      rebuildPropSoon();
    });
    animForm.dropdown('Starting anim', () -> [''].concat([for (a in propAnims()) a.name]), () -> prop()?.startingAnimation ?? '', v -> {
      if (prop() == null) return;
      prop().startingAnimation = v == '' ? null : v;
      rebuildPropSoon();
    });
    propsPage.addComponent(animForm);

    // Stage events tab.
    var eventsPage = new VBox();
    eventsPage.text = 'Stage Events';
    eventsPage.styleString = 'spacing: 5px; padding: 6px;';
    tabs.addComponent(eventsPage);

    var help = new Label();
    help.width = rightPanelWidth - 50;
    help.text = 'Stage events are little sequences (move props, play animations, flash, zoom...). Trigger them from a chart with the "Stage Event" event.';
    help.styleString = 'color: #C9C2E6; font-size: 11px;';
    eventsPage.addComponent(help);

    eventList = new ListView();
    eventList.width = rightPanelWidth - 50;
    eventList.height = 90;
    eventList.onChange = _ -> {
      if (eventList.selectedIndex != selectedEvent) selectEvent(eventList.selectedIndex);
    };
    eventsPage.addComponent(eventList);
    var erow = new HBox();
    erow.addComponent(btn('+ Event', addEvent));
    erow.addComponent(btn('Copy', duplicateEvent));
    erow.addComponent(btn('Delete', deleteEvent));
    erow.addComponent(btn('▶ Preview', previewEvent));
    eventsPage.addComponent(erow);

    eventForm = new QOLForm(96, 196);
    eventForm.onAnyChange = () -> committed();
    eventForm.textField('Event ID', () -> ev()?.id ?? '', v -> if (ev() != null) {
      ev().id = ModWorkspace.sanitizeFolderName(v);
      refreshEventList();
    });
    eventForm.textField('Name', () -> ev()?.name ?? '', v -> if (ev() != null) {
      ev().name = v;
      refreshEventList();
    });
    eventForm.dropdown('Time unit', () -> QOLStageEvents.TIME_UNITS, () -> ev()?.timeUnit ?? 'seconds', v -> if (ev() != null) ev().timeUnit = v);
    eventsPage.addComponent(eventForm);

    var stepsTitle = new Label();
    stepsTitle.text = 'Steps';
    stepsTitle.styleString = 'font-bold: true; color: #FF8FB8;';
    eventsPage.addComponent(stepsTitle);
    stepList = new ListView();
    stepList.width = rightPanelWidth - 50;
    stepList.height = 120;
    stepList.onChange = _ -> {
      if (stepList.selectedIndex != selectedStep)
      {
        selectedStep = stepList.selectedIndex;
        stepForm.refresh();
      }
    };
    eventsPage.addComponent(stepList);
    var srow = new HBox();
    srow.addComponent(btn('+ Step', addStep));
    srow.addComponent(btn('Copy', duplicateStep));
    srow.addComponent(btn('Delete', deleteStep));
    srow.addComponent(btn('Use current', stepFromCurrent));
    eventsPage.addComponent(srow);

    stepForm = new QOLForm(96, 196);
    stepForm.onAnyChange = () -> {
      refreshStepList();
      committed();
    };
    stepForm.number('Time', () -> step()?.time ?? 0, v -> if (step() != null) step().time = v, 0, 9999, 0.25, 2);
    stepForm.dropdown('Action', () -> QOLStageEvents.STEP_TYPES, () -> step()?.type ?? 'tween', v -> if (step() != null) step().type = v,
      () -> QOLStageEvents.STEP_TYPE_NAMES);
    stepForm.dropdown('Target', targetNames, () -> step()?.target ?? '', v -> if (step() != null) step().target = v);
    stepForm.dropdown('Property', () -> QOLStageEvents.PROPS, () -> step()?.prop ?? 'x', v -> if (step() != null) step().prop = v);
    stepForm.number('Value', () -> step()?.value ?? 0, v -> if (step() != null) step().value = v, -99999, 99999, 1, 2);
    stepForm.check('Relative (+=)', () -> step()?.relative == true, v -> if (step() != null) step().relative = v);
    stepForm.number('Duration', () -> step()?.duration ?? 1, v -> if (step() != null) step().duration = v, 0, 999, 0.25, 2);
    stepForm.ease('Ease', () -> step()?.ease ?? 'linear', v -> if (step() != null) step().ease = v);
    stepForm.textField('Animation', () -> step()?.anim ?? '', v -> if (step() != null) step().anim = v);
    stepForm.file('Sound', () -> step()?.sound ?? '', v -> if (step() != null) step().sound = v,
      cb -> browseModFile('Sound', 'sounds', ['ogg', 'mp3'], cb));
    stepForm.colorField('Color', () -> {
      var c = FlxColor.fromString(step()?.color ?? '#FFFFFF');
      return c == null ? FlxColor.WHITE : c;
    }, v -> if (step() != null) step().color = '#' + StringTools.hex(v & 0xFFFFFF, 6));
    stepForm.number('Shake amount', () -> step()?.intensity ?? 0.01, v -> if (step() != null) step().intensity = v, 0, 1, 0.005, 3);
    stepForm.note('"Use current" fills Value with the selected prop\'s current position/alpha/etc.\nZoom value is a multiplier of the stage zoom.');
    eventsPage.addComponent(stepForm);
  }

  function btn(text:String, cb:Void->Void):Button
  {
    var b = new Button();
    b.text = text;
    b.onClick = _ -> cb();
    return b;
  }

  //
  // Data helpers
  //

  function defaultData():Dynamic
  {
    return {
      version: StageRegistry.STAGE_DATA_VERSION.toString(),
      name: 'My Stage',
      cameraZoom: 1.0,
      directory: 'shared',
      props: [],
      characters: {
        bf: {zIndex: 300, position: [989.5, 885], cameraOffsets: [-100, -100]},
        dad: {zIndex: 200, position: [335, 885], cameraOffsets: [150, -100]},
        gf: {zIndex: 100, position: [751.5, 787], cameraOffsets: [0, 0]}
      }
    };
  }

  function props():Array<Dynamic>
  {
    if (data.props == null) data.props = [];
    return data.props;
  }

  function prop():Null<Dynamic>
  {
    var list = props();
    return selectedProp >= 0 && selectedProp < list.length ? list[selectedProp] : null;
  }

  static function ensureArr(obj:Dynamic, field:String, def:Float):Array<Float>
  {
    if (obj == null) return [def, def];
    var v:Dynamic = Reflect.field(obj, field);
    if (v == null)
    {
      v = [def, def];
      Reflect.setField(obj, field, v);
    }
    else if (!Std.isOfType(v, Array))
    {
      // Scale can be a single number in V-Slice stage files.
      var n:Float = v;
      v = [n, n];
      Reflect.setField(obj, field, v);
    }
    var arr:Array<Float> = v;
    while (arr.length < 2)
      arr.push(def);
    return arr;
  }

  function propArr(field:String, def:Float = 0):Array<Float>
    return ensureArr(prop(), field, def);

  function propAnims():Array<Dynamic>
  {
    var p = prop();
    if (p == null) return [];
    if (p.animations == null) p.animations = [];
    return p.animations;
  }

  function propAnim():Null<Dynamic>
  {
    var list = propAnims();
    return selectedPropAnim >= 0 && selectedPropAnim < list.length ? list[selectedPropAnim] : null;
  }

  function animOffsets():Array<Float>
    return ensureArr(propAnim(), 'offsets', 0);

  function charData(?key:String):Null<Dynamic>
  {
    key = key ?? selectedChar;
    if (key == null) return null;
    if (data.characters == null) data.characters = defaultData().characters;
    var c:Dynamic = Reflect.field(data.characters, key);
    if (c == null)
    {
      c = Reflect.field(defaultData().characters, key);
      Reflect.setField(data.characters, key, c);
    }
    return c;
  }

  function charArr(field:String, def:Float = 0):Array<Float>
    return ensureArr(charData(), field, def);

  function ev():Null<QOLStageEvent>
    return selectedEvent >= 0 && selectedEvent < events.events.length ? events.events[selectedEvent] : null;

  function step():Null<QOLStageEventStep>
  {
    var e = ev();
    return e != null && selectedStep >= 0 && selectedStep < e.steps.length ? e.steps[selectedStep] : null;
  }

  function targetNames():Array<String>
  {
    var names = ['bf', 'gf', 'dad', 'camera'];
    for (p in props())
      if (p.name != null && p.name != '' && !names.contains(p.name)) names.push(p.name);
    return names;
  }

  static function CharacterEditorState_indices(indices:Array<Int>):String
  {
    if (indices == null || indices.length == 0) return '';
    return indices.join(', ');
  }

  static function parseIndices(text:String):Array<Int>
  {
    var result:Array<Int> = [];
    for (part in text.split(','))
    {
      part = part.trim();
      var dash = part.indexOf('-', 1);
      if (dash > 0)
      {
        var a = Std.parseInt(part.substr(0, dash));
        var b = Std.parseInt(part.substr(dash + 1));
        if (a != null && b != null && a <= b) for (n in a...b + 1)
          result.push(n);
      }
      else
      {
        var n = Std.parseInt(part);
        if (n != null) result.push(n);
      }
    }
    return result;
  }

  //
  // Loading
  //

  function newStage()
  {
    prompt('New stage', 'ID for the new stage:', 'my-stage', id -> {
      id = ModWorkspace.sanitizeFolderName(id);
      if (id == '') return;
      stageId = id;
      data = defaultData();
      events = {version: '1.0.0', events: []};
      afterLoad();
      dirty = true;
    });
  }

  function loadStage(id:String, startup:Bool)
  {
    var raw:Dynamic = ModWorkspace.hasMod ? ModWorkspace.getJson('data/stages/$id.json') : null;
    if (raw == null)
    {
      var path = Paths.json('stages/$id');
      if (Assets.exists(path)) raw = QOLJson.tryParse(Assets.getText(path));
    }
    if (raw == null)
    {
      if (!startup) alert('Not found', 'Could not find a stage called "$id".');
      raw = defaultData();
    }
    stageId = id;
    data = raw;
    var evRaw:Dynamic = ModWorkspace.hasMod ? ModWorkspace.getJson('data/qol/stage-events/$id.json') : null;
    events = evRaw != null ? evRaw : (QOLStageEvents.load(id) ?? {version: '1.0.0', events: []});
    if (events.events == null) events.events = [];
    afterLoad();
  }

  function afterLoad()
  {
    selectedProp = -1;
    selectedChar = 'bf';
    selectedEvent = events.events.length > 0 ? 0 : -1;
    selectedStep = -1;
    undoStack = [];
    redoStack = [];
    lastSnapshot = snapshot();
    QOLConfig.setPref('stageEditor.last', stageId);
    rebuildAll();
    stageForm.refresh();
    charForm.refresh();
    refreshPropList();
    propForm.refresh();
    refreshEventList();
    eventForm.refresh();
    refreshStepList();
    stepForm.refresh();
    resetCamera();
    dirty = false;
  }

  //
  // Building the scene
  //

  function rebuildAll()
  {
    player?.cancel();
    player = null;
    eventZoom = 1;
    QOLAssets.withLibrary(data.directory, () -> {
      Paths.setCurrentLevel(data.directory);
      for (spr in propSprites)
        if (spr != null)
        {
          stageGroup.remove(spr, true);
          spr.destroy();
        }
      propSprites = [];
      for (i in 0...props().length)
        propSprites.push(null);
      for (i in 0...props().length)
        rebuildProp(i);
      for (key in CHAR_KEYS)
        buildCharacter(key);
      sortStage();
      refreshAnimList();
    });
  }

  var propRebuildTimer:Float = -1;

  function rebuildPropSoon()
    propRebuildTimer = 0.4;

  function rebuildProp(index:Int)
  {
    propRebuildTimer = -1;
    if (index < 0 || index >= props().length) return;
    var old = propSprites[index];
    if (old != null)
    {
      stageGroup.remove(old, true);
      old.destroy();
    }
    var spr = buildPropSprite(props()[index]);
    propSprites[index] = spr;
    if (spr != null)
    {
      stageGroup.add(spr);
      placeProp(index);
      sortStage();
    }
  }

  /**
   * Builds a prop exactly like the game's Stage class does.
   */
  function buildPropSprite(p:Dynamic):Null<StageProp>
  {
    try
    {
      var assetPath:String = p.assetPath ?? '';
      var anims:Array<Dynamic> = p.animations ?? [];
      var isSolid = assetPath.startsWith('#');
      var isAnimated = anims.length > 0;
      var danceEvery:Float = p.danceEvery ?? 0;
      var spr:StageProp = (danceEvery != 0 || isAnimated) ? new Bopper(danceEvery) : new StageProp();
      var scale = ensureArr(p, 'scale', 1);
      if (isAnimated)
      {
        switch (p.animType)
        {
          case 'packer':
            spr.loadPacker(assetPath);
          case 'animateatlas':
            spr.loadTextureAtlas(assetPath, data.directory, cast p.atlasSettings);
          default:
            spr.loadSparrow(assetPath);
        }
      }
      else if (isSolid)
      {
        spr.makeSolidColor(Std.int(Math.max(1, scale[0])), Std.int(Math.max(1, scale[1])), FlxColor.fromString(assetPath) ?? FlxColor.WHITE);
      }
      else
      {
        spr.loadTexture(assetPath);
      }
      if (!spr.isAnimate && (spr.frames == null || spr.frames.numFrames == 0)) throw 'Could not load "$assetPath"';
      if (!isSolid) spr.scale.set(scale[0], scale[1]);
      spr.updateHitbox();

      switch (p.animType)
      {
        case 'packer':
          for (a in anims)
            {
              var raw:Null<Array<Int>> = a.frameIndices;
              var indices:Array<Int> = raw == null ? [] : raw;
              spr.animation.add(a.name, indices, a.frameRate ?? 24, a.looped == true);
            }
        case 'animateatlas':
          FlxAnimationUtil.addTextureAtlasAnimations(spr, cast anims);
        default:
          FlxAnimationUtil.addAtlasAnimations(spr, cast anims);
      }
      if (Std.isOfType(spr, Bopper))
      {
        var b:Bopper = cast spr;
        for (a in anims)
        {
          var o = ensureArr(a, 'offsets', 0);
          b.setAnimationOffsets(a.name, o[0], o[1]);
        }
        if (p.startingAnimation != null) b.playAnimation(p.startingAnimation);
        else if (anims.length > 0) b.playAnimation(anims[0].name);
      }
      spr.name = p.name ?? '';
      return spr;
    }
    catch (e)
    {
      setStatus('Prop "${p.name}" failed: $e');
      return null;
    }
  }

  function placeProp(index:Int)
  {
    if (index < 0 || index >= props().length) return;
    var spr = propSprites[index];
    if (spr == null) return;
    var p = props()[index];
    var pos = ensureArr(p, 'position', 0);
    spr.setPosition(pos[0], pos[1]);
    if (Std.isOfType(spr, Bopper)) (cast spr : Bopper).originalPosition.set(pos[0], pos[1]);
    spr.alpha = p.alpha ?? 1;
    spr.angle = p.angle ?? 0;
    spr.flipX = p.flipX == true;
    spr.flipY = p.flipY == true;
    spr.antialiasing = p.isPixel != true;
    spr.zIndex = p.zIndex ?? 0;
    if (!(p.assetPath ?? '').startsWith('#'))
    {
      var c = FlxColor.fromString(p.color ?? '#FFFFFF');
      spr.color = c == null ? FlxColor.WHITE : c;
    }
    @:privateAccess spr.blend = BlendMode.fromString((p.blend ?? '') == '' ? 'normal' : p.blend);
    var sc = ensureArr(p, 'scroll', 1);
    spr.scrollFactor.set(parallax ? sc[0] : 1, parallax ? sc[1] : 1);
  }

  function buildCharacter(key:String)
  {
    var old = chars.get(key);
    if (old != null)
    {
      stageGroup.remove(old, true);
      old.destroy();
      chars.remove(key);
    }
    var id:String = Reflect.field(previewChars, key) ?? key;
    try
    {
      var c = CharacterDataParser.fetchCharacter(id, true);
      if (c == null) return;
      c.cameras = [camWorld];
      chars.set(key, c);
      stageGroup.add(c);
      placeCharacter(key);
    }
    catch (e)
    {
      setStatus('Could not load character "$id": $e');
    }
    if (!camMarkers.exists(key))
    {
      var m = new FlxSprite().loadGraphic(flixel.graphics.FlxGraphic.fromClass(funkin.ui.debug.GraphicCursorCross));
      m.setGraphicSize(110, 110);
      m.updateHitbox();
      m.cameras = [camWorld];
      m.color = switch (key)
      {
        case 'bf': 0xFF31B0FF;
        case 'dad': 0xFFFF5C9D;
        default: 0xFFFFD84A;
      };
      camMarkers.set(key, m);
      add(m);
    }
  }

  function placeCharacter(key:Null<String>)
  {
    if (key == null) return;
    var c = chars.get(key);
    var cd = charData(key);
    if (c == null || cd == null) return;
    c.flipX = key == 'bf' ? !c.getDataFlipX() : c.getDataFlipX();
    c.resetCharacter(true);
    var pos = ensureArr(cd, 'position', 0);
    c.x = pos[0] - c.characterOrigin.x;
    c.y = pos[1] - c.characterOrigin.y;
    c.setScale(c.getBaseScale() * (cd.scale ?? 1));
    c.originalPosition.set(c.x, c.y);
    c.resetCameraFocusPoint();
    var cam = ensureArr(cd, 'cameraOffsets', 0);
    c.cameraFocusPoint.x += cam[0];
    c.cameraFocusPoint.y += cam[1];
    c.alpha = cd.alpha ?? 1;
    c.angle = cd.angle ?? 0;
    c.zIndex = cd.zIndex ?? 0;
    var sc = ensureArr(cd, 'scroll', 1);
    c.scrollFactor.set(parallax ? sc[0] : 1, parallax ? sc[1] : 1);
    var m = camMarkers.get(key);
    if (m != null) m.setPosition(c.cameraFocusPoint.x - m.width / 2, c.cameraFocusPoint.y - m.height / 2);
  }

  function applyScrollFactors()
  {
    for (i in 0...props().length)
      placeProp(i);
    for (key in CHAR_KEYS)
      placeCharacter(key);
  }

  function sortStage()
  {
    stageGroup.sort(SortUtil.byZIndex, FlxSort.ASCENDING);
  }

  //
  // Lists & selection
  //

  function refreshPropList()
  {
    var ds = new ArrayDataSource<Dynamic>();
    for (p in props())
      ds.add({text: '${p.name ?? '(unnamed)'}   z${p.zIndex ?? 0}   ${p.assetPath}'});
    propList.dataSource = ds;
    if (selectedProp >= 0) propList.selectedIndex = selectedProp;
  }

  function refreshAnimList()
  {
    var ds = new ArrayDataSource<Dynamic>();
    for (a in propAnims())
      ds.add({text: '${a.name}  ·  ${a.prefix ?? ''}'});
    animList.dataSource = ds;
    if (selectedPropAnim >= 0 && selectedPropAnim < propAnims().length) animList.selectedIndex = selectedPropAnim;
    animForm.refresh();
  }

  function selectProp(index:Int)
  {
    selectedProp = index;
    selectedChar = null;
    selectedPropAnim = 0;
    if (propList.selectedIndex != index) propList.selectedIndex = index;
    propForm.refresh();
    refreshAnimList();
  }

  function selectChar(key:String)
  {
    selectedChar = key;
    selectedProp = -1;
    propList.selectedIndex = -1;
    charForm.refresh();
  }

  function addProp(kind:String)
  {
    changing();
    var center = camFocus;
    var p:Dynamic = {
      name: '$kind${props().length + 1}',
      assetPath: kind == 'solid' ? '#3A2E6E' : 'menuDesat',
      position: [Math.round(center.x - 200), Math.round(center.y - 150)],
      zIndex: 50,
      scale: kind == 'solid' ? [400, 300] : [1, 1],
      scroll: [1, 1],
      alpha: 1,
      animType: 'sparrow',
      animations: [],
      danceEvery: 0,
      isPixel: false
    };
    if (kind == 'animated')
    {
      p.assetPath = 'characters/BOYFRIEND';
      p.animations = [{name: 'idle', prefix: 'BF idle dance', frameRate: 24, looped: true, offsets: [0, 0]}];
      p.danceEvery = 0;
    }
    props().push(p);
    propSprites.push(null);
    rebuildProp(props().length - 1);
    selectProp(props().length - 1);
    refreshPropList();
    committed();
    if (kind != 'solid') browseModFile('Choose an image for the prop', 'images', ['png'], key -> {
      changing();
      p.assetPath = key;
      rebuildProp(props().indexOf(p));
      propForm.refresh();
      refreshPropList();
      committed();
    });
  }

  function duplicateProp()
  {
    var p = prop();
    if (p == null) return;
    changing();
    var copy:Dynamic = QOLJson.clone(p);
    copy.name = p.name + '-copy';
    var pos = ensureArr(copy, 'position', 0);
    pos[0] += 40;
    pos[1] += 40;
    props().push(copy);
    propSprites.push(null);
    rebuildProp(props().length - 1);
    selectProp(props().length - 1);
    refreshPropList();
    committed();
  }

  function deleteProp()
  {
    var p = prop();
    if (p == null) return;
    changing();
    var index = selectedProp;
    var spr = propSprites[index];
    if (spr != null)
    {
      stageGroup.remove(spr, true);
      spr.destroy();
    }
    propSprites.splice(index, 1);
    props().splice(index, 1);
    selectedProp = -1;
    refreshPropList();
    propForm.refresh();
    committed();
  }

  function addPropAnim()
  {
    var p = prop();
    if (p == null) return;
    changing();
    propAnims().push({
      name: propAnims().length == 0 ? 'idle' : 'anim${propAnims().length + 1}',
      prefix: '',
      frameRate: 24,
      looped: false,
      offsets: [0, 0]
    });
    selectedPropAnim = propAnims().length - 1;
    refreshAnimList();
    rebuildProp(selectedProp);
    committed();
  }

  // Events.

  function refreshEventList()
  {
    var ds = new ArrayDataSource<Dynamic>();
    for (e in events.events)
      ds.add({text: '${e.name}   (${e.id})'});
    eventList.dataSource = ds;
    if (selectedEvent >= 0) eventList.selectedIndex = selectedEvent;
  }

  function refreshStepList()
  {
    var ds = new ArrayDataSource<Dynamic>();
    var e = ev();
    if (e != null) for (s in e.steps)
      ds.add({text: '@${s.time}  ${s.type} ${s.target ?? ''} ${s.type == 'tween' || s.type == 'set' ? '${s.prop} → ${s.value}' : ''}'});
    stepList.dataSource = ds;
    if (selectedStep >= 0) stepList.selectedIndex = selectedStep;
  }

  function selectEvent(index:Int)
  {
    selectedEvent = index;
    selectedStep = -1;
    if (eventList.selectedIndex != index) eventList.selectedIndex = index;
    eventForm.refresh();
    refreshStepList();
    stepForm.refresh();
  }

  function addEvent()
  {
    changing();
    var n = events.events.length + 1;
    events.events.push({
      id: 'event$n',
      name: 'Event $n',
      timeUnit: 'beats',
      steps: []
    });
    refreshEventList();
    selectEvent(events.events.length - 1);
    committed();
  }

  function duplicateEvent()
  {
    var e = ev();
    if (e == null) return;
    changing();
    var copy:QOLStageEvent = QOLJson.clone(e);
    copy.id += '-copy';
    copy.name += ' (copy)';
    events.events.push(copy);
    refreshEventList();
    selectEvent(events.events.length - 1);
    committed();
  }

  function deleteEvent()
  {
    var e = ev();
    if (e == null) return;
    changing();
    events.events.remove(e);
    selectedEvent = -1;
    refreshEventList();
    eventForm.refresh();
    refreshStepList();
    committed();
  }

  function addStep()
  {
    var e = ev();
    if (e == null)
    {
      addEvent();
      e = ev();
    }
    changing();
    var target = prop()?.name ?? 'bf';
    e.steps.push({
      time: e.steps.length > 0 ? e.steps[e.steps.length - 1].time + 1 : 0,
      type: 'tween',
      target: target,
      prop: 'x',
      value: 100,
      relative: true,
      duration: 1,
      ease: 'quadInOut'
    });
    selectedStep = e.steps.length - 1;
    refreshStepList();
    stepForm.refresh();
    committed();
  }

  function duplicateStep()
  {
    var e = ev();
    var s = step();
    if (e == null || s == null) return;
    changing();
    var copy:QOLStageEventStep = QOLJson.clone(s);
    copy.time += 1;
    e.steps.push(copy);
    selectedStep = e.steps.length - 1;
    refreshStepList();
    stepForm.refresh();
    committed();
  }

  function deleteStep()
  {
    var e = ev();
    var s = step();
    if (e == null || s == null) return;
    changing();
    e.steps.remove(s);
    selectedStep = -1;
    refreshStepList();
    stepForm.refresh();
    committed();
  }

  /**
   * Fill a step's value from the target's current state (handy after dragging a prop where you want it to end up).
   */
  function stepFromCurrent()
  {
    var s = step();
    if (s == null) return;
    var target = resolveTarget(s.target ?? '');
    if (target == null || !Std.isOfType(target, FlxSprite)) return;
    var spr:FlxSprite = cast target;
    changing();
    s.relative = false;
    s.value = switch (s.prop)
    {
      case 'y': spr.y;
      case 'alpha': spr.alpha;
      case 'angle': spr.angle;
      case 'scale' | 'scaleX': spr.scale.x;
      case 'scaleY': spr.scale.y;
      default: spr.x;
    };
    stepForm.refresh();
    refreshStepList();
    committed();
  }

  function resolveTarget(name:String):Null<FlxBasic>
  {
    if (chars.exists(name)) return chars.get(name);
    if (name == 'camera' || name == 'hud') return camWorld;
    for (i in 0...props().length)
      if (props()[i].name == name) return propSprites[i];
    return null;
  }

  function previewEvent()
  {
    var e = ev();
    if (e == null) return;
    rebuildAll();
    // Wait a frame so the rebuilt stage exists before the event starts.
    haxe.ui.Toolkit.callLater(() -> {
      player = new QOLStageEventPlayer(e, resolveTarget, 60000 / 100 / 4, (z, d, ease) -> {
        flixel.tweens.FlxTween.num(eventZoom, z, d, {ease: ease}, v -> eventZoom = v);
      });
      setStatus('Previewing "${e.name}" at 100 BPM. View > Reset Stage puts everything back.');
    });
  }

  //
  // Undo
  //

  function snapshot():String
    return haxe.Json.stringify({d: data, e: events});

  function changing()
  {
    if (snapshot() != lastSnapshot) committed();
  }

  function committed()
  {
    var now = snapshot();
    if (now == lastSnapshot) return;
    undoStack.push(lastSnapshot);
    if (undoStack.length > MAX_UNDO) undoStack.shift();
    redoStack = [];
    lastSnapshot = now;
    lastSnapshotTime = time;
    dirty = true;
  }

  function undo()
  {
    if (undoStack.length == 0) return;
    redoStack.push(snapshot());
    restore(undoStack.pop());
  }

  function redo()
  {
    if (redoStack.length == 0) return;
    undoStack.push(snapshot());
    restore(redoStack.pop());
  }

  function restore(snap:String)
  {
    var parsed:Dynamic = haxe.Json.parse(snap);
    data = parsed.d;
    events = parsed.e;
    lastSnapshot = snap;
    rebuildAll();
    refreshPropList();
    propForm.refresh();
    charForm.refresh();
    stageForm.refresh();
    refreshEventList();
    eventForm.refresh();
    refreshStepList();
    stepForm.refresh();
    dirty = true;
  }

  //
  // Saving
  //

  override function save():Bool
  {
    if (stageId == null || stageId.trim() == '')
    {
      alert('No ID', 'Give the stage an ID first.');
      return false;
    }
    data.version = StageRegistry.STAGE_DATA_VERSION.toString();
    var path = ModWorkspace.saveJson('data/stages/$stageId.json', data, [
      'version', 'name', 'cameraZoom', 'directory', 'props', 'characters', 'name', 'assetPath', 'position', 'zIndex', 'scale', 'scroll'
    ]);
    if (events.events.length > 0) ModWorkspace.saveJson('data/qol/stage-events/$stageId.json', events, ['version', 'events', 'id', 'name', 'timeUnit', 'steps']);
    else if (ModWorkspace.exists('data/qol/stage-events/$stageId.json')) ModWorkspace.delete('data/qol/stage-events/$stageId.json');
    QOLConfig.setPref('stageEditor.last', stageId);
    notifySaved(path);
    return true;
  }

  override function afterSaveReload():Void
  {
    var keep = snapshot();
    ModWorkspace.reloadGameData();
    var parsed:Dynamic = haxe.Json.parse(keep);
    data = parsed.d;
    events = parsed.e;
    rebuildAll();
  }

  //
  // Camera, input & update
  //

  function viewportCenterX():Float
    return leftPanelWidth + (FlxG.width - leftPanelWidth - rightPanelWidth) / 2;

  function resetCamera()
  {
    zoom = 0.45;
    var c = chars.get('gf') ?? chars.get('bf');
    if (c != null) camFocus.set(c.cameraFocusPoint.x, c.cameraFocusPoint.y);
    else
      camFocus.set(640, 400);
  }

  function selectedSprite():Null<FlxSprite>
  {
    if (selectedChar != null) return chars.get(selectedChar);
    if (selectedProp >= 0 && selectedProp < propSprites.length) return propSprites[selectedProp];
    return null;
  }

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);
    time += elapsed;

    if (propRebuildTimer > 0)
    {
      propRebuildTimer -= elapsed;
      if (propRebuildTimer <= 0) rebuildProp(selectedProp);
    }

    camWorld.zoom = zoom;
    var shiftX = (FlxG.width / 2 - viewportCenterX()) / zoom;
    camWorld.scroll.set(camFocus.x + shiftX - FlxG.width / 2, camFocus.y - FlxG.height / 2);

    if (player != null)
    {
      player.update(elapsed);
      if (player.finished) player = null;
    }

    if (bopPreview)
    {
      bopTimer += elapsed;
      if (bopTimer >= 0.6)
      {
        bopTimer -= 0.6;
        bopBeat++;
        for (s in propSprites)
          if (Std.isOfType(s, Bopper)) (cast s : Bopper).onBeatHit(new funkin.modding.events.ScriptEvent.SongTimeScriptEvent(SONG_BEAT_HIT, bopBeat, bopBeat * 4));
        for (c in chars)
          c.dance();
      }
    }

    updateOverlays();
    handleMouse();
    updateInfo();
  }

  function updateOverlays()
  {
    // Game camera frame: what the player sees, centered on the selected character's camera.
    var focusChar = chars.get(selectedChar ?? 'dad') ?? chars.get('dad');
    camFrame.visible = showCamera && focusChar != null;
    if (camFrame.visible)
    {
      var z = (data.cameraZoom ?? 1) * eventZoom;
      var w = Std.int(FlxG.width / z);
      var h = Std.int(FlxG.height / z);
      var key = 'qol-camframe-$w-$h';
      if (camFrameKey != key)
      {
        camFrameKey = key;
        camFrame.loadGraphic(QOLTheme.cached(key, () -> {
          var bmp = new openfl.display.BitmapData(w, h, true, 0);
          var t = Std.int(Math.max(3, 4 / zoom));
          bmp.fillRect(new openfl.geom.Rectangle(0, 0, w, t), 0xC0FFD84A);
          bmp.fillRect(new openfl.geom.Rectangle(0, h - t, w, t), 0xC0FFD84A);
          bmp.fillRect(new openfl.geom.Rectangle(0, 0, t, h), 0xC0FFD84A);
          bmp.fillRect(new openfl.geom.Rectangle(w - t, 0, t, h), 0xC0FFD84A);
          return bmp;
        }));
      }
      camFrame.setPosition(focusChar.cameraFocusPoint.x - w / 2, focusChar.cameraFocusPoint.y - h / 2);
    }

    // Selection box.
    var sel = selectedSprite();
    selectionBox.visible = sel != null;
    if (sel != null)
    {
      var w = Std.int(Math.max(4, sel.width));
      var h = Std.int(Math.max(4, sel.height));
      var key = 'qol-selbox-$w-$h';
      if (selectionBox.graphic == null || selectionBox.graphic.key != key) selectionBox.loadGraphic(QOLTheme.cached(key, () -> {
        var bmp = new openfl.display.BitmapData(w, h, true, 0);
        var t = 4;
        for (r in [
          new openfl.geom.Rectangle(0, 0, w, t),
          new openfl.geom.Rectangle(0, h - t, w, t),
          new openfl.geom.Rectangle(0, 0, t, h),
          new openfl.geom.Rectangle(w - t, 0, t, h)
        ])
          bmp.fillRect(r, 0xFF5CE1FF);
        return bmp;
      }));
      selectionBox.setPosition(sel.x, sel.y);
      selectionBox.scrollFactor.set(sel.scrollFactor.x, sel.scrollFactor.y);
    }
  }

  function handleMouse()
  {
    var overUI = mouseOverUI || dialogOpen;
    if (!overUI && FlxG.mouse.wheel != 0) zoom = Math.max(0.05, Math.min(4, zoom * (FlxG.mouse.wheel > 0 ? 1.1 : 0.9)));

    if (dragMode == '' && !overUI)
    {
      if (FlxG.mouse.justPressedRight || FlxG.mouse.justPressedMiddle) dragMode = 'pan';
      else if (FlxG.mouse.justPressed)
      {
        // Camera markers first, then the topmost sprite under the mouse.
        for (key => m in camMarkers)
          if (FlxG.mouse.overlaps(m, camWorld))
          {
            selectChar(key);
            dragMode = 'camera';
            break;
          }
        if (dragMode == '')
        {
          var picked = false;
          var i = stageGroup.members.length - 1;
          while (i >= 0)
          {
            var spr = stageGroup.members[i];
            i--;
            if (spr == null || !spr.visible || !FlxG.mouse.overlaps(spr, camWorld)) continue;
            for (key => c in chars)
              if (c == spr)
              {
                selectChar(key);
                picked = true;
              }
            if (!picked)
            {
              var index = propSprites.indexOf(cast spr);
              if (index >= 0)
              {
                selectProp(index);
                picked = true;
              }
            }
            if (picked) break;
          }
          if (picked) dragMode = 'move';
        }
        if (dragMode != '') changing();
      }
      dragLast.set(FlxG.mouse.viewX, FlxG.mouse.viewY);
    }

    if (dragMode != '')
    {
      var dx = (FlxG.mouse.viewX - dragLast.x) / zoom;
      var dy = (FlxG.mouse.viewY - dragLast.y) / zoom;
      dragLast.set(FlxG.mouse.viewX, FlxG.mouse.viewY);
      switch (dragMode)
      {
        case 'pan':
          camFocus.x -= dx;
          camFocus.y -= dy;
          if (!FlxG.mouse.pressedRight && !FlxG.mouse.pressedMiddle) dragMode = '';
        case 'camera':
          var o = charArr('cameraOffsets');
          o[0] += dx;
          o[1] += dy;
          placeCharacter(selectedChar);
          if (!FlxG.mouse.pressed) finishDrag(o);
        case 'move':
          var arr = selectedChar != null ? charArr('position') : propArr('position');
          arr[0] += dx;
          arr[1] += dy;
          if (selectedChar != null) placeCharacter(selectedChar);
          else
            placeProp(selectedProp);
          if (!FlxG.mouse.pressed) finishDrag(arr);
      }
    }
  }

  function finishDrag(arr:Array<Float>)
  {
    arr[0] = Math.round(arr[0]);
    arr[1] = Math.round(arr[1]);
    if (selectedChar != null) placeCharacter(selectedChar);
    else
      placeProp(selectedProp);
    charForm.refresh();
    propForm.refresh();
    committed();
    dragMode = '';
  }

  override function handleShortcuts():Void
  {
    if (ctrl())
    {
      if (FlxG.keys.justPressed.Z) undo();
      if (FlxG.keys.justPressed.Y) redo();
      if (FlxG.keys.justPressed.D) duplicateProp();
      if (FlxG.keys.justPressed.N) newStage();
      return;
    }
    if (FlxG.keys.justPressed.DELETE) deleteProp();
    if (FlxG.keys.justPressed.R) resetCamera();
    var step = FlxG.keys.pressed.SHIFT ? 10 : 1;
    var dx = 0;
    var dy = 0;
    if (FlxG.keys.justPressed.LEFT) dx -= step;
    if (FlxG.keys.justPressed.RIGHT) dx += step;
    if (FlxG.keys.justPressed.UP) dy -= step;
    if (FlxG.keys.justPressed.DOWN) dy += step;
    if (dx != 0 || dy != 0)
    {
      if (time - lastSnapshotTime > 0.6) changing();
      var arr = selectedChar != null ? charArr('position') : (prop() != null ? propArr('position') : null);
      if (arr != null)
      {
        arr[0] += dx;
        arr[1] += dy;
        if (selectedChar != null) placeCharacter(selectedChar);
        else
          placeProp(selectedProp);
        charForm.refresh();
        propForm.refresh();
        committed();
      }
    }
    if (FlxG.keys.pressed.Q) zoom = Math.max(0.05, zoom - FlxG.elapsed * zoom);
    if (FlxG.keys.pressed.E) zoom = Math.min(4, zoom + FlxG.elapsed * zoom);
  }

  function updateInfo()
  {
    var sel = selectedChar != null ? '${selectedChar.toUpperCase()} (${Reflect.field(previewChars, selectedChar)})' : (prop()?.name ?? 'nothing');
    var pos = selectedChar != null ? charArr('position') : (prop() != null ? propArr('position') : [0.0, 0.0]);
    var text = '$stageId.json  ·  selected: $sel  [${pos[0]}, ${pos[1]}]\nzoom ${Math.round(zoom * 100)}%  ·  stage zoom ${data.cameraZoom ?? 1}'
      + (parallax ? '  ·  parallax on' : '');
    if (infoText.text != text) infoText.text = text;
  }

  override public function destroy():Void
  {
    player?.cancel();
    camFocus.put();
    dragLast.put();
    super.destroy();
  }
}
#end
