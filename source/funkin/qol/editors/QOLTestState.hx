package funkin.qol.editors;

#if FEATURE_HAXEUI
import funkin.qol.ui.QOLEditorState;
import funkin.qol.ui.QOLForm;
import flixel.FlxSprite;

/**
 * Internal test bed for the QOL UI kit.
 */
class QOLTestState extends QOLEditorState
{
  var spr:FlxSprite;
  var ease:String = 'quadInOut';

  public function new()
  {
    super();
    editorName = 'UI Test';
    rightPanelWidth = 320;
    leftPanelWidth = 240;
  }

  override function buildEditor():Void
  {
    spr = new FlxSprite(500, 300).makeGraphic(100, 100, 0xFFFF5C8A);
    spr.cameras = [camWorld];
    add(spr);

    var file = addMenu('File');
    addMenuItem(file, 'Save', 'Ctrl+S', () -> doSave());

    var form = new QOLForm();
    form.section('Transform');
    form.pair('Position', () -> spr.x, v -> spr.x = v, () -> spr.y, v -> spr.y = v);
    form.number('Angle', () -> spr.angle, v -> spr.angle = v, -360, 360, 1);
    form.slider('Alpha', () -> spr.alpha, v -> spr.alpha = v, 0, 1);
    form.check('Visible', () -> spr.visible, v -> spr.visible = v);
    form.colorField('Color', () -> spr.color, v -> spr.color = v);
    form.dropdown('Blend', () -> ['normal', 'add', 'multiply', 'screen'], () -> 'normal', v -> {});
    form.ease('Ease', () -> ease, v -> ease = v, true);
    form.textField('Name', () -> 'test', v -> {});
    form.button('Open Ease Picker', () -> funkin.qol.ui.EasePicker.open(ease, true, e -> ease = e));
    rightPanel.addComponent(form);

    var form2 = new QOLForm(80, 120);
    form2.section('Files');
    form2.button('Browse images', () -> browseModFile('Pick an image', 'images', ['png'], k -> setStatus('Picked $k')));
    leftPanel.addComponent(form2);
    setStatus('Ready');
  }
}
#end
