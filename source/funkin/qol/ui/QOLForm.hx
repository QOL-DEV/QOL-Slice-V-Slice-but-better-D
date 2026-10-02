package funkin.qol.ui;

#if FEATURE_HAXEUI
import haxe.ui.components.Button;
import haxe.ui.components.CheckBox;
import haxe.ui.components.DropDown;
import haxe.ui.components.HorizontalSlider;
import haxe.ui.components.Label;
import haxe.ui.components.NumberStepper;
import haxe.ui.components.SectionHeader;
import haxe.ui.components.TextArea;
import haxe.ui.components.TextField;
import haxe.ui.components.popups.ColorPickerPopup;
import haxe.ui.containers.HBox;
import haxe.ui.containers.VBox;
import haxe.ui.core.Component;
import haxe.ui.data.ArrayDataSource;
import haxe.ui.util.Color;
import funkin.qol.util.QOLEase;

/**
 * A property form for editor side panels.
 *
 * Each row is bound to a getter and a setter, so after the selected object changes you
 * just call `refresh()` and every control re-reads its value. Changes made by the user
 * are pushed straight into the setter.
 *
 * ```haxe
 * var form = new QOLForm();
 * form.section('Position');
 * form.number('X', () -> obj.x, v -> obj.x = v, -9999, 9999, 1);
 * form.check('Flip X', () -> obj.flipX, v -> obj.flipX = v);
 * ```
 */
class QOLForm extends VBox
{
  public var labelWidth:Float = 104;
  public var controlWidth:Float = 160;

  var refreshers:Array<Void->Void> = [];

  /**
   * Re-apply each control's width (so the form can follow its panel when the panel is resized).
   */
  var sizers:Array<Void->Void> = [];

  var baseControlWidth:Float = -1;

  function fit(c:Component, width:Void->Float):Void
  {
    c.width = width();
    sizers.push(() -> c.width = width());
  }

  /**
   * Widen or narrow the controls by `delta` pixels from the form's original size.
   */
  public function fitDelta(delta:Float):Void
  {
    if (baseControlWidth < 0) baseControlWidth = controlWidth;
    var w = Math.max(60, baseControlWidth + delta);
    if (w == controlWidth) return;
    controlWidth = w;
    for (s in sizers)
      s();
  }

  /**
   * True while values are being pushed into controls, so change events can be ignored.
   */
  public var refreshing(default, null):Bool = false;

  /**
   * Called after any control in the form changes a value.
   */
  public var onAnyChange:Null<Void->Void> = null;

  public function new(?labelWidth:Float, ?controlWidth:Float)
  {
    super();
    if (labelWidth != null) this.labelWidth = labelWidth;
    if (controlWidth != null) this.controlWidth = controlWidth;
    this.styleString = 'spacing: 4px;';
  }

  public function clearForm():Void
  {
    removeAllComponents();
    refreshers = [];
    sizers = [];
  }

  /**
   * Re-read every bound value into its control.
   */
  public function refresh():Void
  {
    refreshing = true;
    for (r in refreshers)
    {
      try
      {
        r();
      }
      catch (e)
      {
        trace('[QOL] Form refresh error: $e');
      }
    }
    refreshing = false;
  }

  function changed():Void
  {
    if (onAnyChange != null) onAnyChange();
  }

  public function row(labelText:String, control:Component):HBox
  {
    var hbox = new HBox();
    hbox.styleString = 'spacing: 6px;';
    if (labelText != null)
    {
      var label = new Label();
      label.text = labelText;
      label.width = labelWidth;
      label.styleString = 'padding-top: 4px;';
      hbox.addComponent(label);
    }
    hbox.addComponent(control);
    addComponent(hbox);
    return hbox;
  }

  public function section(title:String):SectionHeader
  {
    var header = new SectionHeader();
    header.text = title;
    header.percentWidth = 100;
    addComponent(header);
    return header;
  }

  public function note(text:String):Label
  {
    var label = new Label();
    label.text = text;
    fit(label, () -> labelWidth + controlWidth + 6);
    label.styleString = 'color: #A0A0A0; font-size: 11px;';
    addComponent(label);
    return label;
  }

  public function textField(labelText:String, get:Void->String, set:String->Void, ?placeholder:String):TextField
  {
    var field = new TextField();
    fit(field, () -> controlWidth);
    if (placeholder != null) field.placeholder = placeholder;
    field.onChange = function(_) {
      if (refreshing || (field.text ?? '') == (get() ?? '')) return;
      set(field.text ?? '');
      changed();
    };
    refreshers.push(() -> {
      var v = get() ?? '';
      if (field.text != v) field.text = v;
    });
    row(labelText, field);
    refreshers[refreshers.length - 1]();
    return field;
  }

  public function textArea(labelText:String, get:Void->String, set:String->Void, height:Float = 80):TextArea
  {
    var field = new TextArea();
    fit(field, () -> labelText == null ? labelWidth + controlWidth + 6 : controlWidth);
    field.height = height;
    field.onChange = function(_) {
      if (refreshing || (field.text ?? '') == (get() ?? '')) return;
      set(field.text ?? '');
      changed();
    };
    refreshers.push(() -> {
      var v = get() ?? '';
      if (field.text != v) field.text = v;
    });
    if (labelText == null) addComponent(field);
    else
      row(labelText, field);
    refreshers[refreshers.length - 1]();
    return field;
  }

  public function number(labelText:String, get:Void->Float, set:Float->Void, ?min:Float, ?max:Float, step:Float = 1, precision:Int = 2):NumberStepper
  {
    var stepper = new NumberStepper();
    fit(stepper, () -> controlWidth);
    stepper.min = min ?? -99999;
    stepper.max = max ?? 99999;
    stepper.step = step;
    stepper.precision = precision;
    stepper.onChange = function(_) {
      if (refreshing) return;
      var v:Null<Float> = stepper.pos;
      if (v == null || Math.isNaN(v)) return;
      // HaxeUI reports changes made by `refresh` a moment later; only pass on real edits.
      if (v == get()) return;
      set(v);
      changed();
    };
    refreshers.push(() -> {
      var v:Float = get();
      if (Math.isNaN(v)) v = 0;
      if (stepper.pos != v) stepper.pos = v;
    });
    row(labelText, stepper);
    refreshers[refreshers.length - 1]();
    return stepper;
  }

  /**
   * Two number steppers side by side (for positions, offsets, scroll factors...).
   */
  public function pair(labelText:String, getA:Void->Float, setA:Float->Void, getB:Void->Float, setB:Float->Void, step:Float = 1, precision:Int = 2,
      ?min:Float, ?max:Float):HBox
  {
    var hbox = new HBox();
    hbox.styleString = 'spacing: 4px;';
    var a = new NumberStepper();
    var b = new NumberStepper();
    for (s in [a, b])
    {
      fit(s, () -> (controlWidth - 4) / 2);
      s.min = min ?? -99999;
      s.max = max ?? 99999;
      s.step = step;
      s.precision = precision;
      hbox.addComponent(s);
    }
    a.onChange = function(_) {
      if (refreshing || a.pos == null || a.pos == getA()) return;
      setA(a.pos);
      changed();
    };
    b.onChange = function(_) {
      if (refreshing || b.pos == null || b.pos == getB()) return;
      setB(b.pos);
      changed();
    };
    refreshers.push(() -> {
      var va = getA();
      var vb = getB();
      if (a.pos != va) a.pos = va;
      if (b.pos != vb) b.pos = vb;
    });
    row(labelText, hbox);
    refreshers[refreshers.length - 1]();
    return hbox;
  }

  public function check(labelText:String, get:Void->Bool, set:Bool->Void):CheckBox
  {
    var box = new CheckBox();
    box.text = '';
    box.onChange = function(_) {
      if (refreshing || box.selected == (get() == true)) return;
      set(box.selected);
      changed();
    };
    refreshers.push(() -> {
      var v = get() == true;
      if (box.selected != v) box.selected = v;
    });
    row(labelText, box);
    refreshers[refreshers.length - 1]();
    return box;
  }

  public function slider(labelText:String, get:Void->Float, set:Float->Void, min:Float, max:Float, step:Float = 0.01):HorizontalSlider
  {
    var s = new HorizontalSlider();
    fit(s, () -> controlWidth);
    s.min = min;
    s.max = max;
    s.step = step;
    s.onChange = function(_) {
      if (refreshing || s.pos == get()) return;
      set(s.pos);
      changed();
    };
    refreshers.push(() -> {
      var v = get();
      if (s.pos != v) s.pos = v;
    });
    row(labelText, s);
    refreshers[refreshers.length - 1]();
    return s;
  }

  /**
   * A dropdown. `items` is re-evaluated on every refresh, so lists can change (e.g. animation names).
   */
  public function dropdown(labelText:String, items:Void->Array<String>, get:Void->String, set:String->Void, ?labels:Void->Array<String>):DropDown
  {
    var dd = new DropDown();
    fit(dd, () -> controlWidth);
    sizers.push(() -> dd.dropdownWidth = Math.max(controlWidth, 180));
    dd.dropdownWidth = Math.max(controlWidth, 180);
    dd.searchable = true;
    var currentItems:Array<String> = [];
    // HaxeUI auto-selects item 0 (and fires a change) when a list is assigned to a dropdown that is
    // already on screen, so changes are ignored while the dropdown is being (re)built.
    var building = false;
    function rebuild()
    {
      building = true;
      var list = items() ?? [];
      var names = labels != null ? labels() : list;
      if (list.join('\u0001') != currentItems.join('\u0001'))
      {
        currentItems = list.copy();
        var ds = new ArrayDataSource<Dynamic>();
        for (i in 0...list.length)
          ds.add({text: names[i] ?? list[i], value: list[i]});
        dd.dataSource = ds;
      }
      var v = get();
      var idx = currentItems.indexOf(v);
      if (dd.selectedIndex != idx) dd.selectedIndex = idx;
      if (idx >= 0) dd.text = names[idx] ?? list[idx];
      else if (v != null && v != '') dd.text = v;
      building = false;
    }
    dd.onChange = function(_) {
      if (refreshing || building) return;
      var item = dd.selectedItem;
      if (item == null || item.value == get()) return;
      set(item.value);
      changed();
    };
    refreshers.push(rebuild);
    row(labelText, dd);
    rebuild();
    return dd;
  }

  public function colorField(labelText:String, get:Void->Int, set:Int->Void):ColorPickerPopup
  {
    var picker = new ColorPickerPopup();
    fit(picker, () -> controlWidth);
    var syncing = false;
    function sync()
    {
      var v = get() & 0xFFFFFF;
      var raw:Dynamic = picker.selectedItem;
      var curInt:Int = raw == null ? -1 : ((raw : Int) & 0xFFFFFF);
      if (curInt != v)
      {
        syncing = true;
        picker.selectedItem = Color.fromComponents((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF, 255);
        syncing = false;
      }
    }
    // HaxeUI's picker reports black while it builds its popup, so for a moment after it opens its changes are ignored
    // and the real color is put back.
    var openedAt = -1.0;
    picker.registerEvent(haxe.ui.events.MouseEvent.MOUSE_DOWN, function(_) {
      openedAt = haxe.Timer.stamp();
    });
    picker.onChange = function(_) {
      if (refreshing || syncing) return;
      var now = haxe.Timer.stamp();
      if (!picker.dropDownOpen) openedAt = -1;
      else if (openedAt < 0) openedAt = now;
      if (openedAt < 0 || now - openedAt < 0.3)
      {
        haxe.ui.Toolkit.callLater(sync);
        return;
      }
      var raw:Dynamic = picker.selectedItem;
      if (raw == null) return;
      var c:Color = raw;
      var next = 0xFF000000 | (c.r << 16) | (c.g << 8) | c.b;
      if ((next & 0xFFFFFF) == (get() & 0xFFFFFF)) return;
      set(next);
      changed();
    };
    refreshers.push(sync);
    row(labelText, picker);
    refreshers[refreshers.length - 1]();
    return picker;
  }

  /**
   * An ease selector. Shows the ease's name and curve; clicking it opens the full Ease Picker
   * that previews every single ease type.
   */
  public function ease(labelText:String, get:Void->String, set:String->Void, includeInstant:Bool = false, includeClassic:Bool = false):Button
  {
    var btn = new Button();
    fit(btn, () -> controlWidth);
    btn.iconPosition = 'left';
    function update()
    {
      var e = get() ?? 'linear';
      btn.text = QOLEase.displayName(e);
      btn.icon = EaseGraph.frame(e, 26, 18);
    }
    btn.onClick = function(_) {
      EasePicker.open(get() ?? 'linear', includeInstant, function(chosen:String) {
        set(chosen);
        update();
        changed();
      }, includeClassic);
    };
    refreshers.push(update);
    row(labelText, btn);
    update();
    return btn;
  }

  public function button(text:String, onClick:Void->Void, ?tooltip:String):Button
  {
    var btn = new Button();
    btn.text = text;
    fit(btn, () -> labelWidth + controlWidth + 6);
    btn.onClick = _ -> onClick();
    if (tooltip != null) btn.tooltip = tooltip;
    addComponent(btn);
    return btn;
  }

  public function buttons(defs:Array<{text:String, cb:Void->Void}>):HBox
  {
    var hbox = new HBox();
    hbox.styleString = 'spacing: 4px;';
    var count = defs.length;
    for (def in defs)
    {
      var btn = new Button();
      btn.text = def.text;
      fit(btn, () -> (labelWidth + controlWidth + 6 - (count - 1) * 4) / count);
      var cb = def.cb;
      btn.onClick = _ -> cb();
      hbox.addComponent(btn);
    }
    addComponent(hbox);
    return hbox;
  }

  /**
   * A text field with a "..." browse button next to it.
   */
  public function file(labelText:String, get:Void->String, set:String->Void, browse:(String->Void)->Void):TextField
  {
    var hbox = new HBox();
    hbox.styleString = 'spacing: 4px;';
    var field = new TextField();
    fit(field, () -> controlWidth - 34);
    var btn = new Button();
    btn.text = '...';
    btn.width = 30;
    hbox.addComponent(field);
    hbox.addComponent(btn);
    field.onChange = function(_) {
      if (refreshing || (field.text ?? '') == (get() ?? '')) return;
      set(field.text ?? '');
      changed();
    };
    btn.onClick = function(_) {
      browse(function(chosen:String) {
        field.text = chosen;
        set(chosen);
        changed();
      });
    };
    refreshers.push(() -> {
      var v = get() ?? '';
      if (field.text != v) field.text = v;
    });
    row(labelText, hbox);
    refreshers[refreshers.length - 1]();
    return field;
  }

  /**
   * Adds an arbitrary component as its own row, with an optional refresher.
   */
  public function custom(component:Component, ?refresher:Void->Void, ?labelText:String):Component
  {
    if (labelText != null) row(labelText, component);
    else
      addComponent(component);
    if (refresher != null)
    {
      refreshers.push(refresher);
      refresher();
    }
    return component;
  }

  public function addRefresher(fn:Void->Void):Void
  {
    refreshers.push(fn);
  }
}
#end
