package funkin.qol.events;

import funkin.data.event.SongEventSchema.SongEventFieldType;
import funkin.qol.util.QOLEase;

/**
 * Helpers shared by QOL Slice's chart events.
 */
class QOLEventUtil
{
  /**
   * An `ease` field that lists EVERY ease type (the QOL chart editor shows it with the Ease Picker).
   */
  public static function easeField(def:String = 'quadOut'):funkin.data.event.SongEventSchema.SongEventSchemaField
  {
    var keys = new Map<String, Dynamic>();
    for (e in QOLEase.ALL_WITH_INSTANT)
      keys.set(QOLEase.displayName(e), e);
    return {
      name: 'ease',
      title: 'Easing',
      defaultValue: def,
      type: SongEventFieldType.ENUM,
      keys: keys
    };
  }

  /**
   * Converts a duration in steps into seconds at the current BPM.
   */
  public static inline function stepsToSeconds(steps:Float):Float
    return Conductor.instance.stepLengthMs * steps / Constants.MS_PER_SEC;
}
