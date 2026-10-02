package funkin.qol.ui;

#if FEATURE_HAXEUI
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.addons.display.FlxGridOverlay;
import flixel.addons.transition.FlxTransitionableState;
import flixel.math.FlxPoint;
import funkin.audio.FunkinSound;
import funkin.graphics.FunkinCamera;
import funkin.input.Cursor;
import funkin.qol.util.QOLFS;
import haxe.ui.backend.flixel.UIState;
import haxe.ui.components.Label;
import haxe.ui.components.TextField;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ListView;
import haxe.ui.containers.ScrollView;
import haxe.ui.containers.VBox;
import haxe.ui.containers.dialogs.Dialog;
import haxe.ui.containers.dialogs.Dialogs;
import haxe.ui.containers.dialogs.MessageBox.MessageBoxType;
import haxe.ui.containers.menus.Menu;
import haxe.ui.containers.menus.MenuBar;
import haxe.ui.containers.menus.MenuCheckBox;
import haxe.ui.containers.menus.MenuItem;
import haxe.ui.containers.menus.MenuSeparator;
import haxe.ui.containers.windows.WindowManager;
import haxe.ui.core.Screen;
import haxe.ui.data.ArrayDataSource;
import haxe.ui.focus.FocusManager;
import haxe.ui.notifications.NotificationManager;
import haxe.ui.notifications.NotificationType;

/**
 * Base class for every QOL Slice editor.
 *
 * Gives each editor the same V-Slice-style frame: a menu bar at the top, docked side panels,
 * a status bar, notifications, dialogs, a grid background, a zoomable "world" camera and
 * helpers for saving straight into the active mod.
 */
class QOLEditorState extends UIState
{
  public static final MENUBAR_HEIGHT:Int = 32;
  public static final STATUSBAR_HEIGHT:Int = 26;

  /**
   * Camera for the thing being edited (characters, stages, menus...).
   */
  public var camWorld:FunkinCamera;

  /**
   * Camera for HaxeUI and overlays.
   */
  public var camUI:FlxCamera;

  public var menubar:MenuBar;
  public var statusLabel:Label;
  public var statusRight:Label;
  public var leftPanel:Null<VBox> = null;
  public var rightPanel:Null<VBox> = null;

  var gridBG:FlxSprite;

  /**
   * Shown in the window title and menus.
   */
  public var editorName:String = 'Editor';

  /**
   * Set to true when there are unsaved changes.
   */
  public var dirty(default, set):Bool = false;

  function set_dirty(value:Bool):Bool
  {
    dirty = value;
    updateWindowTitle();
    return value;
  }

  /**
   * Width of the docked panels (0 = no panel).
   */
  public var leftPanelWidth:Int = 0;

  public var rightPanelWidth:Int = 0;

  public function new()
  {
    super();
  }

  override public function create():Void
  {
    WindowManager.instance.reset();
    FlxTransitionableState.skipNextTransIn = true;
    FlxTransitionableState.skipNextTransOut = true;

    camWorld = new FunkinCamera('qolEditorWorld');
    camUI = new FlxCamera();
    camUI.bgColor.alpha = 0;
    FlxG.cameras.reset(camWorld);
    FlxG.cameras.add(camUI, false);
    FlxG.cameras.setDefaultDrawTarget(camWorld, true);
    camWorld.bgColor = 0xFF202124;

    persistentUpdate = false;

    gridBG = FlxGridOverlay.create(20, 20, FlxG.width * 2, FlxG.height * 2, true, 0xFF232428, 0xFF27292E);
    gridBG.scrollFactor.set();
    gridBG.cameras = [camWorld];
    add(gridBG);

    super.create();

    root.scrollFactor.set();
    root.cameras = [camUI];
    root.width = FlxG.width;
    root.height = FlxG.height;
    WindowManager.instance.container = root;
    Screen.instance.addComponent(root);

    buildFrame();
    buildEditor();
    updateWindowTitle();

    Cursor.show();
    FlxG.mouse.visible = true;
  }

  /**
   * Builds the menu bar, status bar and side panels.
   */
  function buildFrame():Void
  {
    menubar = new MenuBar();
    menubar.percentWidth = 100;
    menubar.height = MENUBAR_HEIGHT;
    root.addComponent(menubar);

    var status = new HBox();
    status.percentWidth = 100;
    status.height = STATUSBAR_HEIGHT;
    status.top = FlxG.height - STATUSBAR_HEIGHT;
    status.styleString = 'background-color: #1E1F22; border-top: 1px solid #3A3F47; padding-left: 8px; padding-right: 8px; padding-top: 4px;';
    statusLabel = new Label();
    statusLabel.percentWidth = 70;
    status.addComponent(statusLabel);
    statusRight = new Label();
    statusRight.percentWidth = 30;
    statusRight.styleString = 'text-align: right;';
    status.addComponent(statusRight);
    root.addComponent(status);
    updateModStatus();

    if (leftPanelWidth > 0) leftPanel = makePanel(0, leftPanelWidth);
    if (rightPanelWidth > 0) rightPanel = makePanel(FlxG.width - rightPanelWidth, rightPanelWidth);

    // Common menu: the "QOL Slice" menu with navigation helpers.
    var qolMenu = addMenu('QOL Slice');
    addMenuItem(qolMenu, 'Back to Mod Menu', 'Esc', () -> exitEditor());
    addMenuItem(qolMenu, 'Open Mod Folder', null, () -> QOLFS.openInExplorer(ModWorkspace.modFolder));
    addMenuItem(qolMenu, 'Reload Game Data', 'F5', () -> {
      ModWorkspace.reloadGameData();
      notify('Reloaded', 'All mods and data were reloaded.');
    });
    addMenuItem(qolMenu, 'Guide for this editor', 'F1', () -> openGuide());
  }

  function makePanel(x:Float, width:Int):VBox
  {
    var scroll = new ScrollView();
    scroll.left = x;
    scroll.top = MENUBAR_HEIGHT;
    scroll.width = width;
    scroll.height = FlxG.height - MENUBAR_HEIGHT - STATUSBAR_HEIGHT;
    scroll.styleString = 'background-color: #2B2D31; border: 1px solid #3A3F47; padding: 8px;';
    scroll.horizontalScrollPolicy = 'never';
    var content = new VBox();
    content.width = width - 28;
    content.styleString = 'spacing: 6px;';
    scroll.addComponent(content);
    root.addComponent(scroll);
    return content;
  }

  /**
   * Override to build the editor's UI and content.
   */
  function buildEditor():Void {}

  /**
   * Override to save. Return true if the save succeeded.
   */
  function save():Bool
  {
    return true;
  }

  /**
   * Called by Ctrl+S.
   */
  public function doSave():Void
  {
    if (!ModWorkspace.hasMod)
    {
      alert('No mod selected', 'Choose or create a mod in the Mod Menu first. Everything you make is saved straight into that mod\'s folder.');
      return;
    }
    try
    {
      if (save())
      {
        dirty = false;
        if (QOLConfig.autoReload) afterSaveReload();
      }
    }
    catch (e)
    {
      alert('Save failed', Std.string(e));
    }
  }

  /**
   * Called after a successful save when auto-reload is on.
   * Editors that hold registry objects can override this to re-fetch them.
   */
  function afterSaveReload():Void
  {
    ModWorkspace.reloadGameData();
  }

  function updateWindowTitle():Void
  {
    funkin.util.WindowUtil.setWindowTitle('QOL Slice - $editorName${dirty ? ' *' : ''} - ${ModWorkspace.current ?? 'no mod selected'}');
  }

  public function updateModStatus():Void
  {
    if (statusRight != null) statusRight.text = 'Mod: ${ModWorkspace.current ?? '(none)'}';
  }

  public function setStatus(text:String):Void
  {
    if (statusLabel != null) statusLabel.text = text;
  }

  //
  // Menu helpers
  //

  public function addMenu(text:String):Menu
  {
    var menu = new Menu();
    menu.text = text;
    menubar.addComponent(menu);
    return menu;
  }

  public function addSubMenu(parent:Menu, text:String):Menu
  {
    var menu = new Menu();
    menu.text = text;
    parent.addComponent(menu);
    return menu;
  }

  public function addMenuItem(menu:Menu, text:String, ?shortcut:String, cb:Void->Void):MenuItem
  {
    var item = new MenuItem();
    item.text = text;
    if (shortcut != null) item.shortcutText = shortcut;
    item.onClick = function(_) {
      try
      {
        cb();
      }
      catch (e)
      {
        alert('Error', Std.string(e));
      }
    };
    menu.addComponent(item);
    return item;
  }

  public function addMenuCheck(menu:Menu, text:String, value:Bool, cb:Bool->Void):MenuCheckBox
  {
    var item = new MenuCheckBox();
    item.text = text;
    item.selected = value;
    item.onChange = _ -> cb(item.selected);
    menu.addComponent(item);
    return item;
  }

  public function addMenuSeparator(menu:Menu):Void
  {
    menu.addComponent(new MenuSeparator());
  }

  //
  // Dialog helpers
  //

  public function notify(title:String, body:String, ?type:NotificationType):Void
  {
    NotificationManager.instance.addNotification({
      title: title,
      body: body,
      type: type ?? NotificationType.Info,
      expiryMs: 3500
    });
  }

  public function notifySaved(path:String):Void
  {
    notify('Saved', path, NotificationType.Success);
    setStatus('Saved to $path');
  }

  public function alert(title:String, message:String):Void
  {
    Dialogs.messageBox(message, title, MessageBoxType.TYPE_WARNING, true);
  }

  public function confirm(title:String, message:String, onYes:Void->Void, ?onNo:Void->Void):Void
  {
    Dialogs.messageBox(message, title, MessageBoxType.TYPE_QUESTION, true, function(button) {
      if (button == DialogButton.YES || button == DialogButton.OK) onYes();
      else if (onNo != null) onNo();
    });
  }

  /**
   * Ask for a line of text.
   */
  public function prompt(title:String, label:String, defaultText:String, onOk:String->Void):Void
  {
    var dialog = new Dialog();
    dialog.title = title;
    dialog.buttons = DialogButton.CANCEL | DialogButton.OK;
    dialog.defaultButton = '{{ok}}';
    dialog.destroyOnClose = true;
    var box = new VBox();
    box.styleString = 'spacing: 6px;';
    var l = new Label();
    l.text = label;
    box.addComponent(l);
    var field = new TextField();
    field.width = 320;
    field.text = defaultText ?? '';
    box.addComponent(field);
    dialog.addComponent(box);
    dialog.onDialogClosed = function(e) {
      if (e.button == DialogButton.OK) onOk(field.text ?? '');
    };
    dialog.showDialog(true);
    field.focus = true;
  }

  /**
   * Pick an item from a searchable list.
   */
  public function chooseFromList(title:String, items:Array<String>, onPick:String->Void, ?current:String):Void
  {
    var dialog = new Dialog();
    dialog.title = title;
    dialog.buttons = DialogButton.CANCEL | DialogButton.OK;
    dialog.defaultButton = '{{ok}}';
    dialog.destroyOnClose = true;
    var box = new VBox();
    box.styleString = 'spacing: 6px;';
    var search = new TextField();
    search.placeholder = 'Search...';
    search.width = 360;
    box.addComponent(search);
    var list = new ListView();
    list.width = 360;
    list.height = 360;
    box.addComponent(list);
    function fill(filter:String)
    {
      var ds = new ArrayDataSource<Dynamic>();
      for (item in items)
        if (filter == '' || item.toLowerCase().indexOf(filter.toLowerCase()) != -1) ds.add({text: item});
      list.dataSource = ds;
      if (current != null)
      {
        for (i in 0...ds.size)
          if (ds.get(i).text == current) list.selectedIndex = i;
      }
    }
    fill('');
    search.onChange = _ -> fill(search.text ?? '');
    list.onDblClick = function(_) {
      if (list.selectedItem != null) dialog.hideDialog(DialogButton.OK);
    };
    dialog.addComponent(box);
    dialog.onDialogClosed = function(e) {
      if (e.button == DialogButton.OK && list.selectedItem != null) onPick(list.selectedItem.text);
    };
    dialog.showDialog(true);
    search.focus = true;
  }

  /**
   * Pick an image (or any file) from the active mod or from the game's assets.
   * `onPick` receives an asset key such as `characters/bf` (for images) or a relative path.
   */
  public function browseModFile(title:String, folder:String, extensions:Array<String>, onPick:String->Void, ?allowImport:Bool = true):Void
  {
    FileBrowser.open(this, title, folder, extensions, onPick, allowImport);
  }

  //
  // Input helpers
  //

  /**
   * True if the user is typing into a text field (so editor shortcuts should be ignored).
   */
  public var isTyping(get, never):Bool;

  function get_isTyping():Bool
  {
    var focus = FocusManager.instance.focus;
    if (focus == null) return false;
    return Std.isOfType(focus, TextField) || Std.isOfType(focus, haxe.ui.components.TextArea)
      || Std.isOfType(focus, haxe.ui.components.NumberStepper);
  }

  /**
   * True if the mouse is over any HaxeUI panel/menu/dialog.
   */
  public var mouseOverUI(get, never):Bool;

  function get_mouseOverUI():Bool
  {
    return Screen.instance.hasSolidComponentUnderPoint(Screen.instance.currentMouseX, Screen.instance.currentMouseY);
  }

  /**
   * True while a modal dialog is open.
   */
  public var dialogOpen(get, never):Bool;

  function get_dialogOpen():Bool
  {
    @:privateAccess
    for (c in Screen.instance.rootComponents)
      if (Std.isOfType(c, Dialog)) return true;
    return false;
  }

  public inline function ctrl():Bool
    return FlxG.keys.pressed.CONTROL #if mac || FlxG.keys.pressed.WINDOWS #end;

  /**
   * Mouse position in the world camera.
   */
  public function worldMouse():FlxPoint
  {
    return FlxG.mouse.getWorldPosition(camWorld);
  }

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);

    // Escape closes the top dialog first (and nothing else that frame).
    if (FlxG.keys.justPressed.ESCAPE && QOLDialogs.closeTop()) return;

    if (!isTyping && !dialogOpen)
    {
      if (ctrl() && FlxG.keys.justPressed.S) doSave();
      if (FlxG.keys.justPressed.F1) openGuide();
      if (FlxG.keys.justPressed.F5)
      {
        ModWorkspace.reloadGameData();
        notify('Reloaded', 'All mods and data were reloaded.');
      }
      if (FlxG.keys.justPressed.ESCAPE) exitEditor();
      handleShortcuts();
    }
  }

  /**
   * Override for editor-specific keyboard shortcuts (only called while not typing).
   */
  function handleShortcuts():Void {}

  /**
   * Which guide page F1 opens.
   */
  function guidePage():String
  {
    return 'welcome';
  }

  public function openGuide():Void
  {
    funkin.qol.guide.GuideState.openOver(this, guidePage());
  }

  public function exitEditor():Void
  {
    if (dirty) confirm('Unsaved changes', 'You have unsaved changes. Leave anyway?', () -> leave());
    else
      leave();
  }

  function leave():Void
  {
    funkin.util.WindowUtil.setWindowTitle(QOLSlice.WINDOW_TITLE);
    FlxG.switchState(() -> new funkin.qol.menu.QOLModMenuState());
  }

  /**
   * Plays the chart editor click sounds.
   */
  function clickSound(down:Bool):Void
  {
    FunkinSound.playOnce(Paths.sound(down ? 'chartingSounds/ClickDown' : 'chartingSounds/ClickUp'), 0.5);
  }

  //
  // Playtesting
  //

  /**
   * True from the moment a playtest is requested until it closes. Subclass updates should skip their work while it's set.
   */
  public var playtestPending(default, null):Bool = false;

  var playtestCameras:Array<FlxCamera> = [];
  var playtestDefaultCameras:Array<FlxCamera> = [];
  var playtestOnClosed:Null<Void->Void> = null;
  var playtestPrevPersistentUpdate:Bool = false;

  /**
   * Play a song in a PlayState opened on top of this editor (pause > "Return to Chart Editor" comes back here).
   * The editor's cameras are kept alive while the PlayState replaces them.
   */
  function openPlaytest(params:funkin.play.PlayState.PlayStateParams, ?onConstruct:funkin.play.PlayState->Void, ?onClosed:Void->Void):Void
  {
    playtestCameras = FlxG.cameras.list.copy();
    @:privateAccess playtestDefaultCameras = FlxG.cameras.defaults.copy();
    for (c in playtestCameras)
      FlxG.cameras.remove(c, false);
    FlxG.cameras.reset(new FunkinCamera('qolPlaytestTemp'));
    playtestPrevPersistentUpdate = persistentUpdate;
    persistentUpdate = false;
    persistentDraw = false;
    playtestPending = true;
    playtestOnClosed = onClosed;
    // A plain listener (removed when the PlayState closes): web builds close a LoadingState first, and re-adding a
    // one-shot listener from inside its own dispatch gets it dropped.
    subStateClosed.add(onPlaytestSubStateClosed);
    funkin.ui.transition.LoadingState.loadPlayState(params, false, true, onConstruct);
  }

  function onPlaytestSubStateClosed(closed:flixel.FlxSubState):Void
  {
    // Web builds open a LoadingState first, which then hands over to the PlayState.
    if (Std.isOfType(closed, funkin.ui.transition.LoadingState)) return;
    subStateClosed.remove(onPlaytestSubStateClosed);
    playtestPending = false;
    FlxG.sound.music?.stop();
    if (playtestCameras.length > 0)
    {
      FlxG.cameras.reset(playtestCameras[0]);
      FlxG.cameras.setDefaultDrawTarget(playtestCameras[0], playtestDefaultCameras.contains(playtestCameras[0]));
      for (i in 1...playtestCameras.length)
        FlxG.cameras.add(playtestCameras[i], playtestDefaultCameras.contains(playtestCameras[i]));
    }
    persistentUpdate = playtestPrevPersistentUpdate;
    persistentDraw = true;
    Cursor.show();
    FlxG.mouse.visible = true;
    updateWindowTitle();
    if (playtestOnClosed != null) playtestOnClosed();
  }

  override public function destroy():Void
  {
    WindowManager.instance.reset();
    super.destroy();
  }
}
#end
