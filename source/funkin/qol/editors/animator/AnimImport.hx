package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import funkin.qol.editors.animator.AnimData;
import funkin.qol.util.QOLFilePicker;
import haxe.io.Bytes;
import openfl.display.BitmapData;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;

typedef SparrowFrame =
{
  var name:String;
  var x:Int;
  var y:Int;
  var w:Int;
  var h:Int;
  var fx:Int;
  var fy:Int;
  var fw:Int;
  var fh:Int;
  var rotated:Bool;
}

/**
 * Bringing art into the Animator: images, Sparrow spritesheets, Animate texture atlases, PNG sequences, sprite sheet
 * grids, Animate .fla/.xfl files, PSDs (Photoshop, ToonSquid, ibisPaint) and videos.
 */
class AnimImport
{
  //
  // Library image
  //

  public static function importLibraryImage(ed:AnimatorState):Void
  {
    QOLFilePicker.open('Images', ['png'], true, files -> {
      var count = 0;
      ed.doc.checkpoint();
      for (f in files)
      {
        var bmp = AnimIO.decodePNG(f.bytes);
        if (bmp == null) continue;
        ed.doc.addBitmap(bmp, haxe.io.Path.withoutExtension(f.name), true);
        count++;
      }
      ed.doc.changed();
      ed.notify('Imported', '$count image(s) added to the Library. Select one there and click "Place on stage".');
    });
  }

  //
  // Sparrow
  //

  public static function parseSparrow(xml:String):Array<SparrowFrame>
  {
    var out:Array<SparrowFrame> = [];
    var root = Xml.parse(xml).firstElement();
    if (root == null) return out;
    for (sub in root.elementsNamed('SubTexture'))
    {
      inline function num(n:String, def:Int):Int
      {
        var v = sub.get(n);
        return v == null ? def : Std.int(Std.parseFloat(v));
      }
      var w = num('width', 0), h = num('height', 0);
      out.push({
        name: sub.get('name') ?? '',
        x: num('x', 0),
        y: num('y', 0),
        w: w,
        h: h,
        fx: num('frameX', 0),
        fy: num('frameY', 0),
        fw: num('frameWidth', w),
        fh: num('frameHeight', h),
        rotated: sub.get('rotated') == 'true'
      });
    }
    return out;
  }

  /**
   * Cut one Sparrow frame out of its atlas, at its full (untrimmed) size.
   */
  public static function cutFrame(atlas:BitmapData, f:SparrowFrame):BitmapData
  {
    var out = new BitmapData(Std.int(Math.max(1, f.fw)), Std.int(Math.max(1, f.fh)), true, 0);
    if (f.rotated)
    {
      // Stored turned 90 degrees in the atlas (like Flixel: the region is x/y/width/height, turned back the other way).
      var piece = new BitmapData(Std.int(Math.max(1, f.w)), Std.int(Math.max(1, f.h)), true, 0);
      piece.copyPixels(atlas, new Rectangle(f.x, f.y, f.w, f.h), new Point(0, 0));
      var m = new Matrix();
      m.rotate(-Math.PI / 2);
      m.translate(0, f.w);
      m.translate(-f.fx, -f.fy);
      out.draw(piece, m);
      piece.dispose();
    }
    else
    {
      out.copyPixels(atlas, new Rectangle(f.x, f.y, f.w, f.h), new Point(-f.fx, -f.fy));
    }
    return out;
  }

  public static function animName(frameName:String):String
  {
    var n = frameName;
    if (StringTools.endsWith(n.toLowerCase(), '.png')) n = n.substr(0, n.length - 4);
    var re = ~/[0-9]+$/;
    n = re.replace(n, '');
    return StringTools.trim(n) == '' ? 'anim' : n;
  }

  public static function importSparrow(ed:AnimatorState):Void
  {
    QOLFilePicker.open('Sparrow spritesheet (pick the .xml and the .png)', ['xml', 'png'], true, files -> {
      var xmlFile = Lambda.find(files, f -> QOLFilePicker.ext(f.name) == 'xml');
      if (xmlFile == null)
      {
        ed.alert('No XML', 'Pick the spritesheet\'s .xml file (and its .png).');
        return;
      }
      var pngBytes:Null<Bytes> = null;
      var png = Lambda.find(files, f -> QOLFilePicker.ext(f.name) == 'png');
      if (png != null) pngBytes = png.bytes;
      else
      {
        var root = Xml.parse(xmlFile.bytes.toString()).firstElement();
        var imagePath = root?.get('imagePath') ?? (haxe.io.Path.withoutExtension(xmlFile.name) + '.png');
        pngBytes = QOLFilePicker.sibling(xmlFile, haxe.io.Path.withoutDirectory(imagePath));
      }
      if (pngBytes == null)
      {
        ed.alert('No PNG', 'Pick both the .xml and the .png of the spritesheet.');
        return;
      }
      var atlas = AnimIO.decodePNG(pngBytes);
      if (atlas == null)
      {
        ed.alert('Bad PNG', 'The spritesheet image could not be read.');
        return;
      }
      var frames = parseSparrow(xmlFile.bytes.toString());
      var doc = framesToDoc(haxe.io.Path.withoutExtension(xmlFile.name), [for (f in frames) {anim: animName(f.name), bmp: cutFrame(atlas, f)}], ed.doc.project.fps);
      atlas.dispose();
      ed.setDocument(doc);
      ed.notify('Imported', '${frames.length} frames. Each animation is a symbol with a bitmap layer you can paint on; '
        + 'the Scene has a frame label for each one.');
    });
  }

  /**
   * Build a document from named frames: one symbol per animation (a bitmap layer, a keyframe per frame) and a Scene
   * timeline with a labeled span per animation.
   */
  public static function framesToDoc(name:String, frames:Array<{anim:String, bmp:BitmapData}>, fps:Float):AnimDoc
  {
    var maxW = 16, maxH = 16;
    for (f in frames)
    {
      if (f.bmp.width > maxW) maxW = f.bmp.width;
      if (f.bmp.height > maxH) maxH = f.bmp.height;
    }
    var project = AnimData.newProject(name, maxW, maxH, fps);
    var doc = new AnimDoc(project);
    var order:Array<String> = [];
    var byAnim = new Map<String, Array<BitmapData>>();
    for (f in frames)
    {
      if (!byAnim.exists(f.anim))
      {
        byAnim.set(f.anim, []);
        order.push(f.anim);
      }
      byAnim.get(f.anim).push(f.bmp);
    }
    var scene = project.symbols[0];
    scene.layers[0].name = 'Animations';
    scene.layers[0].frames = [];
    var cursor = 0;
    for (anim in order)
    {
      var list = byAnim.get(anim);
      var sym = AnimData.newSymbol(AnimData.makeId('sym'), anim);
      var layer = sym.layers[0];
      layer.name = 'Frames';
      layer.kind = 'bitmap';
      layer.frames = [];
      for (i in 0...list.length)
      {
        // Canvases are stage-sized and centered on the symbol's origin; frames sit in the middle.
        var canvas = new BitmapData(maxW, maxH, true, 0);
        canvas.copyPixels(list[i], list[i].rect, new Point(Std.int((maxW - list[i].width) / 2), Std.int((maxH - list[i].height) / 2)));
        list[i].dispose();
        layer.frames.push({
          start: i,
          duration: 1,
          elements: [],
          bitmap: doc.addBitmap(canvas, 'canvas', false),
          bx: -maxW / 2,
          by: -maxH / 2
        });
      }
      project.symbols.push(sym);
      var inst = AnimData.identity('symbol');
      inst.symbol = sym.id;
      inst.loop = 'once';
      inst.firstFrame = 0;
      inst.tx = maxW / 2;
      inst.ty = maxH / 2;
      scene.layers[0].frames.push({
        start: cursor,
        duration: list.length,
        elements: [inst],
        label: anim
      });
      cursor += list.length;
    }
    if (scene.layers[0].frames.length == 0) scene.layers[0].frames.push({start: 0, duration: 1, elements: []});
    doc.clearHistory();
    return doc;
  }

  //
  // PNG sequence / grid
  //

  public static function importSequence(ed:AnimatorState):Void
  {
    QOLFilePicker.open('PNG sequence (pick every frame)', ['png'], true, files -> {
      files.sort((a, b) -> Reflect.compare(a.name.toLowerCase(), b.name.toLowerCase()));
      var bmps = [for (f in files) AnimIO.decodePNG(f.bytes)].filter(b -> b != null);
      if (bmps.length == 0) return;
      addBitmapFrames(ed, haxe.io.Path.withoutExtension(files[0].name), bmps);
    });
  }

  public static function importGrid(ed:AnimatorState):Void
  {
    QOLFilePicker.open('Sprite sheet', ['png'], false, files -> {
      var sheet = AnimIO.decodePNG(files[0].bytes);
      if (sheet == null) return;
      var cols = 4, rows = 1, count = 0;
      AnimExport.formDialog('Sprite sheet grid', 'Import', form -> {
        form.note('${sheet.width} x ${sheet.height} pixels. How is it divided?');
        form.number('Columns', () -> cols, v -> cols = Std.int(v), 1, 256, 1, 0);
        form.number('Rows', () -> rows, v -> rows = Std.int(v), 1, 256, 1, 0);
        form.number('Frames (0 = all)', () -> count, v -> count = Std.int(v), 0, 65536, 1, 0);
      }, () -> {
        var cw = Std.int(sheet.width / cols), ch = Std.int(sheet.height / rows);
        var total = count > 0 ? Std.int(Math.min(count, cols * rows)) : cols * rows;
        var bmps:Array<BitmapData> = [];
        for (i in 0...total)
        {
          var b = new BitmapData(cw, ch, true, 0);
          b.copyPixels(sheet, new Rectangle((i % cols) * cw, Std.int(i / cols) * ch, cw, ch), new Point(0, 0));
          bmps.push(b);
        }
        addBitmapFrames(ed, haxe.io.Path.withoutExtension(files[0].name), bmps);
      });
    });
  }

  /**
   * Put frames on a new bitmap layer of the current timeline, one keyframe each, starting at the playhead.
   */
  public static function addBitmapFrames(ed:AnimatorState, name:String, bmps:Array<BitmapData>):Void
  {
    var doc = ed.doc;
    doc.checkpoint();
    // An empty document takes the size of the frames.
    var empty = doc.project.symbols.length == 1 && AnimData.symbolLength(doc.main) <= 1 && doc.main.layers.length == 1
      && doc.main.layers[0].frames[0].elements.length == 0;
    if (empty)
    {
      var w = 16, h = 16;
      for (b in bmps)
      {
        if (b.width > w) w = b.width;
        if (b.height > h) h = b.height;
      }
      doc.project.width = w;
      doc.project.height = h;
    }
    var sym = ed.sym;
    var layer = AnimData.newLayer(name, 'bitmap', sym.layers.length);
    layer.frames = [];
    var inSymbol = sym != doc.main;
    var start = ed.frame;
    if (start > 0) layer.frames.push({start: 0, duration: start, elements: []});
    for (i in 0...bmps.length)
    {
      var canvas = new BitmapData(doc.project.width, doc.project.height, true, 0);
      canvas.copyPixels(bmps[i], bmps[i].rect, new Point(Std.int((doc.project.width - bmps[i].width) / 2), Std.int((doc.project.height - bmps[i].height) / 2)));
      bmps[i].dispose();
      var k:AnimKeyframe = {
        start: start + i,
        duration: 1,
        elements: [],
        bitmap: doc.addBitmap(canvas, 'canvas', false)
      };
      if (inSymbol)
      {
        k.bx = -doc.project.width / 2;
        k.by = -doc.project.height / 2;
      }
      layer.frames.push(k);
    }
    sym.layers.insert(0, layer);
    doc.changed();
    if (empty) ed.fitView();
    ed.notify('Imported', '${bmps.length} frames on the new bitmap layer "$name".');
  }

  //
  // Animate texture atlas
  //

  static function f(o:Dynamic, short:String, long:String):Dynamic
  {
    if (o == null) return null;
    var v = Reflect.field(o, short);
    return v != null ? v : Reflect.field(o, long);
  }

  public static function importAnimateAtlas(ed:AnimatorState):Void
  {
    QOLFilePicker.open('Animate atlas (pick Animation.json, spritemap*.json and spritemap*.png)', ['json', 'png'], true, files -> {
      var animFile = Lambda.find(files, x -> x.name.toLowerCase() == 'animation.json');
      if (animFile == null)
      {
        ed.alert('No Animation.json', 'Pick the atlas\'s Animation.json together with its spritemap files.');
        return;
      }
      // Spritemaps: pick them, or (desktop) they're found next to Animation.json.
      var maps:Array<{json:Dynamic, png:BitmapData}> = [];
      var i = 1;
      while (i < 32)
      {
        var jn = 'spritemap$i.json', pn = 'spritemap$i.png';
        var jb = Lambda.find(files, x -> x.name.toLowerCase() == jn)?.bytes ?? QOLFilePicker.sibling(animFile, jn);
        var pb = Lambda.find(files, x -> x.name.toLowerCase() == pn)?.bytes ?? QOLFilePicker.sibling(animFile, pn);
        if (jb == null || pb == null)
        {
          if (i == 1)
          {
            // Some atlases use "spritemap.json".
            jb = Lambda.find(files, x -> x.name.toLowerCase() == 'spritemap.json')?.bytes ?? QOLFilePicker.sibling(animFile, 'spritemap.json');
            pb = Lambda.find(files, x -> x.name.toLowerCase() == 'spritemap.png')?.bytes ?? QOLFilePicker.sibling(animFile, 'spritemap.png');
            if (jb == null || pb == null) break;
          }
          else
            break;
        }
        var text = jb.toString();
        if (text.charCodeAt(0) == 0xFEFF) text = text.substr(1);
        maps.push({json: haxe.Json.parse(text), png: AnimIO.decodePNG(pb)});
        i++;
      }
      if (maps.length == 0)
      {
        ed.alert('No spritemap', 'Pick the spritemap .json and .png files too.');
        return;
      }
      var text = animFile.bytes.toString();
      if (text.charCodeAt(0) == 0xFEFF) text = text.substr(1);
      var doc = animateToDoc(haxe.Json.parse(text), maps, ed.doc.project.fps);
      ed.setDocument(doc);
      ed.notify('Imported', 'Animate atlas with ${doc.project.symbols.length - 1} symbols.');
    });
  }

  public static function animateToDoc(anim:Dynamic, maps:Array<{json:Dynamic, png:BitmapData}>, fps:Float):AnimDoc
  {
    var project = AnimData.newProject('Imported Atlas', 1024, 1024, fps);
    var doc = new AnimDoc(project);
    var md = f(anim, 'MD', 'metadata');
    var frt = f(md, 'FRT', 'framerate');
    if (frt != null) project.fps = frt;

    // Atlas sprites -> bitmaps.
    var spriteIds = new Map<String, String>();
    for (map in maps)
    {
      if (map.png == null) continue;
      var atlas = f(map.json, 'ATLAS', 'ATLAS');
      var sprites:Array<Dynamic> = f(atlas, 'SPRITES', 'SPRITES') ?? [];
      for (entry in sprites)
      {
        var sp = f(entry, 'SPRITE', 'SPRITE');
        var x = Std.int(sp.x), y = Std.int(sp.y), w = Std.int(sp.w), h = Std.int(sp.h);
        var rotated = sp.rotated == true;
        var bmp:BitmapData;
        if (rotated)
        {
          var piece = new BitmapData(Std.int(Math.max(1, w)), Std.int(Math.max(1, h)), true, 0);
          piece.copyPixels(map.png, new Rectangle(x, y, w, h), new Point(0, 0));
          bmp = new BitmapData(Std.int(Math.max(1, h)), Std.int(Math.max(1, w)), true, 0);
          var m = new Matrix();
          m.rotate(-Math.PI / 2);
          m.translate(0, w);
          bmp.draw(piece, m);
          piece.dispose();
        }
        else
        {
          bmp = new BitmapData(Std.int(Math.max(1, w)), Std.int(Math.max(1, h)), true, 0);
          bmp.copyPixels(map.png, new Rectangle(x, y, w, h), new Point(0, 0));
        }
        spriteIds.set(Std.string(sp.name), doc.addBitmap(bmp, 'sprite ${sp.name}', false));
      }
    }

    // Symbols.
    var symIds = new Map<String, String>();
    var sd = f(anim, 'SD', 'SYMBOL_DICTIONARY');
    var symList:Array<Dynamic> = f(sd, 'S', 'Symbols') ?? [];
    for (s in symList)
      symIds.set(f(s, 'SN', 'SYMBOL_name'), AnimData.makeId('sym'));
    for (s in symList)
    {
      var name:String = f(s, 'SN', 'SYMBOL_name');
      var sym = timelineToSymbol(symIds.get(name), name, f(s, 'TL', 'TIMELINE'), symIds, spriteIds);
      project.symbols.push(sym);
    }
    var an = f(anim, 'AN', 'ANIMATION');
    project.name = f(an, 'N', 'name') ?? 'Imported Atlas';
    var main = timelineToSymbol('scene', 'Scene', f(an, 'TL', 'TIMELINE'), symIds, spriteIds);
    project.symbols[0] = main;

    // Size the stage around what the scene shows, and move it into view.
    var r = new AnimRender(doc).render(main, 0, {forExport: true});
    var b = r.getBounds(r);
    if (b.width > 0 && b.height > 0)
    {
      var pad = 40;
      project.width = Std.int(Math.min(4096, Math.ceil(b.width + pad * 2)));
      project.height = Std.int(Math.min(4096, Math.ceil(b.height + pad * 2)));
      var dx = pad - b.x, dy = pad - b.y;
      for (l in main.layers)
        for (k in l.frames)
          for (e in k.elements)
          {
            e.tx += dx;
            e.ty += dy;
          }
    }
    doc.clearHistory();
    return doc;
  }

  static function timelineToSymbol(id:String, name:String, tl:Dynamic, symIds:Map<String, String>, spriteIds:Map<String, String>):AnimSymbol
  {
    var sym:AnimSymbol = {
      id: id,
      name: name,
      kind: 'graphic',
      layers: []
    };
    var layers:Array<Dynamic> = f(tl, 'L', 'LAYERS') ?? [];
    for (li in 0...layers.length)
    {
      var l = layers[li];
      var layer = AnimData.newLayer(f(l, 'LN', 'Layer_name') ?? 'Layer ${li + 1}', 'vector', li);
      layer.frames = [];
      var frames:Array<Dynamic> = f(l, 'FR', 'Frames') ?? [];
      for (fr in frames)
      {
        var start:Int = Std.int(f(fr, 'I', 'index') ?? 0);
        var dur:Int = Std.int(f(fr, 'DU', 'duration') ?? 1);
        var key:AnimKeyframe = {start: start, duration: dur, elements: []};
        var label = f(fr, 'N', 'name');
        if (label != null && label != '') key.label = label;
        var els:Array<Dynamic> = f(fr, 'E', 'elements') ?? [];
        for (e in els)
        {
          var si = f(e, 'SI', 'SYMBOL_Instance');
          var asi = f(e, 'ASI', 'ATLAS_SPRITE_instance');
          if (si != null)
          {
            var el = AnimData.identity('symbol');
            el.symbol = symIds.get(f(si, 'SN', 'SYMBOL_name'));
            if (el.symbol == null) continue;
            setMatrix3D(el, f(si, 'M3D', 'Matrix3D'));
            el.firstFrame = Std.int(f(si, 'FF', 'firstFrame') ?? 0);
            var lp:String = f(si, 'LP', 'loop') ?? 'LP';
            el.loop = switch (lp)
            {
              case 'PO' | 'playonce': 'once';
              case 'SF' | 'singleframe': 'single';
              default: 'loop';
            };
            applyColor(el, f(si, 'C', 'color'));
            applyFilters(el, f(si, 'F', 'filters'));
            var instName = f(si, 'IN', 'Instance_Name');
            if (instName != null && instName != '') el.name = instName;
            key.elements.push(el);
          }
          else if (asi != null)
          {
            var el = AnimData.identity('bitmap');
            el.bitmap = spriteIds.get(Std.string(f(asi, 'N', 'name')));
            if (el.bitmap == null) continue;
            setMatrix3D(el, f(asi, 'M3D', 'Matrix3D'));
            key.elements.push(el);
          }
        }
        layer.frames.push(key);
      }
      // Fill gaps so keyframes cover the layer from frame 0.
      layer.frames.sort((a, b) -> a.start - b.start);
      var fixed:Array<AnimKeyframe> = [];
      var at = 0;
      for (k in layer.frames)
      {
        if (k.start > at) fixed.push({start: at, duration: k.start - at, elements: []});
        fixed.push(k);
        at = k.start + k.duration;
      }
      if (fixed.length == 0) fixed.push({start: 0, duration: 1, elements: []});
      layer.frames = fixed;
      sym.layers.push(layer);
    }
    if (sym.layers.length == 0) sym.layers.push(AnimData.newLayer('Layer 1', 'vector', 0));
    return sym;
  }

  static function setMatrix3D(el:AnimElement, m:Dynamic):Void
  {
    if (m == null) return;
    if (Std.isOfType(m, Array))
    {
      var a:Array<Float> = m;
      el.a = a[0];
      el.b = a[1];
      el.c = a[4];
      el.d = a[5];
      el.tx = a[12];
      el.ty = a[13];
    }
    else
    {
      el.a = m.m00 ?? 1;
      el.b = m.m01 ?? 0;
      el.c = m.m10 ?? 0;
      el.d = m.m11 ?? 1;
      el.tx = m.m30 ?? 0;
      el.ty = m.m31 ?? 0;
    }
  }

  static function hexColor(s:Dynamic):Int
  {
    if (s == null) return 0xFFFFFFFF;
    var str = Std.string(s);
    if (StringTools.startsWith(str, '#')) str = str.substr(1);
    return 0xFF000000 | (Std.parseInt('0x$str') ?? 0xFFFFFF);
  }

  static function applyColor(el:AnimElement, c:Dynamic):Void
  {
    if (c == null) return;
    var mode:String = f(c, 'M', 'mode') ?? '';
    switch (mode)
    {
      case 'CA' | 'Alpha':
        el.alpha = f(c, 'AM', 'alphaMultiplier') ?? 1;
      case 'T' | 'Tint':
        el.tint = hexColor(f(c, 'TC', 'tintColor'));
        el.tintAmount = f(c, 'TM', 'tintMultiplier') ?? 0;
      case 'CBRT' | 'Brightness':
        el.brightness = f(c, 'BRT', 'brightness') ?? 0;
      case 'AD' | 'Advanced':
        el.alpha = f(c, 'AM', 'alphaMultiplier') ?? 1;
      default:
    }
  }

  static function applyFilters(el:AnimElement, filters:Dynamic):Void
  {
    if (filters == null) return;
    var out:Array<AnimFilter> = [];
    var blur = f(filters, 'BLF', 'BlurFilter');
    if (blur != null) out.push({type: 'blur', blurX: f(blur, 'BLX', 'blurX') ?? 4, blurY: f(blur, 'BLY', 'blurY') ?? 4, quality: f(blur, 'Q', 'quality') ?? 1});
    var glow = f(filters, 'GF', 'GlowFilter');
    if (glow != null) out.push({
      type: 'glow',
      blurX: f(glow, 'BLX', 'blurX') ?? 4,
      blurY: f(glow, 'BLY', 'blurY') ?? 4,
      color: hexColor(f(glow, 'C', 'color')),
      alpha: f(glow, 'A', 'alpha') ?? 1,
      strength: f(glow, 'STR', 'strength') ?? 1,
      inner: f(glow, 'IN', 'inner') == true,
      knockout: f(glow, 'KK', 'knockout') == true
    });
    var shadow = f(filters, 'DSF', 'DropShadowFilter');
    if (shadow != null) out.push({
      type: 'shadow',
      blurX: f(shadow, 'BLX', 'blurX') ?? 4,
      blurY: f(shadow, 'BLY', 'blurY') ?? 4,
      color: hexColor(f(shadow, 'C', 'color')),
      alpha: f(shadow, 'A', 'alpha') ?? 1,
      strength: f(shadow, 'STR', 'strength') ?? 1,
      distance: f(shadow, 'D', 'distance') ?? 4,
      angle: f(shadow, 'AL', 'angle') ?? 45,
      inner: f(shadow, 'IN', 'inner') == true,
      knockout: f(shadow, 'KK', 'knockout') == true
    });
    var adjust = f(filters, 'ACF', 'AdjustColorFilter');
    if (adjust != null) out.push({
      type: 'adjust',
      brightness: f(adjust, 'BRT', 'brightness') ?? 0,
      contrast: f(adjust, 'CT', 'contrast') ?? 0,
      saturation: f(adjust, 'SAT', 'saturation') ?? 0,
      hue: f(adjust, 'H', 'hue') ?? 0
    });
    if (out.length > 0) el.filters = out;
  }

  //
  // Other formats
  //

  public static function importFla(ed:AnimatorState):Void
  {
    QOLFilePicker.open('Adobe Animate file (.fla, or DOMDocument.xml from an .xfl folder)', ['fla', 'xfl', 'xml'], true, files -> {
      try
      {
        var doc = XFLFile.read(files);
        ed.setDocument(doc);
        ed.notify('Imported', '${doc.project.name}: ${doc.project.symbols.length - 1} symbols.');
      }
      catch (e)
      {
        ed.alert('Could not import', Std.string(e));
      }
    });
  }

  public static function importPsd(ed:AnimatorState):Void
  {
    QOLFilePicker.open('Photoshop file (.psd)', ['psd'], false, files -> {
      try
      {
        var doc = PSDFile.read(files[0].bytes, haxe.io.Path.withoutExtension(files[0].name), ed.doc.project.fps);
        ed.setDocument(doc);
        ed.notify('Imported', '${files[0].name}: ${AnimData.symbolLength(doc.main)} frame(s), ${doc.main.layers.length} layer(s).');
      }
      catch (e)
      {
        ed.alert('Could not import', Std.string(e));
      }
    });
  }

  public static function importVideo(ed:AnimatorState):Void
  {
    AnimVideo.importVideo(ed);
  }
}
#end
