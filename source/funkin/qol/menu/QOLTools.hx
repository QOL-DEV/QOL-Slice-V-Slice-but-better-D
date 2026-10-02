package funkin.qol.menu;

#if FEATURE_HAXEUI
import flixel.FlxState;

typedef QOLToolInfo =
{
  var id:String;
  var name:String;
  var description:String;
  var color:Int;
  var category:String;

  /**
   * Image key used as the tile's artwork until a custom `qol/hub/<id>.png` is made.
   */
  var ?art:String;

  /**
   * Whether the tool needs an active mod to be selected first.
   */
  var needsMod:Bool;
}

/**
 * Every tool in the QOL Slice Mod Menu.
 */
class QOLTools
{
  public static final TOOLS:Array<QOLToolInfo> = [
    {
      id: 'animator',
      name: 'Animator',
      description: 'Flash-style animation studio: timeline, layers, symbols, tweens, vector & bitmap drawing, filters, blend modes.',
      color: 0xFFEC407A,
      category: 'Art',
      art: 'icons/icon-tankman',
      needsMod: true
    },
    {
      id: 'modpack',
      name: 'Modpack Manager',
      description: 'Create mods, edit _polymod_meta.json, icons and folders, and turn mods on or off.',
      color: 0xFF3D7BFF,
      category: 'Project',
      art: 'icons/icon-gf',
      needsMod: false
    },
    {
      id: 'chart',
      name: 'Chart Editor',
      description: 'Codename-style charting: waveforms, events, extra strumlines, multi-select, playtesting and more.',
      color: 0xFFFF4F7B,
      category: 'Songs',
      art: 'icons/icon-dad',
      needsMod: true
    },
    {
      id: 'character',
      name: 'Character Editor',
      description: 'Animations, offsets, camera, health icon and bar colors, death settings. Live preview.',
      color: 0xFF22B573,
      category: 'Art',
      art: 'icons/icon-bf',
      needsMod: true
    },
    {
      id: 'stage',
      name: 'Background Editor',
      description: 'Build stages: props, layers, scroll factors, character spots, camera and stage events.',
      color: 0xFF8E5CFF,
      category: 'Art',
      art: 'icons/icon-spooky',
      needsMod: true
    },
    {
      id: 'noteskin',
      name: 'Note Skin Editor',
      description: 'Notes, strums, holds, note splashes, hold covers, countdown, ratings and combo numbers.',
      color: 0xFF12A9CB,
      category: 'Art',
      art: 'icons/icon-pico',
      needsMod: true
    },
    {
      id: 'death',
      name: 'Death Editor',
      description: 'Custom game over sequences: animations, music, camera, overlays and timed actions.',
      color: 0xFFE8384A,
      category: 'Gameplay',
      art: 'icons/icon-bf-pixel',
      needsMod: true
    },
    {
      id: 'shader',
      name: 'Shader Editor',
      description: 'Write GLSL with a live preview, or start from 20+ built-in effects. Use them in charts.',
      color: 0xFFFF9F1C,
      category: 'Effects',
      art: 'icons/icon-monster',
      needsMod: true
    },
    {
      id: 'modchart',
      name: 'Modchart Editor',
      description: 'Keyframe note and strum modifiers (drunk, tipsy, spin, reverse...) on a timeline.',
      color: 0xFFFF6A3D,
      category: 'Gameplay',
      art: 'icons/icon-mom',
      needsMod: true
    },
    {
      id: 'menu',
      name: 'Menu Editor',
      description: 'Rearrange, restyle and add buttons and animated objects to the game\'s menus.',
      color: 0xFF6DBE3C,
      category: 'Interface',
      art: 'icons/icon-parents',
      needsMod: true
    },
    {
      id: 'hud',
      name: 'UI / HUD Editor',
      description: 'Drag the health bar, score, time bar, strums and popups around. Add custom HUD text.',
      color: 0xFF5463D6,
      category: 'Interface',
      art: 'icons/icon-senpai',
      needsMod: true
    },
    {
      id: 'week',
      name: 'Week Editor',
      description: 'Story mode weeks, their songs, menu characters, titles and backgrounds.',
      color: 0xFF1FA493,
      category: 'Project',
      art: 'icons/icon-darnell',
      needsMod: true
    },
    {
      id: 'freeplay',
      name: 'Freeplay Editor',
      description: 'Freeplay song capsules, album art, difficulty ratings, preview times and DJ settings.',
      color: 0xFFB04FD6,
      category: 'Project',
      art: 'icons/icon-chaewon',
      needsMod: true
    },
    {
      id: 'dialogue',
      name: 'Dialogue Editor',
      description: 'Cutscene conversations: speakers, expressions, dialogue boxes, text speed and sounds.',
      color: 0xFF1E9BEA,
      category: 'Project',
      art: 'icons/icon-senpai-angry',
      needsMod: true
    },
    {
      id: 'achievements',
      name: 'Achievements',
      description: 'Make achievements with icons and unlock conditions (FC a song, beat a week, misses...).',
      color: 0xFFF2B705,
      category: 'Gameplay',
      art: 'icons/icon-sakura',
      needsMod: true
    },
    {
      id: 'credits',
      name: 'Credits Editor',
      description: 'Write the credits for your mod, with roles, icons and links.',
      color: 0xFFA1673F,
      category: 'Project',
      art: 'icons/icon-pico-pixel',
      needsMod: true
    },
    {
      id: 'guide',
      name: 'Guide',
      description: 'How to use QOL Slice and every one of its editors.',
      color: 0xFF5E7C8A,
      category: 'Help',
      art: 'icons/icon-bf-old',
      needsMod: false
    },
    {
      id: 'settings',
      name: 'Engine Settings',
      description: 'Auto-reload, fancy menus, legacy tools, and locking the Mod Menu for your finished mod.',
      color: 0xFF52606D,
      category: 'Help',
      art: 'icons/icon-spirit',
      needsMod: false
    },
    {
      id: 'legacy',
      name: 'Legacy Tools',
      description: 'V-Slice\'s original Chart, Stage and Animation editors, kept around just in case.',
      color: 0xFF7A6E66,
      category: 'Help',
      art: 'icons/icon-face',
      needsMod: false
    },
  ];

  public static function get(id:String):Null<QOLToolInfo>
  {
    for (tool in TOOLS)
      if (tool.id == id) return tool;
    return null;
  }

  /**
   * Create the state for a tool.
   */
  public static function createTool(id:String):Null<FlxState>
  {
    return switch (id)
    {
      case 'menu-hub' | 'hub': new QOLModMenuState();
      case 'guide': new funkin.qol.guide.GuideState();
      default: QOLToolFactory.create(id);
    }
  }
}
#end
