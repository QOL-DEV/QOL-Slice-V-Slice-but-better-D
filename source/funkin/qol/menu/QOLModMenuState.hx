package funkin.qol.menu;

#if FEATURE_HAXEUI
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.addons.display.FlxBackdrop;
import flixel.addons.transition.FlxTransitionableState;
import flixel.graphics.FlxGraphic;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import funkin.audio.FunkinSound;
import funkin.input.Cursor;
import funkin.qol.menu.QOLTools.QOLToolInfo;
import funkin.qol.ui.QOLFlxButton;
import funkin.qol.ui.QOLTheme;
import funkin.qol.util.QOLFS;
import funkin.ui.AtlasText;
import funkin.ui.mainmenu.MainMenuState;
import haxe.ui.backend.flixel.UIState;
import haxe.ui.components.Button;
import haxe.ui.components.CheckBox;
import haxe.ui.components.Label;
import haxe.ui.components.TextArea;
import haxe.ui.components.TextField;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ListView;
import haxe.ui.containers.VBox;
import haxe.ui.containers.dialogs.Dialog;
import haxe.ui.containers.windows.WindowManager;
import haxe.ui.core.Screen;
import haxe.ui.data.ArrayDataSource;
import haxe.ui.focus.FocusManager;
import openfl.display.BitmapData;

/**
 * The QOL Slice Mod Menu (press 7 on the main menu).
 *
 * The home of every editor. Pick the active mod on the left (everything you make is saved
 * straight into that mod's folder), then open a tool. The Animator gets the big featured banner.
 *
 * Everything bops to the menu music. To stay light, every shape is pre-rendered once and cached,
 * floating arrows are a small fixed pool, and per-frame work is just a few lerps.
 * Turn off "Fancy menus" in Engine Settings to disable the extra effects on slow PCs.
 */
class QOLModMenuState extends UIState
{
  static inline final COLS:Int = 6;
  static inline final GRID_X:Float = 344;
  static inline final GRID_Y:Float = 102;
  static inline final TILE_W:Int = 142;
  static inline final TILE_H:Int = 108;
  static inline final GAP:Float = 12;
  static inline final BANNER_H:Int = 176;
  static inline final TILES_Y:Float = GRID_Y + BANNER_H + 16;
  static inline final CARD_X:Float = 24;
  static inline final CARD_W:Int = 300;
  static inline final CARD_H:Int = 562;
  static inline final FLOATING_ARROWS:Int = 9;

  static var lastSelected:Int = -1;

  var camBG:FlxCamera;
  var camMenu:FlxCamera;
  var fancy:Bool;

  // Background.
  var bg:FlxSprite;
  var bgTarget:FlxColor = 0xFF821D44;
  var stripes:FlxBackdrop;
  var arrows:Array<FlxSprite> = [];

  // Header.
  var title:AtlasText;
  var titleBaseY:Array<Float> = [];
  var tag:FlxSprite;
  var tagText:FlxText;
  var tagPop:Float = 0;
  var time:Float = 0;

  // Content.
  var banner:AnimatorBanner;
  var tiles:Array<ToolTile> = [];

  /**
   * -1 = the featured Animator banner, 0+ = a tool tile.
   */
  var selected:Int = -1;

  // Mod card.
  var modIcon:FlxSprite;
  var modIconPop:Float = 0;
  var modTitle:FlxText;
  var modFolder:FlxText;
  var modDesc:FlxText;
  var noModWarning:FlxText;

  // Footer.
  var footerStripe:FlxSprite;
  var descName:FlxText;
  var descText:FlxText;

  var messageBox:FlxSprite;
  var messageText:FlxText;

  var busy:Bool = false;

  public function new()
  {
    super();
  }

  override public function create():Void
  {
    WindowManager.instance.reset();
    FlxTransitionableState.skipNextTransIn = true;
    fancy = QOLConfig.fancyMenus;

    camBG = new FlxCamera();
    camBG.bgColor = 0xFF140E24;
    camMenu = new FlxCamera();
    camMenu.bgColor = FlxColor.TRANSPARENT;
    FlxG.cameras.reset(camBG);
    FlxG.cameras.add(camMenu, true);
    FlxG.cameras.setDefaultDrawTarget(camBG, false);
    FlxG.cameras.setDefaultDrawTarget(camMenu, true);

    super.create();
    root.width = FlxG.width;
    root.height = FlxG.height;
    root.cameras = [camMenu];
    Screen.instance.addComponent(root);

    funkin.util.WindowUtil.setWindowTitle('${QOLSlice.WINDOW_TITLE} - Mod Menu');

    FunkinSound.playMusic('freakyMenu', {
      overrideExisting: true,
      restartTrack: false,
      persist: true
    });

    buildBackground();
    buildHeader();
    buildModCard();
    buildTiles();
    buildFooter();

    selected = Std.int(FlxMath.bound(lastSelected, -1, tiles.length - 1));
    select(selected, false, true);
    refreshModCard();
    if (fancy) playIntro();

    Cursor.show();
    FlxG.mouse.visible = true;

    if (!QOLConfig.seenWelcome)
    {
      QOLConfig.seenWelcome = true;
      haxe.ui.Toolkit.callLater(showWelcome);
    }
  }

  //
  // Building
  //

  function buildBackground()
  {
    bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
    bg.setGraphicSize(Std.int(FlxG.width * 1.08));
    bg.updateHitbox();
    bg.screenCenter();
    bg.antialiasing = true;
    bg.cameras = [camBG];
    bg.color = bgTarget;
    add(bg);

    stripes = new FlxBackdrop(QOLTheme.stripeTile(96, 0x12FFFFFF));
    stripes.velocity.set(fancy ? 26 : 0, 0);
    stripes.cameras = [camBG];
    add(stripes);

    if (fancy)
    {
      var noteFrames = Paths.getSparrowAtlas('NOTE_assets');
      var names = ['purple instance', 'blue instance', 'green instance', 'red instance'];
      for (i in 0...FLOATING_ARROWS)
      {
        var a = new FlxSprite();
        a.frames = noteFrames;
        a.animation.addByPrefix('note', names[i % 4], 0, false);
        a.animation.play('note');
        a.antialiasing = true;
        a.cameras = [camBG];
        resetArrow(a, true);
        arrows.push(a);
        add(a);
      }
    }

    // Soft top and bottom vignette.
    var top = QOLTheme.gradientRoundRect(FlxG.width, 150, 0xD0140E24, 0x00140E24, 0, Math.PI / 2);
    top.cameras = [camBG];
    add(top);
    var bottom = QOLTheme.gradientRoundRect(FlxG.width, 150, 0x00140E24, 0xE0140E24, 0, Math.PI / 2);
    bottom.y = FlxG.height - 150;
    bottom.cameras = [camBG];
    add(bottom);
  }

  function resetArrow(a:FlxSprite, initial:Bool)
  {
    var s = FlxG.random.float(0.28, 0.5);
    a.scale.set(s, s);
    a.updateHitbox();
    a.x = FlxG.random.float(-40, FlxG.width - 40);
    a.y = initial ? FlxG.random.float(0, FlxG.height) : FlxG.height + 40;
    a.velocity.set(FlxG.random.float(-8, 8), -FlxG.random.float(22, 55));
    a.angularVelocity = FlxG.random.float(-25, 25);
    a.alpha = FlxG.random.float(0.14, 0.3);
  }

  function buildHeader()
  {
    title = new AtlasText(26, 14, 'QOL SLICE', AtlasFont.BOLD);
    QOLTheme.scaleAtlasText(title, 0.78);
    for (m in title.members)
      titleBaseY.push(m.y);
    add(title);

    var tagX = title.x + title.width + 22;
    tag = QOLTheme.buttonGraphic(176, 46, QOLTheme.ACCENT_PINK, false, 12, 5);
    tag.setPosition(tagX, 24);
    tag.angle = -4;
    add(tag);
    tagText = QOLTheme.outlinedText(tagX, 30, 176, 'MOD MENU', 24, FlxColor.WHITE, 2.5);
    tagText.alignment = CENTER;
    tagText.angle = -4;
    add(tagText);

    var version = QOLTheme.outlinedText(FlxG.width - 524, 24, 500, QOLSlice.versionString, 15, QOLTheme.TEXT_DIM, 1.5);
    version.alignment = RIGHT;
    add(version);
    var tip = QOLTheme.outlinedText(FlxG.width - 524, 46, 500, 'Everything saves straight into your mod\'s folder!', 15, QOLTheme.ACCENT_YELLOW, 1.5);
    tip.alignment = RIGHT;
    add(tip);
  }

  function buildModCard()
  {
    var y0 = GRID_Y;
    var shadow = QOLTheme.shadow(CARD_W, CARD_H, 20, 0.5);
    shadow.setPosition(CARD_X, y0 + 8);
    add(shadow);
    var card = QOLTheme.roundRect(CARD_W, CARD_H, QOLTheme.PANEL, 20, 0xFF1A1030, 3);
    card.setPosition(CARD_X, y0);
    add(card);

    var chip = QOLTheme.roundRect(116, 24, QOLTheme.ACCENT, 12, 0xFF1A1030, 2);
    chip.setPosition(CARD_X + 20, y0 + 16);
    add(chip);
    var chipText = QOLTheme.text(CARD_X + 20, y0 + 19, 116, 'ACTIVE MOD', 13, QOLTheme.FONT_TITLE, 0xFF1A1030);
    chipText.alignment = CENTER;
    add(chipText);

    var frame = QOLTheme.roundRect(144, 144, 0xFFFFFFFF, 18, 0xFF1A1030, 3);
    frame.setPosition(CARD_X + 20, y0 + 50);
    add(frame);
    modIcon = new FlxSprite(CARD_X + 28, y0 + 58);
    add(modIcon);

    modTitle = QOLTheme.outlinedText(CARD_X + 20, y0 + 204, CARD_W - 40, '', 22, FlxColor.WHITE, 2);
    add(modTitle);
    modFolder = QOLTheme.text(CARD_X + 20, y0 + 234, CARD_W - 40, '', 13, QOLTheme.FONT_MONO, QOLTheme.TEXT_DIM);
    add(modFolder);
    modDesc = QOLTheme.text(CARD_X + 20, y0 + 256, CARD_W - 40, '', 14, QOLTheme.FONT_BODY, 0xFFEDE7FF);
    add(modDesc);

    noModWarning = QOLTheme.outlinedText(CARD_X + 20, y0 + 204, CARD_W - 40,
      'No mod selected yet!\nCreate one (or pick one) and start making stuff.', 17, QOLTheme.ACCENT_YELLOW, 2);
    add(noModWarning);

    var by = y0 + CARD_H - 20 - 4 * 50 + 6;
    addCardButton(by, 'SWITCH MOD  [C]', openModPicker, 0xFF3D7BFF);
    addCardButton(by + 50, 'NEW MOD  [N]', openNewModDialog, 0xFF22B573);
    addCardButton(by + 100, 'OPEN FOLDER  [O]', openModFolder, 0xFFFF9F1C);
    addCardButton(by + 150, 'RELOAD DATA  [F5]', reloadData, 0xFF8E5CFF);
  }

  function addCardButton(y:Float, text:String, cb:Void->Void, color:FlxColor)
  {
    add(new QOLFlxButton(CARD_X + 20, y, CARD_W - 40, 42, text, cb, color, 16));
  }

  function buildTiles()
  {
    var gridW = Std.int(COLS * TILE_W + (COLS - 1) * GAP);
    banner = new AnimatorBanner(GRID_X, GRID_Y, gridW, BANNER_H, () -> {
      select(-1, false);
      openSelected();
    });
    add(banner);

    var i = 0;
    for (tool in QOLTools.TOOLS)
    {
      if (tool.id == 'animator') continue;
      var col = i % COLS;
      var row = Std.int(i / COLS);
      var tile = new ToolTile(GRID_X + col * (TILE_W + GAP), TILES_Y + row * (TILE_H + GAP), TILE_W, TILE_H, tool, i);
      tiles.push(tile);
      add(tile);
      i++;
    }
  }

  function buildFooter()
  {
    var bar = new FlxSprite(0, FlxG.height - 44).makeGraphic(1, 1, 0xE6140E24);
    bar.setGraphicSize(FlxG.width, 44);
    bar.updateHitbox();
    add(bar);
    footerStripe = new FlxSprite(0, FlxG.height - 44).makeGraphic(8, 44, FlxColor.WHITE);
    add(footerStripe);
    descName = QOLTheme.outlinedText(22, FlxG.height - 34, 0, '', 18, FlxColor.WHITE, 2);
    add(descName);
    descText = QOLTheme.text(22, FlxG.height - 31, FlxG.width - 560, '', 15, QOLTheme.FONT_BODY, 0xFFEDE7FF);
    add(descText);
    var keys = QOLTheme.text(FlxG.width - 470, FlxG.height - 31, 450, 'ARROWS select  ·  ENTER open  ·  A animator  ·  ESC back', 14,
      QOLTheme.FONT_TITLE, QOLTheme.TEXT_DIM);
    keys.alignment = RIGHT;
    add(keys);

    messageBox = QOLTheme.roundRect(760, 44, 0xF01A1030, 22, QOLTheme.ACCENT_YELLOW, 3);
    messageBox.setPosition(GRID_X + (COLS * TILE_W + (COLS - 1) * GAP - 760) / 2, FlxG.height - 108);
    messageBox.visible = false;
    add(messageBox);
    messageText = QOLTheme.outlinedText(messageBox.x, messageBox.y + 11, 760, '', 17, FlxColor.WHITE, 2);
    messageText.alignment = CENTER;
    messageText.visible = false;
    add(messageText);
  }

  function playIntro()
  {
    var bannerY = banner.y;
    banner.y -= 30;
    FlxTween.tween(banner, {y: bannerY}, 0.5, {ease: FlxEase.backOut});
    for (tile in tiles)
      tile.introPop(0.05 + tile.index * 0.025);
  }

  //
  // Mod card
  //

  function refreshModCard()
  {
    var info = ModWorkspace.hasMod ? ModWorkspace.readModInfo(ModWorkspace.current) : null;
    noModWarning.visible = info == null;
    modTitle.visible = modFolder.visible = modDesc.visible = info != null;

    var bmp:BitmapData = null;
    if (info != null)
    {
      modTitle.text = info.title;
      modFolder.text = 'mods/${info.folder}  ·  v${info.modVersion}';
      modFolder.y = modTitle.y + modTitle.height + 2;
      var desc = info.description;
      if (desc.length > 150) desc = desc.substr(0, 147) + '...';
      modDesc.text = desc;
      modDesc.y = modFolder.y + modFolder.height + 8;
      if (info.hasIcon)
      {
        var bytes = QOLFS.getBytes('${ModWorkspace.MOD_ROOT}/${info.folder}/_polymod_icon.png');
        if (bytes != null) bmp = BitmapData.fromBytes(bytes);
      }
    }
    if (bmp == null) bmp = funkin.qol.util.QOLIconGen.render(info?.title ?? '?', 128);
    if (bmp != null)
    {
      modIcon.loadGraphic(FlxGraphic.fromBitmapData(bmp, false, null, false));
      modIcon.setGraphicSize(128, 128);
      modIcon.updateHitbox();
      modIcon.antialiasing = true;
    }
    for (tile in tiles)
      tile.locked = tile.tool.needsMod && !ModWorkspace.hasMod;
  }

  //
  // Selection
  //

  function selectedTool():QOLToolInfo
  {
    return selected < 0 ? QOLTools.get('animator') : tiles[selected].tool;
  }

  function select(index:Int, playSound:Bool = true, force:Bool = false)
  {
    if (index < -1 || index >= tiles.length) return;
    if (!force && index == selected) return;
    if (playSound) FunkinSound.playOnce(Paths.sound('scrollMenu'), 0.4);
    selected = index;
    lastSelected = index;
    for (i in 0...tiles.length)
      tiles[i].setSelected(i == selected);
    banner.setSelected(selected == -1);
    var tool = selectedTool();
    // Darkened so the colorful tiles pop (cheaper than a full-screen shade layer).
    bgTarget = FlxColor.fromInt(tool.color).getDarkened(0.45);
    footerStripe.color = tool.color;
    descName.text = tool.name;
    descName.color = FlxColor.fromInt(tool.color).getLightened(0.35);
    descText.x = descName.x + descName.width + 12;
    descText.text = tool.description;
  }

  function openSelected()
  {
    var tool = selectedTool();
    if (tool.needsMod && !ModWorkspace.hasMod)
    {
      flashMessage('${tool.name} saves into a mod. Pick or create a mod first!');
      openModPicker();
      return;
    }
    if (tool.id == 'legacy')
    {
      openLegacyTools();
      return;
    }
    var state = QOLTools.createTool(tool.id);
    if (state == null)
    {
      flashMessage('${tool.name} is still being built. Check back soon!');
      FunkinSound.playOnce(Paths.sound('cancelMenu'), 0.6);
      return;
    }
    busy = true;
    FunkinSound.playOnce(Paths.sound('confirmMenu'));
    if (selected >= 0) tiles[selected].confirm();
    else
      flixel.effects.FlxFlicker.flicker(banner, 0.4, 0.06, true);
    if (fancy)
    {
      camMenu.flash(0x60FFFFFF, 0.35);
      FlxTween.tween(camBG, {zoom: 1.12}, 0.45, {ease: FlxEase.quadIn});
    }
    new FlxTimer().start(0.45, _ -> FlxG.switchState(() -> state));
  }

  function flashMessage(msg:String)
  {
    messageText.text = msg;
    messageBox.visible = messageText.visible = true;
    messageBox.alpha = messageText.alpha = 1;
    FlxTween.cancelTweensOf(messageBox);
    FlxTween.cancelTweensOf(messageText);
    messageBox.scale.set(1.08, 1.08);
    messageText.scale.set(1.08, 1.08);
    FlxTween.tween(messageBox.scale, {x: 1, y: 1}, 0.3, {ease: FlxEase.backOut});
    FlxTween.tween(messageText.scale, {x: 1, y: 1}, 0.3, {ease: FlxEase.backOut});
    FlxTween.tween(messageBox, {alpha: 0}, 0.6, {startDelay: 2.6});
    FlxTween.tween(messageText, {alpha: 0}, 0.6, {startDelay: 2.6});
  }

  //
  // Beat
  //

  override public function beatHit():Bool
  {
    if (!super.beatHit()) return false;
    var beat = Conductor.instance.currentBeat;
    if (fancy) camBG.zoom = beat % 4 == 0 ? 1.045 : 1.022;
    tagPop = 1;
    modIconPop = 1;
    banner.beatHit(beat);
    for (tile in tiles)
      tile.beatHit(beat);
    return true;
  }

  //
  // Update
  //

  var dialogOpen(get, never):Bool;

  function get_dialogOpen():Bool
  {
    @:privateAccess
    for (c in Screen.instance.rootComponents)
      if (Std.isOfType(c, Dialog)) return true;
    return FocusManager.instance.focus != null;
  }

  override public function update(elapsed:Float):Void
  {
    Conductor.instance.update();
    super.update(elapsed);
    time += elapsed;

    // Cheap per-frame animation.
    bg.color = FlxColor.interpolate(bg.color, bgTarget, Math.min(1, elapsed * 3));
    if (!busy) camBG.zoom = FlxMath.lerp(camBG.zoom, 1, Math.min(1, elapsed * 5));

    if (fancy)
    {
      for (i in 0...title.members.length)
      {
        var m = title.members[i];
        if (m != null) m.y = titleBaseY[i] + Math.sin(time * 3.2 + i * 0.55) * 4;
      }
      for (a in arrows)
        if (a.y < -a.height - 20) resetArrow(a, false);
    }

    tagPop = Math.max(0, tagPop - elapsed * 4);
    var ts = 1 + 0.08 * tagPop;
    tag.scale.set(ts, ts);
    tagText.scale.set(ts, ts);

    modIconPop = Math.max(0, modIconPop - elapsed * 4);
    var ms = (128 / Math.max(1, modIcon.frameWidth)) * (1 + 0.06 * modIconPop);
    modIcon.scale.set(ms, ms);

    if (FlxG.keys.justPressed.ESCAPE && funkin.qol.ui.QOLDialogs.closeTop()) return;
    if (busy || dialogOpen) return;

    // Mouse.
    if (FlxG.mouse.justMoved || FlxG.mouse.justPressed)
    {
      if (banner.isHovered())
      {
        select(-1);
        // The banner's own button handles its clicks; clicking anywhere else on the banner opens it too.
        if (FlxG.mouse.justPressed && !banner.button.hovered) openSelected();
      }
      else
      {
        for (i in 0...tiles.length)
        {
          if (tiles[i].isHovered(camMenu))
          {
            select(i);
            if (FlxG.mouse.justPressed) openSelected();
            break;
          }
        }
      }
    }

    // Keyboard. The banner sits above the first row of tiles.
    if (selected == -1)
    {
      if (controls.UI_DOWN_P || controls.UI_RIGHT_P) select(0);
      if (controls.UI_LEFT_P || controls.UI_UP_P) select(tiles.length - 1);
    }
    else
    {
      if (controls.UI_RIGHT_P) select(selected + 1 >= tiles.length ? -1 : selected + 1);
      if (controls.UI_LEFT_P) select(selected - 1);
      if (controls.UI_DOWN_P) select(selected + COLS >= tiles.length ? -1 : selected + COLS);
      if (controls.UI_UP_P) select(selected - COLS < 0 ? -1 : selected - COLS);
    }
    if (FlxG.keys.justPressed.A)
    {
      select(-1, false);
      openSelected();
      return;
    }
    if (controls.ACCEPT) openSelected();
    if (FlxG.keys.justPressed.C) openModPicker();
    if (FlxG.keys.justPressed.N) openNewModDialog();
    if (FlxG.keys.justPressed.O) openModFolder();
    if (FlxG.keys.justPressed.F5) reloadData();
    if (controls.BACK)
    {
      busy = true;
      FunkinSound.playOnce(Paths.sound('cancelMenu'));
      funkin.util.WindowUtil.setWindowTitle(QOLSlice.WINDOW_TITLE);
      FlxG.switchState(() -> new MainMenuState());
    }
  }

  //
  // Actions
  //

  function openModFolder()
  {
    #if sys
    QOLFS.openInExplorer(ModWorkspace.hasMod ? ModWorkspace.modFolder : ModWorkspace.MOD_ROOT);
    #else
    flashMessage('Opening folders needs the desktop version.');
    #end
  }

  function reloadData()
  {
    ModWorkspace.reloadGameData();
    flashMessage('Reloaded every mod and data file!');
  }

  function showWelcome()
  {
    var dialog = new Dialog();
    dialog.title = 'Welcome to QOL Slice!';
    dialog.buttons = DialogButton.OK;
    dialog.destroyOnClose = true;
    var box = new VBox();
    box.width = 520;
    box.styleString = 'spacing: 8px;';
    var text = new Label();
    text.width = 520;
    text.text = 'This is the Mod Menu: the home of every editor.\n\n'
      + '1. Create a mod (or pick an existing one) on the left. That is your "active mod".\n'
      + '2. Open any tool. Everything you make is saved straight into mods/<your mod>/, in the exact folder the game reads it from. No save dialogs, no copying files around.\n'
      + '3. Press F1 inside any editor for help, or open the Guide tile.\n\n'
      + 'When your mod is finished, lock this menu from Engine Settings so players can\'t open the editors.';
    box.addComponent(text);
    dialog.addComponent(box);
    dialog.showDialog(true);
  }

  function openLegacyTools()
  {
    var dialog = new Dialog();
    dialog.title = 'Legacy V-Slice tools';
    dialog.buttons = DialogButton.CANCEL;
    dialog.destroyOnClose = true;
    var box = new VBox();
    box.width = 360;
    box.styleString = 'spacing: 6px;';
    var note = new Label();
    note.width = 360;
    note.text = 'The original V-Slice editors. They save through file dialogs, not into your mod folder.';
    box.addComponent(note);
    function addButton(text:String, make:Void->flixel.FlxState)
    {
      var b = new Button();
      b.text = text;
      b.percentWidth = 100;
      b.onClick = function(_) {
        dialog.hideDialog(DialogButton.CANCEL);
        busy = true;
        FlxG.switchState(make);
      };
      box.addComponent(b);
    }
    #if FEATURE_CHART_EDITOR
    addButton('V-Slice Chart Editor', () -> new funkin.ui.debug.charting.ChartEditorState());
    #end
    #if FEATURE_STAGE_EDITOR
    addButton('V-Slice Stage Editor', () -> new funkin.ui.debug.stageeditor.StageEditorState());
    #end
    #if FEATURE_ANIMATION_EDITOR
    addButton('V-Slice Animation Editor', () -> new funkin.ui.debug.anim.DebugBoundingState());
    #end
    dialog.addComponent(box);
    dialog.showDialog(true);
  }

  public function openModPicker()
  {
    var mods = ModWorkspace.listMods();
    var dialog = new Dialog();
    dialog.title = 'Choose the active mod';
    dialog.buttons = DialogButton.CANCEL | '{{New Mod...}}' | '{{Use This Mod}}';
    dialog.defaultButton = '{{Use This Mod}}';
    dialog.destroyOnClose = true;
    var box = new VBox();
    box.styleString = 'spacing: 6px;';
    var label = new Label();
    label.text = mods.length == 0 ? 'You have no mods yet. Click "New Mod..." to make one!' : 'Mods in your mods/ folder:';
    box.addComponent(label);
    var list = new ListView();
    list.width = 420;
    list.height = 300;
    var ds = new ArrayDataSource<Dynamic>();
    for (m in mods)
      ds.add({text: '${m.title}   (mods/${m.folder})', folder: m.folder});
    list.dataSource = ds;
    for (i in 0...mods.length)
      if (mods[i].folder == ModWorkspace.current) list.selectedIndex = i;
    list.onDblClick = _ -> dialog.hideDialog('{{Use This Mod}}');
    box.addComponent(list);
    dialog.addComponent(box);
    dialog.onDialogClosed = function(e) {
      if (e.button == '{{Use This Mod}}' && list.selectedItem != null)
      {
        ModWorkspace.current = list.selectedItem.folder;
        refreshModCard();
        modIconPop = 1;
        flashMessage('Now editing: ${list.selectedItem.folder}');
      }
      else if (e.button == '{{New Mod...}}')
      {
        haxe.ui.Toolkit.callLater(openNewModDialog);
      }
    };
    dialog.showDialog(true);
  }

  public function openNewModDialog()
  {
    var dialog = new Dialog();
    dialog.title = 'Create a new mod';
    dialog.buttons = DialogButton.CANCEL | '{{Create Mod}}';
    dialog.defaultButton = '{{Create Mod}}';
    dialog.destroyOnClose = true;
    var box = new VBox();
    box.styleString = 'spacing: 6px;';

    function row(labelText:String, comp:haxe.ui.core.Component)
    {
      var h = new HBox();
      var l = new Label();
      l.text = labelText;
      l.width = 110;
      h.addComponent(l);
      h.addComponent(comp);
      box.addComponent(h);
    }

    var titleField = new TextField();
    titleField.width = 300;
    titleField.text = 'My Cool Mod';
    row('Mod name', titleField);

    var folderField = new TextField();
    folderField.width = 300;
    folderField.text = ModWorkspace.sanitizeFolderName(titleField.text);
    var folderEdited = false;
    folderField.onChange = _ -> if (FocusManager.instance.focus == folderField) folderEdited = true;
    titleField.onChange = _ -> if (!folderEdited) folderField.text = ModWorkspace.sanitizeFolderName(titleField.text ?? '');
    row('Folder name', folderField);

    var authorField = new TextField();
    authorField.width = 300;
    authorField.text = 'You';
    row('Author', authorField);

    var descField = new TextArea();
    descField.width = 300;
    descField.height = 70;
    descField.text = 'A Friday Night Funkin\' mod made with QOL Slice.';
    row('Description', descField);

    var folders = new CheckBox();
    folders.text = 'Create all the essential folders (recommended)';
    folders.selected = true;
    box.addComponent(folders);

    var hint = new Label();
    hint.text = 'A temporary icon is generated for you. Change it any time in the Modpack Manager.';
    hint.styleString = 'color: #9AA0A6;';
    box.addComponent(hint);

    dialog.addComponent(box);
    dialog.onDialogClosed = function(e) {
      if (e.button != '{{Create Mod}}') return;
      var title = (titleField.text ?? '').trim();
      if (title == '') title = 'My Mod';
      var meta = ModWorkspace.defaultMeta(title);
      meta.description = descField.text ?? '';
      meta.contributors = [{name: (authorField.text ?? '').trim() == '' ? 'You' : authorField.text.trim(), role: 'Creator'}];
      var folder = ModWorkspace.createMod(title, folderField.text, meta, folders.selected);
      ModWorkspace.current = folder;
      ModWorkspace.reloadGameData();
      refreshModCard();
      modIconPop = 1;
      flashMessage('Created mods/$folder and made it the active mod!');
    };
    dialog.showDialog(true);
    titleField.focus = true;
  }

  override public function destroy():Void
  {
    WindowManager.instance.reset();
    super.destroy();
  }
}

/**
 * One tool tile in the Mod Menu grid: a chunky colored button with a bopping icon.
 */
class ToolTile extends FlxSpriteGroup
{
  public var tool:QOLToolInfo;
  public var index:Int;
  public var locked(default, set):Bool = false;

  var base:FlxSprite;
  var baseLit:FlxSprite;
  var grid:FlxSprite;
  var glow:FlxSprite;
  var art:FlxSprite;
  var nameText:FlxText;
  var lockText:FlxText;
  var isSelected:Bool = false;
  var hasSelectedAnim:Bool = false;
  var artScale:Float = 1;
  var artBaseY:Float = 0;
  var pop:Float = 0;
  var tilt:Float = 0;
  var lift:Float = 0;
  var introOffset:Float = 0;
  var baseY:Float;
  var w:Int;
  var h:Int;

  public function new(x:Float, y:Float, w:Int, h:Int, tool:QOLToolInfo, index:Int)
  {
    super(x, y);
    this.tool = tool;
    this.index = index;
    this.w = w;
    this.h = h;
    this.baseY = y;

    var shadow = QOLTheme.shadow(w, h, 14, 0.5);
    shadow.setPosition(0, 7);
    add(shadow);

    glow = QOLTheme.outline(w + 12, h + 12, 0xFFFFFFFF, 20, 4);
    glow.setPosition(-6, -6);
    glow.visible = false;
    add(glow);

    base = QOLTheme.buttonGraphic(w, h, tool.color, false);
    add(base);
    baseLit = QOLTheme.buttonGraphic(w, h, tool.color, true);
    baseLit.visible = false;
    add(baseLit);

    // A little grid scrolling diagonally across the face.
    grid = QOLTheme.scrollGrid(w, h);
    add(grid);

    art = new FlxSprite();
    var customKey = 'qol/hub/${tool.id}';
    var artSize = h - 42;
    if (Assets.exists(Paths.image(customKey)))
    {
      // Custom tile icon (optionally animated with a Sparrow XML containing `idle` / `selected`).
      if (Assets.exists(Paths.file('images/$customKey.xml')))
      {
        art.frames = Paths.getSparrowAtlas(customKey);
        art.animation.addByPrefix('idle', 'idle', 24, true);
        art.animation.addByPrefix('selected', 'selected', 24, true);
        if (art.animation.getByName('idle') != null) art.animation.play('idle');
        hasSelectedAnim = art.animation.getByName('selected') != null;
      }
      else
      {
        art.loadGraphic(Paths.image(customKey));
      }
      art.setGraphicSize(artSize + 8, artSize + 8);
      art.updateHitbox();
      art.antialiasing = true;
    }
    else if (tool.art != null) QOLTheme.loadIcon(art, tool.art, artSize);
    artScale = art.scale.x;
    art.setPosition((w - art.width) / 2, 6);
    artBaseY = art.y;
    add(art);

    nameText = QOLTheme.outlinedText(4, 0, w - 8, tool.name, 14, FlxColor.WHITE, 2);
    nameText.alignment = CENTER;
    if (nameText.height > 24) nameText.size = 12;
    // Local position (the group offsets members when they're added).
    nameText.y = h - 8 - nameText.height - 3;
    add(nameText);

    lockText = QOLTheme.outlinedText(4, 6, w - 10, 'needs a mod', 10, QOLTheme.ACCENT_YELLOW, 1.5);
    lockText.alignment = RIGHT;
    lockText.visible = false;
    add(lockText);
  }

  function set_locked(value:Bool):Bool
  {
    locked = value;
    applyState();
    return value;
  }

  /**
   * Re-applies which layers are shown. Needed after anything that toggles the whole group's visibility.
   */
  function applyState():Void
  {
    if (base == null) return;
    glow.visible = isSelected;
    baseLit.visible = isSelected;
    base.visible = !isSelected;
    lockText.visible = locked;
    grid.visible = true;
    grid.alpha = locked ? 0.35 : (isSelected ? 1 : 0.75);
    art.alpha = locked ? 0.55 : 1;
    base.color = locked ? 0xFFA8A8B8 : FlxColor.WHITE;
  }

  public function isHovered(cam:flixel.FlxCamera):Bool
  {
    return FlxG.mouse.overlaps(base, cam);
  }

  public function setSelected(value:Bool)
  {
    if (isSelected == value) return;
    isSelected = value;
    if (visible) applyState();
    if (hasSelectedAnim) art.animation.play(value ? 'selected' : 'idle');
    if (value)
    {
      pop = 1;
      tilt = FlxG.random.bool() ? 1 : -1;
    }
  }

  public function beatHit(beat:Int)
  {
    pop = isSelected ? 1 : 0.5;
    if (isSelected) tilt = beat % 2 == 0 ? 1 : -1;
  }

  public function confirm()
  {
    pop = 1.6;
    flixel.effects.FlxFlicker.flicker(art, 0.45, 0.06, true);
    flixel.effects.FlxFlicker.flicker(nameText, 0.45, 0.06, true);
  }

  public function introPop(delay:Float)
  {
    introOffset = 36;
    visible = false;
    FlxTween.num(36, 0, 0.45, {
      ease: FlxEase.backOut,
      startDelay: delay,
      onStart: _ -> {
        visible = true;
        applyState();
      }
    }, v -> introOffset = v);
  }

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);

    pop = Math.max(0, pop - elapsed * 4);
    var s = artScale * (1 + (isSelected ? 0.14 : 0.06) * pop);
    art.scale.set(s, s);
    art.angle = isSelected ? tilt * 9 * pop : 0;

    var targetLift = isSelected ? -7.0 : 0.0;
    if (Math.abs(lift - targetLift) > 0.05) lift = FlxMath.lerp(lift, targetLift, Math.min(1, elapsed * 14));
    else
      lift = targetLift;
    var targetY = baseY + lift + introOffset;
    if (y != targetY) y = targetY;
  }
}
#end
