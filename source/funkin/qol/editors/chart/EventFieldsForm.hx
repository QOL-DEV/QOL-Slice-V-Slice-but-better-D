package funkin.qol.editors.chart;

#if FEATURE_HAXEUI
import flixel.util.FlxColor;
import funkin.data.event.SongEventRegistry;
import funkin.data.event.SongEventSchema;
import funkin.data.event.SongEventSchema.SongEventFieldType;
import funkin.data.event.SongEventSchema.SongEventSchemaField;
import funkin.data.song.SongData.SongEventData;
import funkin.qol.ui.QOLForm;
import funkin.qol.util.QOLEase;

/**
 * Builds a form for any song event from its schema.
 *
 * Ease fields (`ease`, plus V-Slice's `easeDir`) become a single Ease Picker button that shows
 * every ease type, and fields named like `color` get a color picker.
 */
class EventFieldsForm
{
  /**
   * @param getEvent Returns the event being edited (it can change without rebuilding the form).
   * @param changed Called after any value changes (record undo, redraw...).
   */
  public static function build(form:QOLForm, kind:String, getEvent:Void->Null<SongEventData>, changed:Void->Void):Void
  {
    var schema:Null<SongEventSchema> = SongEventRegistry.getEventSchema(kind);
    if (schema == null)
    {
      form.note('This event has no settings.');
      return;
    }
    var hasEaseDir = schema.getByName('easeDir') != null;
    addFields(form, schema, cast schema, getEvent, changed, hasEaseDir);
  }

  static function struct(e:SongEventData, schema:SongEventSchema):Dynamic
  {
    var v:Dynamic = e.value;
    if (v == null || !Reflect.isObject(v) || Std.isOfType(v, String))
    {
      var key = schema.getFirstField()?.name ?? 'value';
      var wrapped:Dynamic = {};
      if (v != null) Reflect.setField(wrapped, key, v);
      e.value = wrapped;
    }
    return e.value;
  }

  static function getValue(e:Null<SongEventData>, schema:SongEventSchema, field:SongEventSchemaField):Dynamic
  {
    if (e == null) return field.defaultValue;
    var s = struct(e, schema);
    var v:Dynamic = Reflect.field(s, field.name);
    return v == null ? field.defaultValue : v;
  }

  static function setValue(e:Null<SongEventData>, schema:SongEventSchema, name:String, value:Dynamic):Void
  {
    if (e == null) return;
    Reflect.setField(struct(e, schema), name, value);
  }

  static function addFields(form:QOLForm, schema:SongEventSchema, fields:Array<SongEventSchemaField>, getEvent:Void->Null<SongEventData>,
      changed:Void->Void, hasEaseDir:Bool):Void
  {
    for (field in fields)
    {
      var f = field;
      var title = f.title ?? f.name;
      if (f.units != null && f.units != '') title += ' (${f.units})';
      switch (f.type)
      {
        case SongEventFieldType.FRAME:
          form.section(f.title ?? f.name);
          if (f.children != null) addFields(form, schema, f.children, getEvent, changed, hasEaseDir);

        case SongEventFieldType.STRING:
          if (f.name.toLowerCase().indexOf('color') != -1)
          {
            form.colorField(title, () -> {
              var c = FlxColor.fromString(Std.string(getValue(getEvent(), schema, f) ?? '#FFFFFF'));
              return c == null ? FlxColor.WHITE : c;
            }, v -> {
              setValue(getEvent(), schema, f.name, '#' + StringTools.hex(v & 0xFFFFFF, 6));
              changed();
            });
          }
          else
          {
            form.textField(title, () -> Std.string(getValue(getEvent(), schema, f) ?? ''), v -> {
              setValue(getEvent(), schema, f.name, v);
              changed();
            });
          }

        case SongEventFieldType.INTEGER:
          form.number(title, () -> {
            var v:Dynamic = getValue(getEvent(), schema, f);
            return v == null ? 0 : Std.parseFloat(Std.string(v));
          }, v -> {
            setValue(getEvent(), schema, f.name, Std.int(v));
            changed();
          }, f.min, f.max, f.step ?? 1, 0);

        case SongEventFieldType.FLOAT:
          var step:Float = f.step ?? 0.1;
          form.number(title, () -> {
            var v:Dynamic = getValue(getEvent(), schema, f);
            return v == null ? 0 : Std.parseFloat(Std.string(v));
          }, v -> {
            setValue(getEvent(), schema, f.name, v);
            changed();
          }, f.min, f.max, step, step < 0.01 ? 3 : 2);

        case SongEventFieldType.BOOL:
          form.check(title, () -> {
            var v:Dynamic = getValue(getEvent(), schema, f);
            return v == true || v == 'true';
          }, v -> {
            setValue(getEvent(), schema, f.name, v);
            changed();
          });

        case SongEventFieldType.ENUM:
          if (f.name == 'easeDir' && hasEaseDir)
          {
            // Shown as part of the ease picker.
          }
          else if (f.name == 'ease')
          {
            var specials = f.keys == null ? ['INSTANT'] : [for (v in f.keys) Std.string(v)];
            form.ease(title, () -> {
              var ease = Std.string(getValue(getEvent(), schema, f) ?? 'linear');
              if (!hasEaseDir) return ease;
              var dirField = schema.getByName('easeDir');
              var dir = Std.string(getValue(getEvent(), schema, dirField) ?? 'In');
              return QOLEase.combine(ease, dir);
            }, v -> {
              if (hasEaseDir)
              {
                var parts = QOLEase.split(v);
                setValue(getEvent(), schema, 'ease', parts[0]);
                setValue(getEvent(), schema, 'easeDir', parts[1] == '' ? 'In' : parts[1]);
              }
              else
                setValue(getEvent(), schema, 'ease', v);
              changed();
            }, specials.contains('INSTANT'), specials.contains('CLASSIC'));
          }
          else
          {
            var keys = f.keys ?? new Map<String, Dynamic>();
            var labels = [for (k in keys.keys()) k];
            labels.sort((a, b) -> a.toLowerCase() < b.toLowerCase() ? -1 : 1);
            var values = [for (l in labels) Std.string(keys.get(l))];
            form.dropdown(title, () -> values, () -> Std.string(getValue(getEvent(), schema, f) ?? ''), v -> {
              // Keep the original value type (numbers stay numbers).
              var original:Dynamic = null;
              for (l in labels)
                if (Std.string(keys.get(l)) == v) original = keys.get(l);
              setValue(getEvent(), schema, f.name, original ?? v);
              changed();
            }, () -> labels);
          }

        default:
          form.note('${f.name}: unsupported field type');
      }
    }
  }
}
#end
