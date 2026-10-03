package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import funkin.qol.editors.animator.AnimData;
import funkin.qol.ui.QOLForm;
import haxe.ui.containers.dialogs.Dialog;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;

typedef AnimExportFrame =
{
  var anim:String;
  var index:Int;
  var bmp:Null<BitmapData>;

  /**
   * Trimmed area inside the frame (in frame pixels).
   */
  var trim:Rectangle;

  var frameW:Int;
  var frameH:Int;

  /**
   * Where frame (0, 0) is in the animation's coordinates (unscaled).
   */
  var originX:Float;

  var originY:Float;

  // Filled by packing.
  var ?x:Int;
  var ?y:Int;
  var ?dupOf:Int;
  var ?hash:String;
}

typedef AnimExportSet =
{
  var name:String;
  var symbol:AnimSymbol;
  var from:Int;
  var to:Int; // exclusive
}

/**
 * Exports from the Animator: sprite atlases the game can load (Sparrow PNG + XML, Adobe Animate texture atlases),
 * PNG sequences, and the files other apps open (.fla, PSD).
 */
class AnimExport
{
  //
  // Dialogs
  //

  public static function formDialog(title:String, okText:String, build:QOLForm->Void, onOk:Void->Void):Void
  {
    var dialog = new Dialog();
    dialog.addClass('anim-ui');
    dialog.addClass('anim-popup');
    dialog.title = title;
    dialog.buttons = DialogButton.CANCEL | okText;
    dialog.destroyOnClose = true;
    var form = new QOLForm(150, 230);
    build(form);
    dialog.addComponent(form);
    dialog.onDialogClosed = function(e) {
      if (e.button == okText)
      {
        try
        {
          onOk();
        }
        catch (err)
        {
          haxe.ui.containers.dialogs.Dialogs.messageBox(Std.string(err), 'Export failed', 'error');
        }
      }
    };
    dialog.showDialog(true);
  }

  static function defaultPath(ed:AnimatorState):String
    return 'animations/' + AnimIO.fileId(ed.doc.project.name);

  static function modeItems():Array<String>
    return ['timeline', 'symbols', 'labels'];

  static function modeLabels():Array<String>
    return ['This timeline as one animation', 'Every symbol is an animation', 'Every frame label is an animation'];

  public static function sparrowDialog(ed:AnimatorState):Void
  {
    var path = defaultPath(ed);
    var mode = 'timeline';
    var scale = 1.0;
    var padding = 2;
    formDialog('Export Sprite Atlas (Sparrow)', 'Export', form -> {
      form.textField('Save to images/', () -> path, v -> path = v);
      form.dropdown('Animations', modeItems, () -> mode, v -> mode = v, modeLabels);
      form.number('Scale', () -> scale, v -> scale = v, 0.05, 8, 0.05, 2);
      form.number('Padding (px)', () -> padding, v -> padding = Std.int(v), 0, 16, 1, 0);
      form.note('Makes images/<name>.png and .xml in your mod, ready for the Character Editor (Sparrow).');
    }, () -> {
      var res = exportSparrow(ed, path, mode, scale, padding);
      ed.notify('Exported', res);
    });
  }

  public static function animateDialog(ed:AnimatorState):Void
  {
    var path = defaultPath(ed);
    var mode = 'symbols';
    var scale = 1.0;
    formDialog('Export Animate Texture Atlas', 'Export', form -> {
      form.textField('Save to images/', () -> path, v -> path = v);
      form.dropdown('Animations', modeItems, () -> mode, v -> mode = v, modeLabels);
      form.number('Scale', () -> scale, v -> scale = v, 0.05, 8, 0.05, 2);
      form.note('Makes a folder with Animation.json, spritemap1.json and spritemap1.png. Each animation gets a frame '
        + 'label and a symbol, so the Character Editor can use "Animate atlas" with frame labels or symbols.');
    }, () -> {
      var res = exportAnimateAtlas(ed, path, mode, scale);
      ed.notify('Exported', res);
    });
  }

  public static function sequenceDialog(ed:AnimatorState):Void
  {
    var path = defaultPath(ed);
    var scale = 1.0;
    formDialog('Export PNG Sequence', 'Export', form -> {
      form.textField('Save to images/', () -> path, v -> path = v);
      form.number('Scale', () -> scale, v -> scale = v, 0.05, 8, 0.05, 2);
      form.note('One PNG per frame of this timeline, the full stage size.');
    }, () -> {
      var count = exportSequence(ed, path, scale);
      ed.notify('Exported', '$count frames to images/$path/');
    });
  }

  public static function flaDialog(ed:AnimatorState):Void
  {
    var path = 'export/' + AnimIO.fileId(ed.doc.project.name) + '.fla';
    formDialog('Export Adobe Animate File', 'Export', form -> {
      form.textField('Save as (in your mod)', () -> path, v -> path = v);
      form.note('Everything Animate understands: symbols, layers (folders, masks, guides, the camera), keyframes and labels, '
        + 'classic and shape tweens with their eases, shapes, images, sounds, color effects, filters and blend modes. '
        + 'Paint layers become images. Opens in Adobe Animate.');
    }, () -> {
      var bytes = XFLFile.write(ed.doc);
      var saved = ModWorkspace.saveBytes(path, bytes);
      ed.notify('Exported', saved);
    });
  }

  public static function psdDialog(ed:AnimatorState, animated:Bool):Void
  {
    var base = 'export/' + AnimIO.fileId(ed.doc.project.name);
    var path = animated ? base + '.psd' : base + '-frames';
    var zip = true;
    formDialog(animated ? 'Export Animated PSD (ToonSquid / Photoshop)' : 'Export Layered PSD per Frame (ibisPaint)', 'Export', form -> {
      form.textField(animated ? 'Save as (in your mod)' : 'Name (in your mod)', () -> path, v -> path = v);
      if (animated)
      {
        form.note('One layer group per frame (held frames share one), with Photoshop frame animation data. '
          + 'Photoshop plays it in Timeline > Frame Animation; ToonSquid imports it onto its timeline.');
      }
      else
      {
        form.check('Pack them into one .zip', () -> zip, v -> zip = v);
        form.note('One layered PSD per frame (frame0001.psd...). ibisPaint, Krita and GIMP open them with their layers; '
          + 'ToonSquid imports the .zip as a PSD sequence.');
      }
    }, () -> {
      if (animated)
      {
        if (!StringTools.endsWith(path.toLowerCase(), '.psd')) path += '.psd';
        var saved = ModWorkspace.saveBytes(path, PSDFile.writeAnimated(ed.doc, ed.sym));
        ed.notify('Exported', saved);
      }
      else
      {
        var len = AnimData.symbolLength(ed.sym);
        var files = [
          for (f in 0...len)
            {name: 'frame${StringTools.lpad('${f + 1}', '0', 4)}.psd', data: PSDFile.writeFrame(ed.doc, ed.sym, f)}
        ];
        if (zip)
        {
          var zpath = StringTools.endsWith(path.toLowerCase(), '.zip') ? path : path + '.zip';
          var saved = ModWorkspace.saveBytes(zpath, funkin.qol.util.QOLZip.write(files));
          ed.notify('Exported', '$len PSD files in $saved');
        }
        else
        {
          for (f in files)
            ModWorkspace.saveBytes('$path/${f.name}', f.data);
          ed.notify('Exported', '$len PSD files in $path/');
        }
      }
    });
  }

  //
  // Video, GIF, sound
  //

  /**
   * Every sound on the timeline's sound layers, mixed (16-bit stereo 44.1 kHz), or null if there are none.
   */
  public static function soundMix(doc:AnimDoc, sym:AnimSymbol):Null<haxe.io.Bytes>
  {
    var fps = doc.project.fps;
    var parts:Array<{sound:AnimSound, at:Float, from:Float, length:Float, volume:Float}> = [];
    for (l in sym.layers)
    {
      if (l.kind != 'audio' || !l.visible) continue;
      for (k in l.frames)
      {
        var snd = doc.getSound(k.sound);
        if (snd == null) continue;
        parts.push({
          sound: snd,
          at: k.start / fps,
          from: k.soundStart ?? 0,
          length: k.duration / fps,
          volume: l.volume ?? 1
        });
      }
    }
    if (parts.length == 0) return null;
    return AnimSound.mix(parts, AnimData.symbolLength(sym) / fps);
  }

  /**
   * One frame of a timeline, flattened over the canvas color (or `bg` if the canvas is transparent).
   */
  public static function flatFrame(doc:AnimDoc, sym:AnimSymbol, frame:Int, w:Int, h:Int, transparentOk:Bool, ?bg:Int = 0xFFFFFFFF,
      ?renderer:AnimRender):BitmapData
  {
    var stageBg = (doc.project.bg >>> 24) == 0 ? (transparentOk ? 0 : bg) : (doc.project.bg | 0xFF000000);
    var bmp = new BitmapData(w, h, true, stageBg);
    // Reusing one renderer for every frame keeps its shape cache (much faster for long animations).
    if (renderer == null) renderer = new AnimRender(doc);
    var spr = renderer.render(sym, frame, {forExport: true});
    var m = new Matrix();
    if (sym != doc.main) m.translate(doc.project.width / 2, doc.project.height / 2);
    m.scale(w / doc.project.width, h / doc.project.height);
    bmp.draw(spr, m, null, null, null, true);
    return bmp;
  }

  static function evenSize(doc:AnimDoc, scale:Float):{w:Int, h:Int}
  {
    // Video players like even sizes.
    var w = Std.int(Math.max(2, Math.round(doc.project.width * scale / 2) * 2));
    var h = Std.int(Math.max(2, Math.round(doc.project.height * scale / 2) * 2));
    return {w: w, h: h};
  }

  public static function videoDialog(ed:AnimatorState):Void
  {
    var path = 'export/' + AnimIO.fileId(ed.doc.project.name) + '.avi';
    var scale = 1.0;
    var quality = 90;
    var withSound = true;
    formDialog('Export Video (AVI)', 'Export', form -> {
      form.textField('Save as (in your mod)', () -> path, v -> path = v);
      form.number('Scale', () -> scale, v -> scale = v, 0.1, 4, 0.1, 2);
      form.number('Quality', () -> quality, v -> quality = Std.int(v), 10, 100, 5, 0);
      form.check('Include the sound layers', () -> withSound, v -> withSound = v);
      form.note('Motion-JPEG pictures with the sound mix: plays in VLC, Windows Media Player and video editors. '
        + 'Transparent canvases get a white background.');
    }, () -> {
      if (!StringTools.endsWith(path.toLowerCase(), '.avi')) path += '.avi';
      var size = evenSize(ed.doc, scale);
      var len = AnimData.symbolLength(ed.sym);
      var jpegs:Array<haxe.io.Bytes> = [];
      eachFrame(ed, 'Exporting video', len, (f, renderer) -> {
        var bmp = flatFrame(ed.doc, ed.sym, f, size.w, size.h, false, 0xFFFFFFFF, renderer);
        var ba:openfl.utils.ByteArray = bmp.encode(bmp.rect, new openfl.display.JPEGEncoderOptions(quality));
        jpegs.push(ba);
        bmp.dispose();
      }, () -> {
        var pcm = withSound ? soundMix(ed.doc, ed.sym) : null;
        var saved = ModWorkspace.saveBytes(path, AnimVideoExport.writeAvi(jpegs, size.w, size.h, ed.doc.project.fps, pcm));
        ed.notify('Exported', '$saved ($len frames${pcm != null ? ', with sound' : ''})');
      });
    });
  }

  /**
   * Render every frame a few at a time with a progress bar (Cancel stops), so long animations don't freeze the game.
   */
  public static function eachFrame(ed:AnimatorState, title:String, len:Int, render:(Int, AnimRender) -> Void, done:Void->Void):Void
  {
    var renderer = new AnimRender(ed.doc);
    var cancelled = false;
    var progress = ed.showProgress(title, 'Frame 1 of $len', () -> cancelled = true);
    var f = 0;
    function step():Void
    {
      if (cancelled) return;
      var t0 = haxe.Timer.stamp();
      try
      {
        while (f < len && haxe.Timer.stamp() - t0 < 0.1)
        {
          render(f, renderer);
          f++;
        }
      }
      catch (e:Dynamic)
      {
        cancelled = true;
        progress.close();
        ed.alert('Export failed', 'Frame ${f + 1}: $e');
        return;
      }
      if (f < len)
      {
        progress.update(f / len, 'Frame ${f + 1} of $len');
        haxe.Timer.delay(step, 1);
        return;
      }
      cancelled = true;
      progress.close();
      try
      {
        done();
      }
      catch (e:Dynamic)
      {
        ed.alert('Export failed', Std.string(e));
      }
    }
    step();
  }

  public static function gifDialog(ed:AnimatorState):Void
  {
    var path = 'export/' + AnimIO.fileId(ed.doc.project.name) + '.gif';
    var scale = 0.5;
    formDialog('Export Animated GIF', 'Export', form -> {
      form.textField('Save as (in your mod)', () -> path, v -> path = v);
      form.number('Scale', () -> scale, v -> scale = v, 0.05, 2, 0.05, 2);
      form.note('Loops forever. GIFs have up to 256 colors and on/off transparency; a transparent canvas stays see-through.');
    }, () -> {
      if (!StringTools.endsWith(path.toLowerCase(), '.gif')) path += '.gif';
      var w = Std.int(Math.max(1, Math.round(ed.doc.project.width * scale)));
      var h = Std.int(Math.max(1, Math.round(ed.doc.project.height * scale)));
      var len = AnimData.symbolLength(ed.sym);
      var frames:Array<haxe.io.Bytes> = [];
      eachFrame(ed, 'Exporting GIF', len, (f, renderer) -> {
        var bmp = flatFrame(ed.doc, ed.sym, f, w, h, true, 0xFFFFFFFF, renderer);
        frames.push(AnimIO.argbBytes(bmp));
        bmp.dispose();
      }, () -> {
        var saved = ModWorkspace.saveBytes(path, AnimVideoExport.writeGif(frames, w, h, ed.doc.project.fps));
        ed.notify('Exported', '$saved ($len frames, ${w}x$h)');
      });
    });
  }

  public static function soundDialog(ed:AnimatorState):Void
  {
    var pcm = soundMix(ed.doc, ed.sym);
    if (pcm == null)
    {
      ed.alert('No sounds', 'This timeline has no sound layers yet (File > Import > Audio).');
      return;
    }
    var path = 'export/' + AnimIO.fileId(ed.doc.project.name) + '.wav';
    formDialog('Export Sound Mix', 'Export', form -> {
      form.textField('Save as (in your mod)', () -> path, v -> path = v);
      form.note('Every sound layer mixed into one WAV (44.1 kHz stereo), as long as the timeline.');
    }, () -> {
      if (!StringTools.endsWith(path.toLowerCase(), '.wav')) path += '.wav';
      var saved = ModWorkspace.saveBytes(path, AnimSound.writeWav(pcm, 44100, 2));
      ed.notify('Exported', saved);
    });
  }

  //
  // Gathering frames
  //

  /**
   * The animations to export.
   */
  public static function animationSets(ed:AnimatorState, mode:String):Array<AnimExportSet>
  {
    var out:Array<AnimExportSet> = [];
    switch (mode)
    {
      case 'symbols':
        for (i in 1...ed.doc.project.symbols.length)
        {
          var s = ed.doc.project.symbols[i];
          out.push({name: s.name, symbol: s, from: 0, to: AnimData.symbolLength(s)});
        }
        if (out.length == 0) out.push({name: ed.sym.name, symbol: ed.sym, from: 0, to: AnimData.symbolLength(ed.sym)});
      case 'labels':
        var sym = ed.sym;
        var labels:Array<{name:String, start:Int}> = [];
        for (l in sym.layers)
          for (k in l.frames)
            if (k.label != null && k.label != '') labels.push({name: k.label, start: k.start});
        labels.sort((a, b) -> a.start - b.start);
        var len = AnimData.symbolLength(sym);
        for (i in 0...labels.length)
        {
          var end = i + 1 < labels.length ? labels[i + 1].start : len;
          out.push({name: labels[i].name, symbol: sym, from: labels[i].start, to: end});
        }
        if (out.length == 0) out.push({name: ed.sym.name, symbol: sym, from: 0, to: len});
      default:
        var name = ed.sym == ed.doc.main ? AnimIO.fileId(ed.doc.project.name) : ed.sym.name;
        out.push({name: name, symbol: ed.sym, from: 0, to: AnimData.symbolLength(ed.sym)});
    }
    return out;
  }

  /**
   * Render every frame of the sets, trimmed, with identical frames shared.
   */
  public static function renderFrames(doc:AnimDoc, sets:Array<AnimExportSet>, scale:Float):Array<AnimExportFrame>
  {
    var renderer = new AnimRender(doc);
    var frames:Array<AnimExportFrame> = [];
    var hashes = new Map<String, Int>();
    for (set in sets)
    {
      // Common bounds over the whole animation so frames line up.
      var sprites:Array<Sprite> = [];
      var union:Null<Rectangle> = null;
      for (f in set.from...set.to)
      {
        var spr = renderer.render(set.symbol, f, {forExport: true});
        var holder = new Sprite();
        holder.addChild(spr);
        sprites.push(holder);
        var b = holder.getBounds(holder);
        if (b.width > 0 && b.height > 0) union = union == null ? b : union.union(b);
      }
      if (union == null) union = new Rectangle(0, 0, 1, 1);
      union.x = Math.floor(union.x - 2);
      union.y = Math.floor(union.y - 2);
      union.width = Math.ceil(union.width + 4);
      union.height = Math.ceil(union.height + 4);
      var fw = Std.int(Math.max(1, Math.ceil(union.width * scale)));
      var fh = Std.int(Math.max(1, Math.ceil(union.height * scale)));
      for (i in 0...sprites.length)
      {
        var full = new BitmapData(fw, fh, true, 0);
        var m = new Matrix();
        m.translate(-union.x, -union.y);
        m.scale(scale, scale);
        full.draw(sprites[i], m, null, null, null, true);
        var trim = AnimPaint.opaqueBounds(full);
        var frame:AnimExportFrame = {
          anim: set.name,
          index: i,
          bmp: null,
          trim: trim ?? new Rectangle(0, 0, 1, 1),
          frameW: fw,
          frameH: fh,
          originX: union.x,
          originY: union.y
        };
        if (trim == null)
        {
          frame.bmp = new BitmapData(1, 1, true, 0);
        }
        else
        {
          var cut = new BitmapData(Std.int(trim.width), Std.int(trim.height), true, 0);
          cut.copyPixels(full, trim, new Point(0, 0));
          frame.bmp = cut;
        }
        full.dispose();
        var hash = hashBitmap(frame.bmp) + '@${Std.int(frame.trim.x)},${Std.int(frame.trim.y)}';
        frame.hash = hash;
        if (hashes.exists(hash)) frame.dupOf = hashes.get(hash);
        else
          hashes.set(hash, frames.length);
        frames.push(frame);
      }
    }
    return frames;
  }

  static function hashBitmap(bmp:BitmapData):String
  {
    var bytes = AnimIO.argbBytes(bmp);
    return '${bmp.width}x${bmp.height}:' + haxe.crypto.Md5.make(bytes).toHex();
  }

  /**
   * Shelf-pack the unique frames. Returns the atlas size.
   */
  public static function pack(frames:Array<AnimExportFrame>, padding:Int):{w:Int, h:Int}
  {
    var unique = [for (f in frames) if (f.dupOf == null) f];
    var area = 0.0;
    var widest = 1;
    for (f in unique)
    {
      area += (f.bmp.width + padding) * (f.bmp.height + padding);
      if (f.bmp.width + padding > widest) widest = f.bmp.width + padding;
    }
    var maxW = Std.int(Math.max(widest, Math.min(8192, Math.ceil(Math.sqrt(area) * 1.15))));
    var sorted = unique.copy();
    sorted.sort((a, b) -> b.bmp.height - a.bmp.height);
    var x = 0, y = 0, rowH = 0, usedW = 1;
    for (f in sorted)
    {
      var w = f.bmp.width + padding, h = f.bmp.height + padding;
      if (x + w > maxW)
      {
        x = 0;
        y += rowH;
        rowH = 0;
      }
      f.x = x;
      f.y = y;
      x += w;
      if (h > rowH) rowH = h;
      if (x > usedW) usedW = x;
    }
    for (f in frames)
    {
      if (f.dupOf != null)
      {
        f.x = frames[f.dupOf].x;
        f.y = frames[f.dupOf].y;
      }
    }
    return {w: Std.int(Math.max(1, usedW)), h: Std.int(Math.max(1, y + rowH))};
  }

  static function buildAtlas(frames:Array<AnimExportFrame>, size:{w:Int, h:Int}):BitmapData
  {
    var atlas = new BitmapData(size.w, size.h, true, 0);
    for (f in frames)
      if (f.dupOf == null) atlas.copyPixels(f.bmp, f.bmp.rect, new Point(f.x, f.y), null, null, true);
    return atlas;
  }

  //
  // Sparrow
  //

  public static function exportSparrow(ed:AnimatorState, path:String, mode:String, scale:Float, padding:Int):String
  {
    path = cleanPath(path);
    var frames = renderFrames(ed.doc, animationSets(ed, mode), scale);
    var size = pack(frames, padding);
    var atlas = buildAtlas(frames, size);
    var name = haxe.io.Path.withoutDirectory(path);
    var xml = new StringBuf();
    xml.add('<?xml version="1.0" encoding="utf-8"?>\n');
    xml.add('<!-- Made with the QOL Slice Animator -->\n');
    xml.add('<TextureAtlas imagePath="$name.png">\n');
    for (f in frames)
    {
      var fname = '${f.anim}${StringTools.lpad('${f.index}', '0', 4)}';
      xml.add('  <SubTexture name="${escape(fname)}" x="${f.x}" y="${f.y}" width="${f.bmp.width}" height="${f.bmp.height}" '
        + 'frameX="${-Std.int(f.trim.x)}" frameY="${-Std.int(f.trim.y)}" frameWidth="${f.frameW}" frameHeight="${f.frameH}"/>\n');
    }
    xml.add('</TextureAtlas>\n');
    ModWorkspace.saveBytes('images/$path.png', AnimIO.encodePNG(atlas));
    ModWorkspace.saveText('images/$path.xml', xml.toString());
    var unique = [for (f in frames) if (f.dupOf == null) f].length;
    for (f in frames)
      f.bmp?.dispose();
    atlas.dispose();
    return 'images/$path.png + .xml (${frames.length} frames, $unique unique, ${size.w}x${size.h})';
  }

  static function escape(s:String):String
    return StringTools.htmlEscape(s, true);

  static function cleanPath(p:String):String
  {
    p = StringTools.trim(p).split('\\').join('/');
    while (StringTools.startsWith(p, '/'))
      p = p.substr(1);
    if (StringTools.startsWith(p, 'images/')) p = p.substr(7);
    if (StringTools.endsWith(p, '.png') || StringTools.endsWith(p, '.xml')) p = p.substr(0, p.length - 4);
    return p == '' ? 'animation' : p;
  }

  //
  // Animate texture atlas
  //

  public static function exportAnimateAtlas(ed:AnimatorState, path:String, mode:String, scale:Float):String
  {
    path = cleanPath(path);
    var sets = animationSets(ed, mode);
    var frames = renderFrames(ed.doc, sets, scale);
    var size = pack(frames, 2);
    var atlas = buildAtlas(frames, size);

    var sprites:Array<Dynamic> = [];
    var spriteName = new Map<Int, String>();
    for (i in 0...frames.length)
    {
      var f = frames[i];
      if (f.dupOf != null) continue;
      var n = '${sprites.length}';
      spriteName.set(i, n);
      sprites.push({
        SPRITE: {
          name: n,
          x: f.x,
          y: f.y,
          w: f.bmp.width,
          h: f.bmp.height,
          rotated: false
        }
      });
    }

    // One symbol per animation, each frame showing its atlas sprite.
    var symbols:Array<Dynamic> = [];
    var mainFrames:Array<Dynamic> = [];
    var cursor = 0;
    for (set in sets)
    {
      var setFrames = [for (f in frames) if (f.anim == set.name) f];
      var fr:Array<Dynamic> = [];
      for (i in 0...setFrames.length)
      {
        var f = setFrames[i];
        var idx = frames.indexOf(f);
        var src = f.dupOf ?? idx;
        // Sprite position in the symbol: trim offset, back in unscaled coordinates.
        var ox = f.originX + f.trim.x / scale;
        var oy = f.originY + f.trim.y / scale;
        fr.push({
          I: i,
          DU: 1,
          E: [
            {
              ASI: {
                N: spriteName.get(src),
                M3D: [1 / scale, 0, 0, 0, 0, 1 / scale, 0, 0, 0, 0, 1, 0, ox, oy, 0, 1]
              }
            }
          ]
        });
      }
      symbols.push({SN: set.name, TL: {L: [{LN: 'Layer_1', FR: fr}]}});
      mainFrames.push({
        N: set.name,
        I: cursor,
        DU: setFrames.length,
        E: [
          {
            SI: {
              SN: set.name,
              IN: '',
              ST: 'G',
              FF: 0,
              LP: 'LP',
              TRP: {x: 0, y: 0},
              M3D: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
            }
          }
        ]
      });
      cursor += setFrames.length;
    }
    var animation = {
      AN: {
        N: AnimIO.fileId(ed.doc.project.name),
        SN: 'Scene 1',
        TL: {L: [{LN: 'Labels', FR: mainFrames}]}
      },
      SD: {S: symbols},
      MD: {FRT: ed.doc.project.fps}
    };
    var spritemap = {
      ATLAS: {SPRITES: sprites},
      meta: {
        app: 'QOL Slice Animator',
        version: '1.0',
        image: 'spritemap1.png',
        format: 'RGBA8888',
        size: {w: size.w, h: size.h},
        resolution: '1'
      }
    };
    ModWorkspace.saveText('images/$path/Animation.json', haxe.Json.stringify(animation));
    ModWorkspace.saveText('images/$path/spritemap1.json', haxe.Json.stringify(spritemap));
    ModWorkspace.saveBytes('images/$path/spritemap1.png', AnimIO.encodePNG(atlas));
    for (f in frames)
      f.bmp?.dispose();
    atlas.dispose();
    return 'images/$path/ (Animation.json, spritemap1.json, spritemap1.png; ${sets.length} animations)';
  }

  //
  // PNG sequence
  //

  public static function exportSequence(ed:AnimatorState, path:String, scale:Float):Int
  {
    path = cleanPath(path);
    var renderer = new AnimRender(ed.doc);
    var sym = ed.sym;
    var len = AnimData.symbolLength(sym);
    var w = Std.int(Math.max(1, ed.doc.project.width * scale)), h = Std.int(Math.max(1, ed.doc.project.height * scale));
    var ox = sym == ed.doc.main ? 0 : ed.doc.project.width / 2;
    var oy = sym == ed.doc.main ? 0 : ed.doc.project.height / 2;
    for (f in 0...len)
    {
      var bmp = new BitmapData(w, h, true, (ed.doc.project.bg >>> 24) == 0 ? 0 : (ed.doc.project.bg | 0xFF000000));
      var spr = renderer.render(sym, f, {forExport: true});
      var m = new Matrix();
      m.translate(ox, oy);
      m.scale(scale, scale);
      bmp.draw(spr, m, null, null, null, true);
      ModWorkspace.saveBytes('images/$path/${AnimIO.fileId(sym.name)}${StringTools.lpad('${f + 1}', '0', 4)}.png', AnimIO.encodePNG(bmp));
      bmp.dispose();
    }
    return len;
  }

  /**
   * Render one frame of a symbol at stage size (used by PSD export).
   */
  public static function renderStageFrame(doc:AnimDoc, sym:AnimSymbol, frame:Int, ?onlyLayer:Int = -1):BitmapData
  {
    var w = doc.project.width, h = doc.project.height;
    var bmp = new BitmapData(w, h, true, 0);
    var renderer = new AnimRender(doc);
    var ox = sym == doc.main ? 0 : w / 2;
    var oy = sym == doc.main ? 0 : h / 2;
    var target = sym;
    if (onlyLayer >= 0)
    {
      target = {
        id: sym.id,
        name: sym.name,
        kind: sym.kind,
        layers: [sym.layers[onlyLayer]]
      };
    }
    var spr = renderer.render(target, frame, {forExport: true, camera: sym == doc.main ? renderer.cameraMatrix(sym, frame) : null});
    var m = new Matrix();
    m.translate(ox, oy);
    bmp.draw(spr, m, null, null, null, true);
    return bmp;
  }
}
#end
