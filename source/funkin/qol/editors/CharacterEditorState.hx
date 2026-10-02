package funkin.qol.editors;

#if FEATURE_HAXEUI
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.data.character.CharacterData;
import funkin.data.character.CharacterData.CharacterDataParser;
import funkin.play.character.BaseCharacter;
import funkin.play.components.HealthIcon;
import funkin.qol.ui.QOLEditorState;
import funkin.qol.ui.QOLForm;
import funkin.qol.ui.QOLTheme;
import funkin.qol.util.QOLFS;
import funkin.qol.util.QOLJson;
import funkin.ui.debug.GraphicCursorCross;
import haxe.io.Path;
import haxe.ui.components.Button;
import haxe.ui.components.Label;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ListView;
import haxe.ui.data.ArrayDataSource;
import openfl.display.BitmapData;

/**
 * The QOL Slice Character Editor.
 *
 * Edits every field of a V-Slice character JSON with a live preview that uses the real game
 * character classes (so Sparrow, Packer, Multi-Sparrow and Animate atlases all look exactly like
 * they do in game). Saves to `mods/<mod>/data/characters/<id>.json`.
 */
class CharacterEditorState extends QOLEditorState
{
  static inline final FEET_X:Float = 0;
  static inline final FEET_Y:Float = 0;
  static inline final MAX_UNDO:Int = 200;

  public static final RENDER_TYPES:Array<String> = ['sparrow', 'packer', 'multisparrow', 'animateatlas', 'multianimateatlas'];
  public static final RENDER_TYPE_NAMES:Array<String> = [
    'Sparrow (PNG + XML)',
    'Packer (PNG + TXT)',
    'Multi-Sparrow (several sheets)',
    'Animate atlas (folder)',
    'Multi Animate atlas'
  ];

  /**
   * Standard animation names the game looks for.
   */
  public static final STANDARD_ANIMS:Array<String> = [
    'idle', 'danceLeft', 'danceRight', 'singLEFT', 'singDOWN', 'singUP', 'singRIGHT', 'singLEFTmiss', 'singDOWNmiss', 'singUPmiss', 'singRIGHTmiss',
    'singLEFT-hold', 'singDOWN-hold', 'singUP-hold', 'singRIGHT-hold', 'singLEFT-end', 'singDOWN-end', 'singUP-end', 'singRIGHT-end', 'hey', 'cheer',
    'scared', 'firstDeath', 'deathLoop', 'deathConfirm', 'fakeoutDeath'
  ];

  var charId:String = 'my-character';
  var data:Dynamic;
  var char:Null<BaseCharacter> = null;
  var ghost:Null<BaseCharacter> = null;
  var selectedAnim:Int = 0;
  var showGhost:Bool = true;
  var ghostAnim:String = 'idle';
  var playAsPlayer:Bool = false;
  var paused:Bool = false;

  var propsForm:QOLForm;
  var animForm:QOLForm;
  var animList:ListView;
  var prefixes:Array<String> = [];

  var camMarker:FlxSprite;
  var floorLine:FlxSprite;
  var feetMarker:FlxSprite;
  var errorText:FlxText;
  var infoText:FlxText;
  var iconPreview:Null<HealthIcon> = null;
  var barLeft:FlxSprite;
  var barRight:FlxSprite;

  var camFocus:FlxPoint = FlxPoint.get(0, -300);
  var zoom:Float = 0.7;
  var dragMode:String = '';
  var dragLast:FlxPoint = FlxPoint.get();

  var undoStack:Array<String> = [];
  var redoStack:Array<String> = [];
  var lastSnapshot:String = '';
  var lastSnapshotTime:Float = 0;
  var applyingUndo:Bool = false;
  var time:Float = 0;

  /**
   * @param id Character to open. If null, the last edited character (or a new one) is opened.
   */
  public function new(?id:String)
  {
    super();
    editorName = 'Character Editor';
    leftPanelWidth = 340;
    rightPanelWidth = 340;
    leftPanelTitle = 'Character';
    rightPanelTitle = 'Animations';
    if (id != null) charId = id;
  }

  override function guidePage():String
    return 'character';

  override function buildEditor():Void
  {
    data = defaultData();
    buildMenus();

    floorLine = new FlxSprite(-3000, FEET_Y).makeGraphic(6000, 2, 0x80FF5C9D);
    floorLine.cameras = [camWorld];
    add(floorLine);

    feetMarker = QOLTheme.circle(6, 0xFFFF5C9D);
    feetMarker.cameras = [camWorld];
    feetMarker.setPosition(FEET_X - 6, FEET_Y - 6);
    add(feetMarker);

    camMarker = new FlxSprite().loadGraphic(FlxGraphic.fromClass(GraphicCursorCross));
    camMarker.setGraphicSize(60, 60);
    camMarker.updateHitbox();
    camMarker.cameras = [camWorld];
    camMarker.antialiasing = false;
    camMarker.color = 0xFF5CE1FF;
    add(camMarker);

    errorText = QOLTheme.outlinedText(workLeft + 20, 110, workRight - workLeft - 40, '', 18, QOLTheme.ACCENT_YELLOW, 2);
    errorText.cameras = [camUI];
    errorText.alignment = CENTER;
    add(errorText);

    infoText = QOLTheme.text(workLeft + 12, QOLEditorState.MENUBAR_HEIGHT + 8, 420, '', 13, QOLTheme.FONT_MONO, 0xFFE8E0FF);
    infoText.setBorderStyle(OUTLINE, 0xFF000000, 1);
    infoText.cameras = [camUI];
    add(infoText);

    // Health bar preview (bottom of the viewport).
    barLeft = new FlxSprite().makeGraphic(1, 14, FlxColor.WHITE);
    barRight = new FlxSprite().makeGraphic(1, 14, FlxColor.WHITE);
    for (b in [barLeft, barRight])
    {
      b.cameras = [camUI];
      add(b);
    }
    placeHealthBar();

    buildPropertiesPanel();
    buildAnimationsPanel();

    loadCharacter(charId, true);
  }

  //
  // Menus
  //

  function buildMenus()
  {
    var file = addMenu('File');
    addMenuItem(file, 'New Character', 'Ctrl+N', () -> newCharacter());
    addMenuItem(file, 'Open Character...', 'Ctrl+O', () -> openCharacterDialog());
    addMenuSeparator(file);
    addMenuItem(file, 'Save', 'Ctrl+S', () -> doSave());
    addMenuItem(file, 'Save As New ID...', null, () -> prompt('Save as', 'New character ID (file name):', charId, function(id) {
      id = ModWorkspace.sanitizeFolderName(id).toLowerCase();
      if (id == '') return;
      charId = id;
      propsForm.refresh();
      doSave();
    }));
    addMenuSeparator(file);
    addMenuItem(file, 'Import Spritesheet (PNG + XML/TXT)...', null, importSpritesheet);
    addMenuItem(file, 'Import Animate Atlas Folder...', null, importAtlasFolder);

    var edit = addMenu('Edit');
    addMenuItem(edit, 'Undo', 'Ctrl+Z', undo);
    addMenuItem(edit, 'Redo', 'Ctrl+Y', redo);
    addMenuSeparator(edit);
    addMenuItem(edit, 'Auto-detect Animations', null, autoDetectAnimations);
    addMenuItem(edit, 'Copy Offsets From Ghost Animation', null, () -> {
      var src = findAnim(ghostAnim);
      var anim = currentAnim();
      if (src == null || anim == null) return;
      changing();
      anim.offsets = (src.offsets ?? [0, 0]).copy();
      applyOffsets();
      committed();
    });
    addMenuItem(edit, 'Reset All Offsets', null, () -> confirm('Reset offsets', 'Set every animation\'s offsets to 0, 0?', () -> {
      changing();
      for (a in animations())
        a.offsets = [0, 0];
      rebuild();
      committed();
    }));

    var view = addMenu('View');
    addMenuCheck(view, 'Ghost (onion skin)', showGhost, v -> {
      showGhost = v;
      if (ghost != null) ghost.visible = v;
    });
    addMenuCheck(view, 'Preview as Player (flipped)', playAsPlayer, v -> {
      playAsPlayer = v;
      rebuild();
    });
    addMenuItem(view, 'Reset Camera', 'R', resetCamera);
  }

  //
  // Panels
  //

  function buildPropertiesPanel()
  {
    propsForm = new QOLForm(118, 180);
    propsForm.onAnyChange = () -> committed();

    propsForm.section('Character');
    propsForm.textField('ID (file name)', () -> charId, v -> charId = v.trim());
    propsForm.textField('Display name', () -> data.name, v -> data.name = v);
    propsForm.dropdown('Render type', () -> RENDER_TYPES, () -> data.renderType, v -> {
      data.renderType = v;
      rebuild();
    }, () -> RENDER_TYPE_NAMES);
    propsForm.file('Asset path', () -> data.assetPath, v -> {
      data.assetPath = v;
      rebuild();
    }, cb -> browseModFile('Choose the character spritesheet', 'images', ['png'], cb));
    propsForm.buttons([
      {text: 'Import sheet...', cb: importSpritesheet},
      {text: 'Import atlas...', cb: importAtlasFolder}
    ]);
    propsForm.number('Scale', () -> data.scale ?? 1, v -> {
      data.scale = v;
      rebuild();
    }, 0.05, 20, 0.05, 2);
    propsForm.check('Pixel art', () -> data.isPixel == true, v -> {
      data.isPixel = v;
      rebuild();
    });
    propsForm.check('Faces right (flip X)', () -> data.flipX == true, v -> {
      data.flipX = v;
      rebuild();
    });
    propsForm.number('Dance every', () -> data.danceEvery ?? 1, v -> data.danceEvery = v, 0, 16, 0.25, 2);
    propsForm.number('Sing time (steps)', () -> data.singTime ?? 8, v -> data.singTime = v, 0, 64, 0.5, 1);
    propsForm.dropdown('Starting anim', () -> animNames(), () -> data.startingAnimation ?? 'idle', v -> data.startingAnimation = v);
    propsForm.pair('Global offset', () -> arr(data, 'offsets')[0], v -> {
      arr(data, 'offsets')[0] = v;
      applyGlobalOffsets();
    }, () -> arr(data, 'offsets')[1], v -> {
      arr(data, 'offsets')[1] = v;
      applyGlobalOffsets();
    });
    propsForm.pair('Camera offset', () -> arr(data, 'cameraOffsets')[0], v -> {
      arr(data, 'cameraOffsets')[0] = v;
      updateCameraMarker(true);
    }, () -> arr(data, 'cameraOffsets')[1], v -> {
      arr(data, 'cameraOffsets')[1] = v;
      updateCameraMarker(true);
    });
    propsForm.note('Tip: drag the cross in the viewport to move the camera point.');

    propsForm.section('Health icon');
    propsForm.file('Icon ID', () -> icon().id, v -> {
      icon().id = v;
      updateIcon();
    }, cb -> browseModFile('Choose a health icon', 'images', ['png'], key -> {
      var name = Path.withoutDirectory(key);
      if (name.startsWith('icon-')) name = name.substr(5);
      cb(name);
    }));
    propsForm.check('Pixel icon', () -> icon().isPixel == true, v -> {
      icon().isPixel = v;
      updateIcon();
    });
    propsForm.check('Flip icon', () -> icon().flipX == true, v -> {
      icon().flipX = v;
      updateIcon();
    });
    propsForm.check('Icon bops', () -> icon().shouldBop != false, v -> icon().shouldBop = v);
    propsForm.number('Icon scale', () -> icon().scale ?? 1, v -> {
      icon().scale = v;
      updateIcon();
    }, 0.05, 10, 0.05, 2);
    propsForm.pair('Icon offset', () -> arr(icon(), 'offsets')[0], v -> {
      arr(icon(), 'offsets')[0] = v;
      updateIcon();
    }, () -> arr(icon(), 'offsets')[1], v -> {
      arr(icon(), 'offsets')[1] = v;
      updateIcon();
    });

    propsForm.section('Health bar (QOL Slice)');
    propsForm.colorField('Bar color', () -> healthBarColor(), v -> {
      qol().healthBarColor = '#' + StringTools.hex(v & 0xFFFFFF, 6);
      updateBar();
    });
    propsForm.button('Pick color from health icon', pickColorFromIcon);

    propsForm.section('Death (game over)');
    propsForm.pair('Death cam offset', () -> arr(death(), 'cameraOffsets')[0], v -> arr(death(), 'cameraOffsets')[0] = v,
      () -> arr(death(), 'cameraOffsets')[1], v -> arr(death(), 'cameraOffsets')[1] = v);
    propsForm.number('Death cam zoom', () -> death().cameraZoom ?? 1, v -> death().cameraZoom = v, 0.1, 10, 0.05, 2);
    propsForm.number('Pre-retry delay', () -> death().preTransitionDelay ?? 0, v -> death().preTransitionDelay = v, 0, 30, 0.1, 2);
    propsForm.button('Open the Death Animation Editor', () -> {
      if (dirty) doSave();
      FlxG.switchState(() -> new DeathEditorState(charId));
    });

    leftPanel.addComponent(propsForm);
  }

  function buildAnimationsPanel()
  {
    var title = new Label();
    title.text = 'Animations';
    title.styleString = 'font-bold: true; font-size: 15px; color: #FF8FB8;';
    rightPanel.addComponent(title);

    animList = new ListView();
    animList.width = rightPanelWidth - 30;
    animList.height = 190;
    animList.onChange = function(_) {
      if (animList.selectedIndex >= 0 && animList.selectedIndex != selectedAnim) selectAnim(animList.selectedIndex, true);
    };
    rightPanel.addComponent(animList);

    var row = new HBox();
    row.styleString = 'spacing: 3px;';
    row.addComponent(miniButton('Add', addAnimation));
    row.addComponent(miniButton('Copy', duplicateAnimation));
    row.addComponent(miniButton('Delete', removeAnimation));
    row.addComponent(miniButton('Auto-detect', autoDetectAnimations));
    rightPanel.addComponent(row);

    animForm = new QOLForm(100, 196);
    animForm.onAnyChange = () -> committed();
    animForm.section('Selected animation');
    animForm.dropdown('Name', () -> {
      var list = STANDARD_ANIMS.copy();
      var cur = currentAnim()?.name;
      if (cur != null && !list.contains(cur)) list.unshift(cur);
      return list;
    }, () -> currentAnim()?.name ?? '', v -> {
      var a = currentAnim();
      if (a == null) return;
      if (data.startingAnimation == a.name) data.startingAnimation = v;
      a.name = v;
      refreshAnimList();
      rebuild();
    });
    animForm.textField('Custom name', () -> currentAnim()?.name ?? '', v -> {
      var a = currentAnim();
      if (a == null || v.trim() == '') return;
      a.name = v.trim();
      refreshAnimList();
      rebuildSoon();
    });
    animForm.dropdown('Prefix', () -> prefixes, () -> currentAnim()?.prefix ?? '', v -> {
      var a = currentAnim();
      if (a == null) return;
      a.prefix = v;
      refreshAnimList();
      rebuild();
    });
    animForm.textField('Custom prefix', () -> currentAnim()?.prefix ?? '', v -> {
      var a = currentAnim();
      if (a == null) return;
      a.prefix = v;
      refreshAnimList();
      rebuildSoon();
    });
    animForm.textField('Frame indices', () -> indicesToText(currentAnim()?.frameIndices), v -> {
      var a = currentAnim();
      if (a == null) return;
      a.frameIndices = textToIndices(v);
      rebuildSoon();
    }, 'e.g. 0-5, 8, 10-12 (empty = all)');
    animForm.number('Frame rate', () -> currentAnim()?.frameRate ?? 24, v -> {
      var a = currentAnim();
      if (a == null) return;
      a.frameRate = Std.int(v);
      rebuild();
    }, 1, 240, 1, 0);
    animForm.check('Loop', () -> currentAnim()?.looped == true, v -> {
      var a = currentAnim();
      if (a == null) return;
      a.looped = v;
      rebuild();
    });
    animForm.check('Flip X', () -> currentAnim()?.flipX == true, v -> {
      var a = currentAnim();
      if (a == null) return;
      a.flipX = v;
      rebuild();
    });
    animForm.check('Flip Y', () -> currentAnim()?.flipY == true, v -> {
      var a = currentAnim();
      if (a == null) return;
      a.flipY = v;
      rebuild();
    });
    animForm.pair('Offsets', () -> arr(currentAnim(), 'offsets')[0], v -> {
      if (currentAnim() == null) return;
      arr(currentAnim(), 'offsets')[0] = v;
      applyOffsets();
    }, () -> arr(currentAnim(), 'offsets')[1], v -> {
      if (currentAnim() == null) return;
      arr(currentAnim(), 'offsets')[1] = v;
      applyOffsets();
    });
    animForm.file('Sheet (multi)', () -> currentAnim()?.assetPath ?? '', v -> {
      var a = currentAnim();
      if (a == null) return;
      a.assetPath = v == '' ? null : v;
      rebuild();
    }, cb -> browseModFile('Spritesheet for this animation', 'images', ['png'], cb));
    animForm.dropdown('Atlas anim type', () -> ['framelabel', 'symbol'], () -> currentAnim()?.animType ?? 'framelabel', v -> {
      var a = currentAnim();
      if (a == null) return;
      a.animType = v;
      rebuild();
    });
    animForm.buttons([
      {text: 'Play (Space)', cb: () -> playCurrent(true)},
      {text: 'Use as ghost', cb: () -> {
        ghostAnim = currentAnim()?.name ?? 'idle';
        rebuild();
      }}
    ]);
    animForm.note('Arrows: nudge offsets (Shift = x10)  ·  Drag the character to move it\n'
      + 'W/S: previous/next animation  ·  Space: play  ·  ,/.: step frames\n'
      + 'Wheel or Q/E: zoom  ·  Right-drag: pan  ·  G: ghost  ·  F: flip');
    rightPanel.addComponent(animForm);
  }

  function miniButton(text:String, cb:Void->Void):Button
  {
    var b = new Button();
    b.text = text;
    b.onClick = _ -> cb();
    return b;
  }

  //
  // Data helpers
  //

  static function arr(obj:Dynamic, field:String):Array<Float>
  {
    if (obj == null) return [0, 0];
    var v:Array<Float> = Reflect.field(obj, field);
    if (v == null || v.length < 2)
    {
      v = [0, 0];
      Reflect.setField(obj, field, v);
    }
    return v;
  }

  function icon():Dynamic
  {
    if (data.healthIcon == null) data.healthIcon = {id: charId};
    return data.healthIcon;
  }

  function death():Dynamic
  {
    if (data.death == null) data.death = {};
    return data.death;
  }

  function qol():Dynamic
  {
    if (data.qol == null) data.qol = {};
    return data.qol;
  }

  function healthBarColor():Int
  {
    var hex:String = data.qol?.healthBarColor;
    if (hex == null) return 0xFF66FF33;
    var c = FlxColor.fromString(hex);
    return c == null ? 0xFF66FF33 : c;
  }

  function animations():Array<Dynamic>
  {
    if (data.animations == null) data.animations = [];
    return data.animations;
  }

  function animNames():Array<String>
    return [for (a in animations()) a.name];

  function currentAnim():Null<Dynamic>
  {
    var list = animations();
    if (selectedAnim < 0 || selectedAnim >= list.length) return null;
    return list[selectedAnim];
  }

  function findAnim(name:String):Null<Dynamic>
  {
    for (a in animations())
      if (a.name == name) return a;
    return null;
  }

  static function indicesToText(indices:Array<Int>):String
  {
    if (indices == null || indices.length == 0) return '';
    var parts:Array<String> = [];
    var i = 0;
    while (i < indices.length)
    {
      var start = indices[i];
      var end = start;
      while (i + 1 < indices.length && indices[i + 1] == end + 1)
      {
        end++;
        i++;
      }
      parts.push(end > start + 1 ? '$start-$end' : (end == start ? '$start' : '$start, $end'));
      i++;
    }
    return parts.join(', ');
  }

  static function textToIndices(text:String):Array<Int>
  {
    var result:Array<Int> = [];
    for (part in text.split(','))
    {
      part = part.trim();
      if (part == '') continue;
      var dash = part.indexOf('-', 1);
      if (dash > 0)
      {
        var a = Std.parseInt(part.substr(0, dash).trim());
        var b = Std.parseInt(part.substr(dash + 1).trim());
        if (a == null || b == null) continue;
        if (a <= b) for (n in a...b + 1)
          result.push(n);
        else
        {
          var n = a;
          while (n >= b)
            result.push(n--);
        }
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

  function defaultData():Dynamic
  {
    return {
      version: CharacterDataParser.CHARACTER_DATA_VERSION,
      name: 'My Character',
      renderType: 'sparrow',
      assetPath: 'characters/BOYFRIEND',
      scale: 1,
      isPixel: false,
      flipX: false,
      danceEvery: 1,
      singTime: 8,
      startingAnimation: 'idle',
      offsets: [0, 0],
      cameraOffsets: [0, 0],
      healthIcon: {
        id: 'bf',
        isPixel: false,
        flipX: false,
        scale: 1,
        offsets: [0, 25],
        shouldBop: true
      },
      death: {
        cameraOffsets: [0, 0],
        cameraZoom: 1,
        preTransitionDelay: 0
      },
      animations: [
        {
          name: 'idle',
          prefix: 'BF idle dance',
          offsets: [0, 0],
          frameRate: 24,
          looped: false
        }
      ]
    };
  }

  function newCharacter()
  {
    prompt('New character', 'ID for the new character (this is its file name):', 'my-character', function(id:String) {
      id = ModWorkspace.sanitizeFolderName(id).toLowerCase();
      if (id == '') return;
      charId = id;
      data = defaultData();
      data.healthIcon.id = id;
      afterLoad();
      dirty = true;
    });
  }

  function openCharacterDialog()
  {
    var ids = CharacterDataParser.listCharacterIds();
    for (file in ModWorkspace.listRecursive('data/characters', ['json']))
    {
      var id = Path.withoutExtension(file);
      if (!ids.contains(id)) ids.push(id);
    }
    ids.sort((a, b) -> a.toLowerCase() < b.toLowerCase() ? -1 : 1);
    chooseFromList('Open character', ids, id -> loadCharacter(id, false), charId);
  }

  /**
   * Load a character by ID: from the active mod first, then whatever the game has loaded.
   */
  function loadCharacter(id:String, startup:Bool)
  {
    var raw:Dynamic = ModWorkspace.hasMod ? ModWorkspace.getJson('data/characters/$id.json') : null;
    if (raw == null)
    {
      try
      {
        var path = Paths.json('characters/$id');
        if (Assets.exists(path)) raw = QOLJson.tryParse(Assets.getText(path));
      }
      catch (e) {}
    }
    if (raw == null)
    {
      if (!startup) alert('Not found', 'Could not find a character called "$id".');
      var last:String = QOLConfig.getPref('characterEditor.last', null);
      if (startup && last != null && last != id)
      {
        loadCharacter(last, true);
        return;
      }
      data = defaultData();
      charId = id;
    }
    else
    {
      data = raw;
      charId = id;
    }
    afterLoad();
  }

  function afterLoad()
  {
    selectedAnim = 0;
    var idleIndex = animNames().indexOf(data.startingAnimation ?? 'idle');
    if (idleIndex >= 0) selectedAnim = idleIndex;
    ghostAnim = data.startingAnimation ?? 'idle';
    undoStack = [];
    redoStack = [];
    lastSnapshot = haxe.Json.stringify(data);
    QOLConfig.setPref('characterEditor.last', charId);
    rebuild();
    refreshAnimList();
    propsForm.refresh();
    animForm.refresh();
    updateIcon();
    resetCamera();
    dirty = false;
  }

  //
  // Building the preview
  //

  var rebuildTimer:Float = -1;

  function rebuildSoon()
  {
    rebuildTimer = 0.4;
  }

  function rebuild():Void
  {
    rebuildTimer = -1;
    var keepAnim = currentAnim()?.name;
    for (c in [char, ghost])
    {
      if (c == null) continue;
      remove(c, true);
      c.destroy();
    }
    char = null;
    ghost = null;
    errorText.text = '';

    try
    {
      if (data.version == null) data.version = CharacterDataParser.CHARACTER_DATA_VERSION;
      if (animations().length == 0) throw 'Add at least one animation (or use Auto-detect).';
      @:privateAccess
      var valid = CharacterDataParser.validateCharacterData(charId, data);
      if (valid == null) throw 'This character is missing an asset path or animations.';
      @:privateAccess CharacterDataParser.characterCache.set(charId, data);

      char = makeCharacter();
      if (showGhost && ghostAnim != null && findAnim(ghostAnim) != null)
      {
        ghost = makeCharacter();
        if (ghost != null)
        {
          ghost.alpha = 0.32;
          ghost.color = 0xFF88AAFF;
          ghost.playAnimation(ghostAnim, true);
          if (ghost.animation.curAnim != null)
          {
            ghost.animation.curAnim.curFrame = 0;
            ghost.animation.curAnim.pause();
          }
          insert(members.indexOf(floorLine) + 1, ghost);
        }
      }
      if (char != null)
      {
        insert(members.indexOf(camMarker), char);
        updatePrefixes();
        if (keepAnim != null && findAnim(keepAnim) != null) char.playAnimation(keepAnim, true);
        updateAnimWarning();
      }
    }
    catch (e)
    {
      errorText.text = 'Preview problem: $e';
      trace('[QOL] Character preview failed: $e');
    }
    updateCameraMarker(false);
    animForm?.refresh();
  }

  function makeCharacter():Null<BaseCharacter>
  {
    var c = CharacterDataParser.fetchCharacter(charId, true);
    if (c == null) throw 'The game could not build this character.';
    if (c.frames == null && !c.isAnimate)
    {
      c.destroy();
      throw 'Could not load the spritesheet "${data.assetPath}". Check the asset path (it\'s relative to images/, without .png).';
    }
    c.cameras = [camWorld];
    c.flipX = playAsPlayer ? !c.getDataFlipX() : c.getDataFlipX();
    c.resetCharacter(true);
    c.x = FEET_X - c.characterOrigin.x;
    c.y = FEET_Y - c.characterOrigin.y;
    c.originalPosition.set(c.x, c.y);
    c.resetCameraFocusPoint();
    return c;
  }

  function updatePrefixes()
  {
    prefixes = [];
    if (char == null || char.frames == null) return;
    var seen = new Map<String, Bool>();
    var digits = ~/[0-9]+$/;
    for (frame in char.frames.frames)
    {
      if (frame == null || frame.name == null) continue;
      var p = digits.replace(frame.name, '');
      if (p.endsWith('.png')) p = p.substr(0, p.length - 4);
      if (!seen.exists(p))
      {
        seen.set(p, true);
        prefixes.push(p);
      }
    }
    prefixes.sort((a, b) -> a.toLowerCase() < b.toLowerCase() ? -1 : 1);
  }

  function applyOffsets()
  {
    var a = currentAnim();
    if (a == null || char == null) return;
    var o = arr(a, 'offsets');
    char.setAnimationOffsets(a.name, o[0], o[1]);
    if (ghost != null && a.name == ghostAnim) ghost.setAnimationOffsets(a.name, o[0], o[1]);
    if (char.getCurrentAnimation() == a.name) char.playAnimation(a.name, false);
    else
      playCurrent(true);
    animForm.refresh();
  }

  function applyGlobalOffsets()
  {
    for (c in [char, ghost])
      if (c != null) c.globalOffsets = arr(data, 'offsets').copy();
  }

  function updateCameraMarker(resetFocus:Bool)
  {
    if (char == null)
    {
      camMarker.visible = false;
      return;
    }
    if (resetFocus) char.resetCameraFocusPoint();
    camMarker.visible = true;
    camMarker.setPosition(char.cameraFocusPoint.x - camMarker.width / 2, char.cameraFocusPoint.y - camMarker.height / 2);
  }

  function updateIcon()
  {
    if (iconPreview != null)
    {
      remove(iconPreview, true);
      iconPreview.destroy();
      iconPreview = null;
    }
    try
    {
      iconPreview = new HealthIcon(icon().id ?? charId, 1);
      @:privateAccess iconPreview.autoUpdate = false;
      iconPreview.configure(icon());
      iconPreview.cameras = [camUI];
      add(iconPreview);
      placeHealthBar();
    }
    catch (e)
    {
      trace('[QOL] Icon preview failed: $e');
    }
    updateBar();
  }

  /**
   * Health bar preview along the bottom of the view (follows the panels when they move).
   */
  function placeHealthBar():Void
  {
    var vx = workLeft + 20;
    var vw = Math.max(80, workRight - workLeft - 40);
    var y = FlxG.height - QOLEditorState.STATUSBAR_HEIGHT - 40;
    barLeft.setGraphicSize(Std.int(vw / 2), 14);
    barLeft.updateHitbox();
    barLeft.setPosition(vx, y);
    barRight.setGraphicSize(Std.int(vw / 2), 14);
    barRight.updateHitbox();
    barRight.setPosition(vx + vw / 2, y);
    if (iconPreview != null)
    {
      iconPreview.x = barLeft.x + barLeft.width - iconPreview.width / 2 + 40;
      iconPreview.y = barLeft.y - iconPreview.height / 2 + 7;
    }
  }

  override function onLayoutChanged():Void
  {
    if (errorText != null)
    {
      errorText.x = workLeft + 20;
      errorText.fieldWidth = Math.max(80, workRight - workLeft - 40);
    }
    if (infoText != null) infoText.x = workLeft + 12;
    if (barLeft != null) placeHealthBar();
  }

  function updateBar()
  {
    barLeft.color = 0xFFFF0000;
    barRight.color = healthBarColor();
  }

  function pickColorFromIcon()
  {
    if (iconPreview == null || iconPreview.frame == null) return;
    var bmp:BitmapData = iconPreview.frame.parent.bitmap;
    // The game may have moved this image to the graphics card only (see QOLPerformance); load a readable copy.
    if (!bmp.readable) bmp = openfl.utils.Assets.getBitmapData(iconPreview.frame.parent.key, false) ?? bmp;
    var rect = iconPreview.frame.frame;
    var r = 0.0, g = 0.0, b = 0.0, n = 0.0;
    var step = Std.int(Math.max(1, rect.width / 40));
    var y = Std.int(rect.y);
    while (y < rect.y + rect.height)
    {
      var x = Std.int(rect.x);
      while (x < rect.x + rect.width)
      {
        var c:FlxColor = bmp.getPixel32(x, y);
        // Weight saturated, opaque, non-outline pixels.
        if (c.alpha > 200 && c.lightness > 0.15 && c.lightness < 0.92)
        {
          var w = 0.2 + c.saturation;
          r += c.red * w;
          g += c.green * w;
          b += c.blue * w;
          n += w;
        }
        x += step;
      }
      y += step;
    }
    if (n == 0) return;
    changing();
    var picked = FlxColor.fromRGB(Std.int(r / n), Std.int(g / n), Std.int(b / n));
    qol().healthBarColor = '#' + picked.toHexString(false, false);
    updateBar();
    propsForm.refresh();
    committed();
  }

  //
  // Animations
  //

  function refreshAnimList()
  {
    var ds = new ArrayDataSource<Dynamic>();
    for (a in animations())
      ds.add({text: '${a.name}   ·   ${a.prefix ?? '?'}'});
    animList.dataSource = ds;
    if (selectedAnim >= animations().length) selectedAnim = animations().length - 1;
    if (selectedAnim >= 0) animList.selectedIndex = selectedAnim;
    animForm.hidden = animations().length == 0;
  }

  function selectAnim(index:Int, play:Bool)
  {
    var list = animations();
    if (list.length == 0) return;
    selectedAnim = ((index % list.length) + list.length) % list.length;
    if (animList.selectedIndex != selectedAnim) animList.selectedIndex = selectedAnim;
    animForm.refresh();
    if (play) playCurrent(true);
    else
      updateAnimWarning();
  }

  function playCurrent(restart:Bool)
  {
    var a = currentAnim();
    if (a == null || char == null) return;
    paused = false;
    char.canPlayOtherAnims = true;
    char.playAnimation(a.name, restart);
    updateAnimWarning();
  }

  var animWarningShown:Bool = false;

  /**
   * Animations whose prefix matches no frame in the spritesheet. (Flixel would quietly show the sheet's first frame,
   * which looks like a random pose.)
   */
  function brokenAnims():Array<String>
  {
    var broken:Array<String> = [];
    if (char == null || char.isAnimate || char.frames == null) return broken;
    var names = [for (f in char.frames.frames) if (f != null && f.name != null) f.name];
    for (a in animations())
    {
      var prefix:String = a.prefix ?? '';
      if (prefix == '') continue;
      var found = false;
      for (n in names)
        if (n.startsWith(prefix))
        {
          found = true;
          break;
        }
      if (!found) broken.push(a.name);
    }
    return broken;
  }

  /**
   * Warn (and hide the character) when the selected animation's prefix doesn't exist in the sheet.
   */
  function updateAnimWarning():Void
  {
    if (errorText == null) return;
    var ours = animWarningShown && errorText.text != '';
    if (char == null)
    {
      if (ours) errorText.text = '';
      animWarningShown = false;
      return;
    }
    var broken = brokenAnims();
    var a = currentAnim();
    var currentBroken = a != null && broken.contains(a.name);
    char.visible = !currentBroken;
    if (ghost != null) ghost.visible = !broken.contains(ghostAnim);
    if (broken.length == 0)
    {
      if (ours) errorText.text = '';
      animWarningShown = false;
      return;
    }
    if (errorText.text != '' && !ours) return; // A bigger problem is already shown.
    var msg = currentBroken ? 'No frames in the spritesheet start with "${a.prefix}".\nPick one from the Prefix list, or fix the spelling.' : '';
    var others = [for (n in broken) if (a == null || n != a.name) n];
    if (others.length > 0) msg += (msg == '' ? '' : '\n') + 'Animations with a missing prefix: ${others.join(', ')}';
    errorText.text = msg;
    animWarningShown = true;
  }

  function addAnimation()
  {
    changing();
    var used = animNames();
    var name = 'idle';
    for (n in STANDARD_ANIMS)
      if (!used.contains(n))
      {
        name = n;
        break;
      }
    animations().push({
      name: name,
      prefix: prefixes.length > 0 ? prefixes[0] : '',
      offsets: [0, 0],
      frameRate: 24,
      looped: false
    });
    selectedAnim = animations().length - 1;
    refreshAnimList();
    rebuild();
    committed();
  }

  function duplicateAnimation()
  {
    var a = currentAnim();
    if (a == null) return;
    changing();
    var copy = QOLJson.clone(a);
    copy.name = a.name + '-copy';
    animations().insert(selectedAnim + 1, copy);
    selectedAnim++;
    refreshAnimList();
    rebuild();
    committed();
  }

  function removeAnimation()
  {
    var a = currentAnim();
    if (a == null) return;
    changing();
    animations().remove(a);
    refreshAnimList();
    rebuild();
    committed();
  }

  /**
   * Guess animations from the spritesheet's frame prefixes.
   */
  function autoDetectAnimations()
  {
    if (prefixes.length == 0)
    {
      alert('Nothing to detect', 'Load a spritesheet first (set the asset path).');
      return;
    }
    changing();
    var added = 0;
    for (prefix in prefixes)
    {
      var p = prefix.toLowerCase();
      var miss = p.indexOf('miss') != -1;
      var name:Null<String> = null;
      if (p.indexOf('first death') != -1 || p.indexOf('firstdeath') != -1 || p.indexOf('dies') != -1) name = 'firstDeath';
      else if (p.indexOf('dead loop') != -1 || p.indexOf('deathloop') != -1 || p.indexOf('death loop') != -1) name = 'deathLoop';
      else if (p.indexOf('confirm') != -1 && p.indexOf('dead') != -1) name = 'deathConfirm';
      else if (p.indexOf('dance') != -1 && p.indexOf('left') != -1) name = 'danceLeft';
      else if (p.indexOf('dance') != -1 && p.indexOf('right') != -1) name = 'danceRight';
      else if (p.indexOf('idle') != -1) name = 'idle';
      else if (p.indexOf('left') != -1) name = 'singLEFT';
      else if (p.indexOf('down') != -1) name = 'singDOWN';
      else if (p.indexOf('up') != -1) name = 'singUP';
      else if (p.indexOf('right') != -1) name = 'singRIGHT';
      else if (p.indexOf('hey') != -1) name = 'hey';
      else if (p.indexOf('scared') != -1 || p.indexOf('shaking') != -1) name = 'scared';
      else if (p.indexOf('cheer') != -1) name = 'cheer';
      if (name == null) continue;
      if (miss && name.startsWith('sing')) name += 'miss';
      if (findAnim(name) != null) continue;
      animations().push({
        name: name,
        prefix: prefix,
        offsets: [0, 0],
        frameRate: 24,
        looped: name == 'deathLoop'
      });
      added++;
    }
    refreshAnimList();
    rebuild();
    committed();
    notify('Auto-detect', added == 0 ? 'No new animations found.' : 'Added $added animation(s). Check their names and offsets!');
  }

  //
  // Importing
  //

  function importSpritesheet()
  {
    #if sys
    if (!ModWorkspace.hasMod) return alert('No mod selected', 'Pick a mod in the Mod Menu first.');
    funkin.util.FileUtil.browseForFile('Choose the spritesheet PNG', [funkin.util.FileUtil.FILE_FILTER_PNG], function(file) {
      var base = Path.withoutExtension(file.fullPath);
      var key = 'characters/$charId';
      ModWorkspace.saveBytes('images/$key.png', file.bytes);
      var type = 'sparrow';
      if (QOLFS.exists('$base.xml')) ModWorkspace.importFile('$base.xml', 'images/$key.xml');
      else if (QOLFS.exists('$base.txt'))
      {
        ModWorkspace.importFile('$base.txt', 'images/$key.txt');
        type = 'packer';
      }
      else
        alert('No atlas file', 'Copied the PNG, but there was no ${Path.withoutDirectory(base)}.xml or .txt next to it.');
      changing();
      data.assetPath = key;
      data.renderType = type;
      reloadAndRebuild();
      committed();
      notify('Imported', 'images/$key.png');
    });
    #else
    alert('Not available', 'Importing files needs the desktop version of the game.');
    #end
  }

  function importAtlasFolder()
  {
    #if sys
    if (!ModWorkspace.hasMod) return alert('No mod selected', 'Pick a mod in the Mod Menu first.');
    funkin.util.FileUtil.browseForDirectory('Choose the Animate atlas folder (with Animation.json)', function(dir:String) {
      if (!QOLFS.exists('$dir/Animation.json'))
      {
        alert('Not an atlas', 'That folder has no Animation.json. Export a Texture Atlas from Adobe Animate first.');
        return;
      }
      var key = 'characters/$charId';
      for (rel in QOLFS.listFilesRecursive(dir))
        ModWorkspace.importFile('$dir/$rel', 'images/$key/$rel');
      changing();
      data.assetPath = key;
      data.renderType = 'animateatlas';
      reloadAndRebuild();
      committed();
      notify('Imported', 'images/$key/');
    });
    #else
    alert('Not available', 'Importing files needs the desktop version of the game.');
    #end
  }

  /**
   * Hot-reload mods so newly copied files can be found, then put our unsaved data back.
   */
  function reloadAndRebuild()
  {
    ModWorkspace.reloadGameData();
    rebuild();
    propsForm.refresh();
  }

  //
  // Undo / redo
  //

  /**
   * Call before a change that isn't made through a form (forms record automatically).
   */
  function changing()
  {
    var now = haxe.Json.stringify(data);
    if (now != lastSnapshot) committed();
  }

  /**
   * Records the current state as an undo step.
   */
  function committed()
  {
    if (applyingUndo) return;
    var now = haxe.Json.stringify(data);
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
    redoStack.push(haxe.Json.stringify(data));
    restore(undoStack.pop());
  }

  function redo()
  {
    if (redoStack.length == 0) return;
    undoStack.push(haxe.Json.stringify(data));
    restore(redoStack.pop());
  }

  function restore(snapshot:String)
  {
    applyingUndo = true;
    data = haxe.Json.parse(snapshot);
    lastSnapshot = snapshot;
    rebuild();
    refreshAnimList();
    propsForm.refresh();
    animForm.refresh();
    updateIcon();
    applyingUndo = false;
    dirty = true;
  }

  //
  // Saving
  //

  override function save():Bool
  {
    if (charId == null || charId.trim() == '')
    {
      alert('No ID', 'Give the character an ID (file name) first.');
      return false;
    }
    data.version = CharacterDataParser.CHARACTER_DATA_VERSION;
    var path = ModWorkspace.saveJson('data/characters/$charId.json', data, [
      'version', 'name', 'renderType', 'assetPath', 'scale', 'isPixel', 'flipX', 'danceEvery', 'singTime', 'startingAnimation', 'offsets',
      'cameraOffsets', 'healthIcon', 'death', 'qol', 'animations', 'id', 'prefix', 'frameIndices', 'frameRate', 'looped', 'flipY'
    ]);
    QOLConfig.setPref('characterEditor.last', charId);
    notifySaved(path);
    return true;
  }

  override function afterSaveReload():Void
  {
    var keep = haxe.Json.stringify(data);
    ModWorkspace.reloadGameData();
    data = haxe.Json.parse(keep);
    rebuild();
  }

  //
  // Camera & input
  //

  function viewportCenterX():Float
    return workLeft + (workRight - workLeft) / 2;

  function resetCamera()
  {
    zoom = 0.7;
    if (char != null) camFocus.set(FEET_X, FEET_Y - char.height / 2);
    else
      camFocus.set(FEET_X, FEET_Y - 300);
  }

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);
    time += elapsed;

    if (rebuildTimer > 0)
    {
      rebuildTimer -= elapsed;
      if (rebuildTimer <= 0) rebuild();
    }

    // Camera.
    camWorld.zoom = zoom;
    var shiftX = (FlxG.width / 2 - viewportCenterX()) / zoom;
    camWorld.scroll.set(camFocus.x + shiftX - FlxG.width / 2, camFocus.y - FlxG.height / 2);

    handleMouse();
    updateInfo();
  }

  function handleMouse()
  {
    var overUI = mouseOverUI || dialogOpen;
    var mouse = FlxG.mouse.getWorldPosition(camWorld);

    if (!overUI && FlxG.mouse.wheel != 0) zoom = Math.max(0.1, Math.min(4, zoom * (FlxG.mouse.wheel > 0 ? 1.1 : 0.9)));

    if (dragMode == '' && !overUI)
    {
      if (FlxG.mouse.justPressedRight || FlxG.mouse.justPressedMiddle) dragMode = 'pan';
      else if (FlxG.mouse.justPressed)
      {
        if (camMarker.visible && FlxG.mouse.overlaps(camMarker, camWorld)) dragMode = 'camera';
        else if (char != null && FlxG.mouse.overlaps(char, camWorld) && currentAnim() != null) dragMode = 'offset';
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
          var o = arr(data, 'cameraOffsets');
          o[0] += dx;
          o[1] += dy;
          updateCameraMarker(true);
          if (!FlxG.mouse.pressed)
          {
            o[0] = Math.round(o[0]);
            o[1] = Math.round(o[1]);
            updateCameraMarker(true);
            propsForm.refresh();
            committed();
            dragMode = '';
          }
        case 'offset':
          var a = currentAnim();
          var o = arr(a, 'offsets');
          var sx = char.scale.x == 0 ? 1 : char.scale.x;
          var sy = char.scale.y == 0 ? 1 : char.scale.y;
          // Offsets push the sprite the opposite way, so dragging right lowers the X offset.
          o[0] -= dx / sx;
          o[1] -= dy / sy;
          applyOffsets();
          if (!FlxG.mouse.pressed)
          {
            o[0] = Math.round(o[0]);
            o[1] = Math.round(o[1]);
            applyOffsets();
            committed();
            dragMode = '';
          }
      }
    }
    mouse.put();
  }

  override function handleShortcuts():Void
  {
    if (ctrl())
    {
      if (FlxG.keys.justPressed.Z) undo();
      if (FlxG.keys.justPressed.Y) redo();
      if (FlxG.keys.justPressed.N) newCharacter();
      if (FlxG.keys.justPressed.O) openCharacterDialog();
      return;
    }

    var a = currentAnim();
    var step = FlxG.keys.pressed.SHIFT ? 10 : 1;
    var nudge = [0, 0];
    if (FlxG.keys.justPressed.LEFT) nudge[0] += step;
    if (FlxG.keys.justPressed.RIGHT) nudge[0] -= step;
    if (FlxG.keys.justPressed.UP) nudge[1] += step;
    if (FlxG.keys.justPressed.DOWN) nudge[1] -= step;
    if (a != null && (nudge[0] != 0 || nudge[1] != 0))
    {
      // Group quick nudges into one undo step.
      if (time - lastSnapshotTime > 0.6) changing();
      var o = arr(a, 'offsets');
      o[0] += nudge[0];
      o[1] += nudge[1];
      applyOffsets();
      committed();
    }

    if (FlxG.keys.justPressed.W) selectAnim(selectedAnim - 1, true);
    if (FlxG.keys.justPressed.S) selectAnim(selectedAnim + 1, true);
    if (FlxG.keys.justPressed.SPACE) playCurrent(true);
    if (FlxG.keys.justPressed.G)
    {
      showGhost = !showGhost;
      rebuild();
    }
    if (FlxG.keys.justPressed.F)
    {
      playAsPlayer = !playAsPlayer;
      rebuild();
    }
    if (FlxG.keys.justPressed.R) resetCamera();
    if (FlxG.keys.pressed.Q) zoom = Math.max(0.1, zoom - FlxG.elapsed * zoom);
    if (FlxG.keys.pressed.E) zoom = Math.min(4, zoom + FlxG.elapsed * zoom);
    if (FlxG.keys.justPressed.COMMA) stepFrame(-1);
    if (FlxG.keys.justPressed.PERIOD) stepFrame(1);
  }

  function stepFrame(dir:Int)
  {
    if (char == null || char.animation.curAnim == null) return;
    var anim = char.animation.curAnim;
    anim.pause();
    paused = true;
    var count = anim.numFrames;
    anim.curFrame = ((anim.curFrame + dir) % count + count) % count;
  }

  function updateInfo()
  {
    var a = currentAnim();
    var frameInfo = '';
    if (char != null && char.animation.curAnim != null)
      frameInfo = '  frame ${char.animation.curAnim.curFrame + 1}/${char.animation.curAnim.numFrames}${paused ? ' (paused)' : ''}';
    var o = a == null ? [0.0, 0.0] : arr(a, 'offsets');
    var text = '${charId}.json  ·  ${a?.name ?? 'no animation'}$frameInfo\noffset [${o[0]}, ${o[1]}]  ·  zoom ${Math.round(zoom * 100)}%'
      + (playAsPlayer ? '  ·  player view' : '');
    if (infoText.text != text) infoText.text = text;
  }

  override public function destroy():Void
  {
    // Put the real data back so the game doesn't keep our unsaved version.
    try
    {
      @:privateAccess CharacterDataParser.characterCache.remove(charId);
      var fresh = CharacterDataParser.parseCharacterData(charId);
      if (fresh != null) @:privateAccess CharacterDataParser.characterCache.set(charId, fresh);
    }
    catch (e) {}
    camFocus.put();
    dragLast.put();
    super.destroy();
  }
}
#end
