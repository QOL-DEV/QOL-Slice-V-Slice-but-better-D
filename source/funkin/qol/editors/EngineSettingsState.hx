package funkin.qol.editors;

#if FEATURE_HAXEUI
import funkin.qol.ui.QOLEditorState;
import funkin.qol.ui.QOLForm;
import funkin.qol.util.QOLFS;
import haxe.ui.components.Button;
import haxe.ui.components.Label;
import haxe.ui.containers.VBox;

/**
 * QOL Slice engine settings, including the "lock for release" switch that disables the Mod Menu.
 */
class EngineSettingsState extends QOLEditorState
{
  var form:QOLForm;

  public function new()
  {
    super();
    editorName = 'Engine Settings';
  }

  override function guidePage():String
    return 'settings';

  override function buildEditor():Void
  {
    gridBG.visible = false;
    camWorld.bgColor = 0xFF1B1530;

    var panel = new VBox();
    panel.left = (FlxG.width - 620) / 2;
    panel.top = QOLEditorState.MENUBAR_HEIGHT + 20;
    panel.width = 620;
    panel.styleString = 'background-color: #2B2340; border: 2px solid #5A4F80; border-radius: 10px; padding: 18px; spacing: 8px;';
    root.addComponent(panel);

    var title = new Label();
    title.text = 'QOL Slice Engine Settings';
    title.styleString = 'font-size: 22px; font-bold: true; color: #FF8FB8;';
    panel.addComponent(title);

    var info = new Label();
    info.width = 580;
    info.text = '${QOLSlice.versionString}\nSettings file: ${QOLFS.absolute(QOLConfig.CONFIG_PATH)}\nMods folder: ${QOLFS.absolute(ModWorkspace.MOD_ROOT)}';
    info.styleString = 'color: #C9C2E6;';
    panel.addComponent(info);

    form = new QOLForm(240, 320);
    form.section('Editors');
    form.check('Reload game data after saving', () -> QOLConfig.autoReload, v -> QOLConfig.autoReload = v);
    form.note('When on, saving in any editor hot-reloads every mod so the game sees your changes right away.');
    form.check('Show Legacy V-Slice tools', () -> QOLConfig.showLegacyTools, v -> QOLConfig.showLegacyTools = v);
    form.section('Menus');
    form.check('Fancy menus', () -> QOLConfig.fancyMenus, v -> QOLConfig.fancyMenus = v);
    form.note('Beat bumps, floating arrows, sparkles and intro animations in QOL Slice menus. Turn off on slow PCs.');
    form.section('Performance');
    form.check('GPU textures (saves RAM)', () -> QOLConfig.gpuTextures, v -> QOLConfig.gpuTextures = v);
    form.note('During songs, images that are already on the graphics card don\'t keep a second copy in memory. '
      + 'Turn off only if a mod\'s script needs to read image pixels in-game.');
    if (funkin.qol.util.QOLPerformance.freedTextures > 0)
    {
      form.note('This session: ${funkin.qol.util.QOLPerformance.freedTextures} images moved to the GPU, about '
        + '${Math.round(funkin.qol.util.QOLPerformance.freedBytes / 1048576)} MB of RAM saved.');
    }
    form.check('Free memory when leaving editors', () -> QOLConfig.cleanMemory, v -> QOLConfig.cleanMemory = v);
    form.note('Drops images the editors loaded for their previews and gives the memory back.');
    form.section('Releasing your mod');
    form.note('Lock the Mod Menu before you share your finished mod, so players can\'t open the editors with 7 or ~.');
    panel.addComponent(form);

    var lockButton = new Button();
    lockButton.text = 'Lock the Mod Menu for release...';
    lockButton.percentWidth = 100;
    lockButton.styleString = 'font-bold: true; color: #FFFFFF; background-color: #C2185B; border: 1px solid #FF5C9D;';
    lockButton.onClick = _ -> confirmLock();
    panel.addComponent(lockButton);

    var buildNote = new Label();
    buildNote.width = 580;
    buildNote.text = 'To unlock later, open qolslice.json next to the game and change "modMenuEnabled" to true.\n'
      + 'For a build that can never be unlocked, compile with -DQOL_LOCK_MOD_MENU.';
    buildNote.styleString = 'color: #9AA0A6; font-size: 12px;';
    panel.addComponent(buildNote);

    setStatus('Settings save automatically.');
  }

  function confirmLock()
  {
    confirm('Lock the Mod Menu?', 'After locking, pressing 7 or ~ will do nothing and players can\'t open any editor.\n\n'
      + 'You can undo this by editing qolslice.json (set "modMenuEnabled" to true).\n\nLock it now and go back to the main menu?', () -> {
        QOLConfig.modMenuEnabled = false;
        funkin.util.WindowUtil.setWindowTitle(QOLSlice.WINDOW_TITLE);
        FlxG.switchState(() -> new funkin.ui.mainmenu.MainMenuState());
      });
  }
}
#end
