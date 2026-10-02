package funkin.qol.ui;

#if FEATURE_HAXEUI
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.addons.display.FlxGridOverlay;
import flixel.addons.transition.FlxTransitionableState;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
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

  /**
   * Titles shown on the two standard panels' title bars.
   */
  public var leftPanelTitle:String = 'Properties';

  public var rightPanelTitle:String = 'Inspector';

  /**
   * Every movable panel in this editor.
   */
  public var panels(default, null):Array<QOLDockPanel> = [];

  var leftDock:Array<QOLDockPanel> = [];
  var rightDock:Array<QOLDockPanel> = [];

  /**
   * The free area between the docked panels (screen x). Use these (not the panel widths) to center things in the
   * editor's view: they change when panels are moved, resized, collapsed or floated.
   */
  public var workLeft(default, null):Float = 0;

  public var workRight(default, null):Float = 0;

  /**
   * An area along the bottom that the editor owns (a timeline, say). Docked panels stop above it. If
   * `bottomAreaResizable` is on, the border above it can be dragged to resize it.
   */
  public var bottomAreaHeight:Float = 0;

  public var bottomAreaResizable:Bool = false;
  public var bottomAreaMin:Float = 120;

  /**
   * Bottom of the work area (screen y).
   */
  public var workBottom(default, null):Float = 0;

  /**
   * True while a panel is being dragged or resized (editors should ignore the mouse).
   */
  public var panelInteracting(default, null):Bool = false;

  public function new()
  {
    // Like every V-Slice state: pick up a window resize from the previous screen so the editor lays itself out for
    // the window's real size.
    if (funkin.ui.FullScreenScaleMode.instance != null) funkin.ui.FullScreenScaleMode.instance.onMeasurePostAwait();
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
    defaultBottomAreaHeight = bottomAreaHeight;
    loadLayout();
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

    workLeft = 0;
    workRight = FlxG.width;
    workBottom = FlxG.height - STATUSBAR_HEIGHT - bottomAreaHeight;
    if (leftPanelWidth > 0) leftPanel = addDockPanel('left', leftPanelTitle, leftPanelWidth, 'left').content;
    if (rightPanelWidth > 0) rightPanel = addDockPanel('right', rightPanelTitle, rightPanelWidth, 'right').content;

    // Common menu: the "QOL Slice" menu with navigation helpers.
    var qolMenu = addMenu('QOL Slice');
    addMenuItem(qolMenu, 'Back to Mod Menu', 'Esc', () -> exitEditor());
    addMenuItem(qolMenu, 'Open Mod Folder', null, () -> QOLFS.openInExplorer(ModWorkspace.modFolder));
    addMenuItem(qolMenu, 'Reload Game Data', 'F5', () -> {
      ModWorkspace.reloadGameData();
      notify('Reloaded', 'All mods and data were reloaded.');
    });
    addMenuItem(qolMenu, 'Guide for this editor', 'F1', () -> openGuide());
    addMenuSeparator(qolMenu);
    addMenuItem(qolMenu, 'Reset Panel Layout', null, () -> resetLayout());
  }

  //
  // Movable panels
  //

  /**
   * Add a movable panel. `side` is 'left', 'right' or 'float'. Put your controls in the returned panel's `content`.
   */
  public function addDockPanel(id:String, title:String, width:Int, side:String):QOLDockPanel
  {
    var panel = new QOLDockPanel(id, title, width, side);
    panel.onToggleCollapse = p -> {
      p.collapsed = !p.collapsed;
      layoutPanels();
      saveLayout();
    };
    panel.onToggleFloat = p -> {
      if (p.isFloating) dockPanel(p, p.defaultSide == 'float' ? 'right' : p.defaultSide);
      else
        floatPanel(p, workLeft + (workRight - workLeft - p.panelWidth) / 2, MENUBAR_HEIGHT + 40);
      saveLayout();
    };
    panels.push(panel);
    if (side == 'left') leftDock.push(panel);
    else if (side == 'right') rightDock.push(panel);
    else
    {
      panel.floatX = (FlxG.width - width) / 2;
      panel.floatY = MENUBAR_HEIGHT + 40;
    }
    root.addComponent(panel);
    layoutPanels();
    return panel;
  }

  function availableHeight():Float
    return FlxG.height - MENUBAR_HEIGHT - STATUSBAR_HEIGHT - bottomAreaHeight;

  function maxBottomArea():Float
    return FlxG.height - MENUBAR_HEIGHT - STATUSBAR_HEIGHT - 160;

  /**
   * Position every panel. Docked panels stack from the screen edges inwards; the space between them is the editor's
   * work area (`workLeft`...`workRight`).
   */
  public function layoutPanels():Void
  {
    var top = MENUBAR_HEIGHT;
    var h = availableHeight();
    var x = 0.0;
    for (p in leftDock)
    {
      var w = p.shownWidth();
      p.place(x, top, w, h);
      x += w;
    }
    var rx:Float = FlxG.width;
    for (p in rightDock)
    {
      var w = p.shownWidth();
      rx -= w;
      p.place(rx, top, w, h);
    }
    for (p in panels)
    {
      if (!p.isFloating) continue;
      var ph = p.collapsed ? QOLDockPanel.HEADER_HEIGHT + 2 : Math.min(p.floatHeight, h);
      p.floatX = FlxMath.bound(p.floatX, -p.panelWidth + 80, FlxG.width - 80);
      p.floatY = FlxMath.bound(p.floatY, top, FlxG.height - STATUSBAR_HEIGHT - QOLDockPanel.HEADER_HEIGHT);
      p.place(p.floatX, p.floatY, p.panelWidth, ph);
    }
    var bottom = FlxG.height - STATUSBAR_HEIGHT - bottomAreaHeight;
    if (x != workLeft || rx != workRight || bottom != workBottom)
    {
      workLeft = x;
      workRight = rx;
      workBottom = bottom;
      onLayoutChanged();
    }
  }

  /**
   * Called when the work area changes (a panel was moved, resized, collapsed or floated). Override to re-center
   * things that depend on it.
   */
  function onLayoutChanged():Void {}

  function dockPanel(p:QOLDockPanel, side:String):Void
  {
    leftDock.remove(p);
    rightDock.remove(p);
    p.side = side;
    if (side == 'left') leftDock.insert(0, p);
    else
      rightDock.insert(0, p);
    p.collapsed = p.collapsed; // refresh header buttons for the new side
    layoutPanels();
  }

  function floatPanel(p:QOLDockPanel, x:Float, y:Float):Void
  {
    leftDock.remove(p);
    rightDock.remove(p);
    p.side = 'float';
    p.floatX = x;
    p.floatY = y;
    p.floatHeight = Math.min(p.floatHeight, availableHeight());
    p.collapsed = p.collapsed;
    bringToFront(p);
    layoutPanels();
  }

  function bringToFront(p:QOLDockPanel):Void
  {
    if (root.childComponents.indexOf(p) >= 0) root.setComponentIndex(p, root.childComponents.length - 1);
  }

  //
  // Panel dragging and resizing
  //

  static inline final EDGE_GRAB:Float = 4;
  static inline final UNDOCK_DISTANCE:Float = 8;
  static inline final DOCK_ZONE:Float = 48;

  var dragPanel:Null<QOLDockPanel> = null;
  var dragStartX:Float = 0;
  var dragStartY:Float = 0;
  var dragOffsetX:Float = 0;
  var dragOffsetY:Float = 0;
  var dragMoved:Bool = false;
  var resizePanel:Null<QOLDockPanel> = null;
  var resizeEdge:String = '';
  var resizingArea:Bool = false;
  var dockPreview:Null<FlxSprite> = null;
  var dockPreviewSide:String = '';
  var panelCursorSet:Bool = false;

  function minPanelWidth(p:QOLDockPanel):Int
    return Std.int(Math.max(180, p.naturalWidth * 0.6));

  function maxPanelWidth(p:QOLDockPanel):Int
    return Std.int(Math.max(p.naturalWidth, Math.min(p.naturalWidth * 2.2, FlxG.width * 0.5)));

  /**
   * Which resize edge of which panel is under the mouse ('right', 'left', 'bottom' or 'corner').
   */
  function edgeAt(x:Float, y:Float):Null<{panel:Null<QOLDockPanel>, edge:String}>
  {
    if (bottomAreaResizable && Math.abs(y - workBottom) <= EDGE_GRAB && x >= workLeft && x <= workRight)
    {
      // Floating panels over the border win.
      var overFloating = false;
      for (p in panels)
        if (p.isFloating && p.contains(x, y)) overFloating = true;
      if (!overFloating) return {panel: null, edge: 'area'};
    }
    var order = panels.copy();
    order.sort((a, b) -> (b.isFloating ? 1 : 0) - (a.isFloating ? 1 : 0));
    for (p in order)
    {
      if (p.collapsed || p.hidden) continue;
      var l = p.screenLeft;
      var t = p.screenTop;
      var r = l + p.width;
      var b = t + p.height;
      if (p.isFloating)
      {
        var nearR = x >= r - EDGE_GRAB && x <= r + EDGE_GRAB && y >= t && y <= b + EDGE_GRAB;
        var nearB = y >= b - EDGE_GRAB && y <= b + EDGE_GRAB && x >= l && x <= r + EDGE_GRAB;
        if (nearR && nearB) return {panel: p, edge: 'corner'};
        if (nearR) return {panel: p, edge: 'right'};
        if (nearB) return {panel: p, edge: 'bottom'};
      }
      else if (y >= t && y <= b)
      {
        if (p.side == 'left' && x >= r - 2 && x <= r + EDGE_GRAB + 1) return {panel: p, edge: 'right'};
        if (p.side == 'right' && x >= l - EDGE_GRAB - 1 && x <= l + 2) return {panel: p, edge: 'left'};
      }
    }
    return null;
  }

  function topPanelHeaderAt(x:Float, y:Float):Null<QOLDockPanel>
  {
    var found:Null<QOLDockPanel> = null;
    // Floating panels sit on top of docked ones; later children draw on top.
    for (c in root.childComponents)
    {
      if (!Std.isOfType(c, QOLDockPanel)) continue;
      var p:QOLDockPanel = cast c;
      if (p.headerHit(x, y)) found = p;
    }
    return found;
  }

  function updatePanelInteraction():Void
  {
    if (panels.length == 0) return;
    var pos = FlxG.mouse.getViewPosition(camUI);
    var mx = pos.x;
    var my = pos.y;
    pos.put();

    if (resizingArea)
    {
      bottomAreaHeight = FlxMath.bound(FlxG.height - STATUSBAR_HEIGHT - my, bottomAreaMin, maxBottomArea());
      layoutPanels();
      if (!FlxG.mouse.pressed)
      {
        resizingArea = false;
        saveLayout();
      }
      setPanelCursor(true);
      panelInteracting = true;
      return;
    }

    if (resizePanel != null)
    {
      var p = resizePanel;
      if (resizeEdge == 'right' || resizeEdge == 'corner')
        p.panelWidth = Std.int(FlxMath.bound(mx - p.screenLeft, minPanelWidth(p), maxPanelWidth(p)));
      if (resizeEdge == 'left')
        p.panelWidth = Std.int(FlxMath.bound(p.screenLeft + p.width - mx, minPanelWidth(p), maxPanelWidth(p)));
      if (resizeEdge == 'bottom' || resizeEdge == 'corner')
        p.floatHeight = FlxMath.bound(my - p.screenTop, 120, availableHeight());
      layoutPanels();
      if (!FlxG.mouse.pressed)
      {
        resizePanel = null;
        saveLayout();
      }
      setPanelCursor(true);
      panelInteracting = true;
      return;
    }

    if (dragPanel != null)
    {
      var p = dragPanel;
      if (!dragMoved && Math.abs(mx - dragStartX) + Math.abs(my - dragStartY) >= UNDOCK_DISTANCE)
      {
        dragMoved = true;
        if (!p.isFloating)
        {
          // Keep the grab point under the mouse, but don't let a tall docked panel stay full height.
          floatPanel(p, mx - dragOffsetX, my - dragOffsetY);
          p.floatHeight = Math.min(p.floatHeight, availableHeight() - 60);
        }
        bringToFront(p);
      }
      if (dragMoved)
      {
        p.floatX = mx - dragOffsetX;
        p.floatY = my - dragOffsetY;
        layoutPanels();
        dockPreviewSide = mx <= workLeft + DOCK_ZONE ? 'left' : (mx >= workRight - DOCK_ZONE ? 'right' : '');
        showDockPreview(dockPreviewSide, p);
      }
      if (!FlxG.mouse.pressed)
      {
        if (dragMoved && dockPreviewSide != '') dockPanel(p, dockPreviewSide);
        dragPanel = null;
        showDockPreview('', p);
        if (dragMoved) saveLayout();
      }
      setPanelCursor(dragMoved);
      panelInteracting = dragMoved;
      return;
    }

    panelInteracting = false;
    if (dialogOpen)
    {
      setPanelCursor(false);
      return;
    }
    var edge = edgeAt(mx, my);
    setPanelCursor(edge != null);
    if (FlxG.mouse.justPressed)
    {
      if (edge != null)
      {
        if (edge.edge == 'area') resizingArea = true;
        else
        {
          resizePanel = edge.panel;
          resizeEdge = edge.edge;
        }
        panelInteracting = true;
        return;
      }
      var p = topPanelHeaderAt(mx, my);
      if (p != null)
      {
        dragPanel = p;
        dragStartX = mx;
        dragStartY = my;
        dragOffsetX = mx - p.screenLeft;
        dragOffsetY = my - p.screenTop;
        dragMoved = false;
        if (p.isFloating) bringToFront(p);
      }
      else
      {
        // Clicking a floating panel brings it to the front.
        for (c in root.childComponents.copy())
          if (Std.isOfType(c, QOLDockPanel) && (cast c : QOLDockPanel).isFloating && (cast c : QOLDockPanel).contains(mx, my))
            bringToFront(cast c);
      }
    }
  }

  function setPanelCursor(on:Bool):Void
  {
    if (on)
    {
      Cursor.cursorMode = dragPanel != null ? Grabbing : Scroll;
      panelCursorSet = true;
    }
    else if (panelCursorSet)
    {
      Cursor.cursorMode = Default;
      panelCursorSet = false;
    }
  }

  function showDockPreview(side:String, p:QOLDockPanel):Void
  {
    if (dockPreview == null)
    {
      dockPreview = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
      dockPreview.color = 0xFF5CE1FF;
      dockPreview.alpha = 0.22;
      dockPreview.cameras = [camUI];
      dockPreview.scrollFactor.set();
      add(dockPreview);
    }
    dockPreview.visible = side != '';
    if (side == '') return;
    var w = p.panelWidth;
    dockPreview.setGraphicSize(w, Std.int(availableHeight()));
    dockPreview.updateHitbox();
    dockPreview.setPosition(side == 'left' ? workLeft : workRight - w, MENUBAR_HEIGHT);
    // Keep it above the HaxeUI root.
    remove(dockPreview, true);
    add(dockPreview);
  }

  //
  // Saving the layout
  //

  function layoutPrefKey():String
    return 'layout.' + editorName;

  function saveLayout():Void
  {
    var out:Array<Dynamic> = [];
    for (p in panels)
    {
      out.push({
        id: p.panelId,
        side: p.side,
        order: p.side == 'left' ? leftDock.indexOf(p) : (p.side == 'right' ? rightDock.indexOf(p) : 0),
        width: p.panelWidth,
        collapsed: p.collapsed,
        x: Math.round(p.floatX),
        y: Math.round(p.floatY),
        h: Math.round(p.floatHeight)
      });
    }
    if (bottomAreaResizable) out.push({id: '__bottom', h: Math.round(bottomAreaHeight)});
    QOLConfig.setPref(layoutPrefKey(), haxe.Json.stringify(out));
  }

  function loadLayout():Void
  {
    var raw:String = QOLConfig.getPref(layoutPrefKey(), '');
    if (raw == null || raw == '') return;
    try
    {
      var saved:Array<Dynamic> = haxe.Json.parse(raw);
      saved.sort((a, b) -> Std.int(a.order) - Std.int(b.order));
      leftDock = [];
      rightDock = [];
      var seen:Array<QOLDockPanel> = [];
      for (s in saved)
      {
        if (s.id == '__bottom')
        {
          if (bottomAreaResizable && s.h != null) bottomAreaHeight = FlxMath.bound(s.h, bottomAreaMin, maxBottomArea());
          continue;
        }
        var p = Lambda.find(panels, x -> x.panelId == s.id);
        if (p == null) continue;
        seen.push(p);
        p.panelWidth = Std.int(FlxMath.bound(s.width ?? p.naturalWidth, minPanelWidth(p), maxPanelWidth(p)));
        p.side = s.side ?? p.defaultSide;
        p.floatX = s.x ?? p.floatX;
        p.floatY = s.y ?? p.floatY;
        p.floatHeight = s.h ?? p.floatHeight;
        p.collapsed = s.collapsed == true;
        if (p.side == 'left') leftDock.push(p);
        else if (p.side == 'right') rightDock.push(p);
      }
      // Panels this editor didn't have when the layout was saved go to their usual place.
      for (p in panels)
      {
        if (seen.contains(p)) continue;
        if (p.side == 'left') leftDock.push(p);
        else if (p.side == 'right') rightDock.push(p);
      }
      layoutPanels();
    }
    catch (e)
    {
      trace('[QOL] Could not restore the panel layout: $e');
    }
  }

  /**
   * The editor's starting bottom area height (Reset Layout goes back to it).
   */
  var defaultBottomAreaHeight:Float = -1;

  public function resetLayout():Void
  {
    if (defaultBottomAreaHeight >= 0) bottomAreaHeight = defaultBottomAreaHeight;
    leftDock = [];
    rightDock = [];
    for (p in panels)
    {
      p.side = p.defaultSide;
      p.panelWidth = p.naturalWidth;
      p.collapsed = false;
      if (p.side == 'left') leftDock.push(p);
      else if (p.side == 'right') rightDock.push(p);
    }
    QOLConfig.setPref(layoutPrefKey(), '');
    layoutPanels();
    notify('Layout reset', 'Panels are back where they started.');
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
    if (panelInteracting || resizePanel != null || resizingArea || dragPanel != null || panelCursorSet) return true;
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
    if (!playtestPending) updatePanelInteraction();

    // Keep the checkerboard filling the whole view at any zoom (it's a backdrop, so its squares stay the same size).
    if (gridBG != null && gridBG.visible && gridBG.scrollFactor.x == 0)
    {
      var z = camWorld.zoom > 0.01 ? camWorld.zoom : 1;
      gridBG.scale.set(1 / z, 1 / z);
      gridBG.setPosition(-FlxG.width / 2, -FlxG.height / 2);
    }

    // Escape closes the top dialog first (and nothing else that frame).
    if (FlxG.keys.justPressed.ESCAPE && (QOLDialogs.closePopups() || QOLDialogs.closeTop())) return;

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
