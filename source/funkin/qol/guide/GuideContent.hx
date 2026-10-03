package funkin.qol.guide;

typedef GuidePage =
{
  var id:String;
  var title:String;
  var body:String;
}

/**
 * The text of the built-in guide.
 *
 * Markup: `# Heading`, `## Subheading`, `- bullet`, `> tip`, lines starting with four spaces are code, blank lines
 * separate paragraphs.
 */
class GuideContent
{
  public static final PAGES:Array<GuidePage> = [
    {
      id: 'welcome',
      title: 'Welcome to QOL Slice',
      body: "
QOL Slice is a Friday Night Funkin' engine built on V-Slice, with an editor for almost everything. Everything you make is saved straight into your mod's folder, ready to share.

# Opening the Mod Menu
Press 7 (or ~) on the main menu. The Mod Menu is the home of every editor: pick a tile with the arrow keys or the mouse, and press Enter to open it.

# Your mod
Editors save into the active mod: mods/<your mod>/. Make one with + New Mod in the Mod Menu (or in the Modpack Manager), or pick one you already have. The essential folders (data, images, songs, music, sounds...) are made for you.

> The Mod Menu's tip line and the status bar at the bottom of every editor show which mod is active.

# Every editor works the same way
- Ctrl+S saves into your mod. Ctrl+Z and Ctrl+Y undo and redo.
- F1 opens this guide on the page for the editor you're in.
- F5 reloads every mod, so the game sees files you changed outside QOL Slice.
- Esc leaves the editor (it asks first if you have unsaved changes).
- The side panels can be dragged by their title bars to float them, docked to either side, resized from their edges, or folded away with the - button. The layout is remembered.
- A * in the window title means there are unsaved changes.

# After saving
With \"Reload game data after saving\" on (Engine Settings), saving hot-reloads the mods so your change shows up in the game right away. Turn it off if reloading is slow with a big mod.

# Sharing your mod
Your mod is the folder in mods/. Before releasing it, you can lock the Mod Menu in Engine Settings so players can't open the editors.
"
    },
    {
      id: 'modpack',
      title: 'Modpack Manager',
      body: "
The Modpack Manager makes and organizes mods: their names, descriptions, icons, contributors and load order.

# Making a mod
Click + New Mod (Ctrl+N). Give it a title and a folder name. A temporary icon is drawn from the title's initials; change it any time.

# The mod's details
These are saved in _polymod_meta.json, which the game reads to list your mod:
- Title, description, author and version.
- Contributors: a name and a role for each person.
- Dependencies: other mods this one needs, one per line, like
    myOtherMod: >=1.0.0

# Icon
_polymod_icon.png. Import a PNG, make one from a character's health icon, or generate a temporary one.

# Load order
Mods lower in the list load later and override the ones above them. Use Move Up and Move Down. Untick Enabled to keep a mod from loading without deleting it.

# Other tools
- Make this the active mod: the one the editors save into.
- Create missing folders: adds any essential folder that's missing.
- Duplicate, rename or delete a mod from the File menu.
"
    },
    {
      id: 'chart',
      title: 'Chart Editor',
      body: "
The Chart Editor writes songs: notes, events, BPM changes and the song's settings, with the instrumental and vocals as waveforms.

# Starting a song
File > New Song makes a song in your mod. Import the instrumental and the vocals (OGG) from the File menu. File > Open Song opens any song, including the base game's (saving puts a copy in your mod).

# Placing notes
- Click: place a note. Drag down while placing to make a hold note.
- Right-click: delete. Drag a note to move it.
- Shift+drag or right-drag: box select. Ctrl+click: add to the selection.
- Q and E: shorter or longer holds. M: mirror the selection.
- Left and Right change the snap (how finely notes line up to the beat).
- Ctrl+C, Ctrl+X, Ctrl+V: copy, cut and paste at the playhead.

# Playing
- Space plays and pauses. Enter playtests from the playhead, Shift+Enter from the start.
- Hitsounds and a metronome are in the Play menu.
- Live Input: press the keys 1-8 while the song plays to place notes in time.

# Strumlines
Chart > Add Strumline adds extra lanes (a third character, a duet...). Each strumline has its own settings, like which character sings its notes.

# Song settings
Name, artist, charter, difficulties, BPM and time signature, difficulty rating, the characters, the stage and the note skin. These are shared by every difficulty of the variation.

> Ctrl+Wheel zooms the chart. The waveforms can be turned off in the View menu if they slow things down.
"
    },
    {
      id: 'character',
      title: 'Character Editor',
      body: "
The Character Editor makes playable and opponent characters: their sprite sheet, animations, offsets, camera point, health icon and health bar color.

# Starting
File > New Character, or open an existing one (Ctrl+O). Import a sprite sheet (PNG + XML), a Packer sheet (PNG + TXT) or an Animate texture atlas folder.

# Animations
- Auto-detect fills in the usual animations (idle, singLEFT, singDOWN...) from the sheet's names.
- Add, Copy and Delete in the Animations panel. Each has a name, a prefix (the name in the sheet), frame indices, a frame rate, looping and offsets.
- Frame indices pick and order frames, like 0-5, 8, 10-12. Empty means all of them.

# Offsets
Drag the character to move the current animation, or nudge with the arrow keys (Shift = 10 pixels). Use another animation as a ghost (G) to line poses up with each other.
- W and S: previous and next animation. Space: play it. , and .: step through frames.
- Wheel or Q/E: zoom. Right-drag: pan. F: flip.

# Camera, icon and health bar
Drag the cross to set where the camera looks when this character sings. Pick the health icon and the health bar color (or take the color from the icon).

# Death
The death animations and sounds are set here too; for a full custom game over, use the Death Editor.
"
    },
    {
      id: 'stage',
      title: 'Background Editor',
      body: "
The Background Editor builds stages: the images behind and in front of the characters, where the characters stand, and the camera.

# Props
Add images (or animated sprite sheets) and place them by dragging. Each prop has a position, scale, scroll factor (how much it moves with the camera: 0 = fixed, 1 = moves with the world), opacity, layer order (zIndex), flip and blend mode.
- Ctrl+D duplicates the selected prop, Delete removes it.
- Animated props can dance on the beat.

# Characters
Click a character to select it, drag to move it. Drag its cross to move where the camera looks when it sings. Set each one's scale and layer.

# Camera
The stage zoom, and R to reset the view.

# Stage events
Timed changes during songs: move, fade or scale props, change the zoom... Use current fills a step's value with the prop's current position or opacity.

> The stage's images can live in any library, but your mod's images/ folder always works.
"
    },
    {
      id: 'noteskin',
      title: 'Note Skin Editor',
      body: "
The Note Skin Editor makes note styles: the notes, strums, hold notes, note splashes, hold covers, the countdown, and the rating and combo pop-ups. The preview plays notes exactly like the game does.

# Making a skin
File > New Skin starts from a copy of another skin. A skin is based on another one: anything it leaves out comes from that one, so you only change what you need.

# Parts
Pick a part on the left and set it on the right:
- Notes, Strums: a Sparrow sprite sheet, its scale and offset, and the animation for each direction (and each strum state: static, pressed, hit).
- Hold notes: a strip with the body and the end of each color.
- Note splashes and hold covers: turn them on or off, pick their animations.
- Countdown: the READY, SET, GO! pictures and a sound for each beat.
- Ratings and combo: the SICK!/GOOD!/BAD!/SHIT! pictures and the numbers 0-9.

# Testing it
Space pauses, R restarts. C shows the countdown and P a rating. D F J K (or the arrow keys) press the strums yourself; turn off Autoplay to play the pattern.

# Using it
Pick the skin for a song in the Chart Editor's song settings (Note style).
"
    },
    {
      id: 'death',
      title: 'Death Editor',
      body: "
The Death Editor makes custom game over sequences: the animations, the music, the camera, overlays (pictures on top) and timed actions.

# For one character or everyone
Open a character (Ctrl+O) to make their death. Turn on \"Use for everyone\" to save it as the default, which plays for every character without their own.

# Phases
A death has three phases: the start (the character dies), the loop (waiting for the player), and retry (the player pressed confirm). Each has its animation and music.

# Timed actions
Add actions on the timeline: play a sound or an animation, show, hide or tween an overlay, flash, shake or zoom the camera. Drag their markers to change when (and in which phase) they happen.

# Previewing
Space plays the death, Enter presses retry, Backspace stops. Drag overlays in the preview to place them.
"
    },
    {
      id: 'modchart',
      title: 'Modchart Editor',
      body: "
The Modchart Editor animates the notes, strums and more during a song with keyframes on a timeline: drunk, tipsy, spinning arrows, reverse scroll, moving strumlines, camera tricks...

# How it works
1. Click something in the preview (a strumline, a single arrow with Ctrl, the health bar, a character) or a row in the timeline.
2. Add a track with the + next to its name, or from the Add Track tab, which lists every feature.
3. Move the playhead and press K (or change the value) to add a key. Pick an ease for each key: it's how the value travels from the previous key.

# Keys
- Drag keys to move them (hold Alt to move without snapping). Right-click deletes one, double-click a track adds one.
- Ctrl+C and Ctrl+V copy and paste keys at the playhead. Ctrl+A selects all of them.
- Instant makes the value jump at the key instead of easing.

# Playing
Space plays, Home goes back to the start, Enter playtests from the playhead (Shift+Enter from the start).

> The modchart is shared by every difficulty of the song. A variation (erect, pico...) can have its own.
"
    },
    {
      id: 'animator',
      title: 'Animator',
      body: "
The Animator is a Flash-style animation studio: a timeline with layers, folders and masks, symbols, classic and shape tweens, vector and bitmap drawing, filters, blend modes, a camera and sound. It opens and saves Adobe Animate files.

# Tools
- V Select, B Brush, Y Pencil, E Eraser, K Bucket.
- N Line, R Rectangle, O Oval, P Polygon, T Text.
- I Eyedropper, H Hand, Z Zoom.
Drag with Select to box-select part of a drawing: lines and fills are cut where the box crosses them, just like Animate. The Eraser erases parts of lines and fills too. Bitmap (paint) layers can be selected and moved by pixels.

# The timeline
- F5 insert frame, Shift+F5 remove frames.
- F6 keyframe, F7 blank keyframe, Shift+F6 clear keyframe.
- Right-click frames to make a classic tween, copy or reverse frames.
- Layers can be put in folders and turned into masks. The eye and the lock hide and lock them (folders hide and lock everything inside).
- Enter plays. , and . step through frames. Home and End jump to the ends.

# Symbols
Select something and press F8 (or right-click > Convert to Symbol). Double-click a symbol to edit it, and set how it plays (loop, play once, single frame) in its properties. Ctrl+B breaks it apart again.

# Bringing things in
Drag files straight onto the Animator, or use File > Import: images, Sparrow sheets, Animate texture atlases, PNG sequences, sprite sheet grids, .fla/.xfl files, PSDs (Photoshop, ToonSquid, ibisPaint), videos and GIFs, and audio.

# Exporting
- Sprite Atlas for the Game: a Sparrow PNG + XML the game can use for characters and props.
- Animate texture atlas, PNG sequence, .fla, animated PSD, layered PSDs, video with sound, GIF, or the sound mix as a WAV.

> Right-click the canvas, the timeline or a layer for the most common actions. View > Theme changes the Animator's colors.
"
    },
    {
      id: 'week',
      title: 'Week Editor',
      body: "
The Week Editor makes story mode weeks: their songs, the characters dancing on the banner, the title, the banner color or picture, and the order of the weeks. The preview shows the Story Mode menu.

# Weeks
The list on the left is the order of Story Mode. Move weeks up and down to change it (saved with the week, into data/qol/week-order.json). New makes a week, Copy duplicates the one you're editing.
- Weeks that come with the game can't be deleted, but you can untick Show in Story Mode to hide one.
- Changing a saved week's ID saves a copy under the new name.

# This week
- Name: shown at the top right of the Story Mode menu.
- Title image: the picture in the list of weeks. No picture? Make a title image from the name.
- Banner: a color, or a 1280x400 picture.
- Freeplay capsule label: the small week name on its songs' Freeplay capsules (made from the ID when empty).

# Songs
Add, remove and order the week's songs. The difficulties in Story Mode come from the first song.

# Characters on the banner
- Click one in the preview to pick it, drag to move it, or nudge with the arrow keys (Shift = 10).
- Add a character with its sprite sheet. Its animations are detected for you: idle (or danceLeft and danceRight) dances on the beat, confirm plays when the week is picked.
- Split \"idle\" into danceLeft + danceRight for characters that sway, like Girlfriend.
- Dance every: beats between dances. 0 means it never dances and plays its starting animation instead.

> Space plays the \"week picked\" animation: the confirm sound, the title flashing and the characters cheering.
"
    },
    {
      id: 'freeplay',
      title: 'Freeplay Editor',
      body: "
The Freeplay Editor sets up Freeplay: which songs are in it, each song's difficulty ratings, album and music preview, and the albums. The preview shows the Freeplay menu.

# Songs in Freeplay
Every week's songs are in Freeplay already. On top of that you can:
- Add a song that isn't in any week. Pick which week it's listed with: its capsule shows that week's name, and it comes after that week's songs.
- Hide a song (it stays in Story Mode).
These are saved in data/qol/freeplay.json.

# A song's settings
These are saved in the song's metadata, the same file the Chart Editor saves:
- Name and artist.
- Album: the album art shown next to the list.
- Difficulty ratings: the number on the capsule and the stars (up to 15).
- Music preview: the part of the song that plays while it's selected (start and end, as a part of the whole song). Press Play to hear it.
Songs with variations (erect, pico...) have settings for each one.

# Albums
New makes an album. It has a name, artists, the album art (a 262x262 picture) and a title. The title can be a plain picture or a sprite sheet with idle and switch animations; Make a title from the name draws one for you.

# Preview
Up and Down (or the mouse wheel over the preview) move through the songs, and clicking a capsule picks it. Space plays the music preview. Pick the difficulty and the style (bf or pico) under Preview.

> The icon, BPM and difficulties on a capsule come from the chart. Change them in the Chart Editor.
"
    },
    {
      id: 'settings',
      title: 'Engine Settings',
      body: "
Settings for QOL Slice itself.

# Editors
- Reload game data after saving: saving hot-reloads every mod, so the game sees your changes right away.
- Show Legacy V-Slice tools: the original V-Slice editors. They save through file dialogs, not into your mod folder.

# Menus
- Fancy menus: beat bumps, floating arrows, sparkles and intro animations in the QOL Slice menus. Turn them off on slow PCs.

# Performance
- GPU textures: during songs, images that are already on the graphics card don't keep a second copy in memory.
- Free memory when leaving editors: drops the images the editors loaded for their previews.

# Releasing your mod
Lock the Mod Menu before sharing your finished mod, so players can't open the editors with 7 or ~.
"
    }
  ];

  public static function get(id:String):Null<GuidePage>
  {
    for (page in PAGES)
      if (page.id == id) return page;
    return null;
  }
}
