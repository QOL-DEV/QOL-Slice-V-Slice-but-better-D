package funkin.qol.events;

import funkin.data.character.CharacterData.CharacterDataParser;
import funkin.data.event.SongEventSchema;
import funkin.data.event.SongEventSchema.SongEventFieldType;
import funkin.data.song.SongData.SongEventData;
import funkin.play.PlayState;
import funkin.play.event.SongEvent;

/**
 * QOL SLICE: swap Boyfriend, Girlfriend or the opponent for another character mid-song.
 * Health icons and health bar colors update too.
 */
class ChangeCharacterSongEvent extends SongEvent
{
  public function new()
  {
    super('ChangeCharacter', {processOldEvents: true});
  }

  override public function handleEvent(data:SongEventData):Void
  {
    if (PlayState.instance == null || PlayState.instance.isMinimalMode) return;
    var target = data.getString('target') ?? 'dad';
    var character = data.getString('character');
    if (character == null || character == '') return;
    PlayState.instance.qol?.changeCharacter(target, character);
  }

  override public function getTitle():String
    return 'Change Character';

  override public function getEventSchema():SongEventSchema
  {
    var keys = new Map<String, Dynamic>();
    for (id in CharacterDataParser.listCharacterIds())
      keys.set(id, id);
    return new SongEventSchema([
      {
        name: 'target',
        title: 'Who',
        defaultValue: 'dad',
        type: SongEventFieldType.ENUM,
        keys: ['Opponent' => 'dad', 'Player' => 'bf', 'Girlfriend' => 'gf']
      },
      {
        name: 'character',
        title: 'New character',
        defaultValue: 'dad',
        type: SongEventFieldType.ENUM,
        keys: keys
      }
    ]);
  }
}
