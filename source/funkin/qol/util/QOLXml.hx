package funkin.qol.util;

import haxe.io.Bytes;

/**
 * A small, fast XML reader for big files (an Adobe Animate document can be tens of megabytes of XML; Haxe's own Xml
 * class is too slow and uses too much memory for that). Reads UTF-8 bytes straight into a tree of nodes.
 */
class QOLXml
{
  /**
   * Parse a document. The result is a root node (named "#document") whose children are the top-level elements.
   */
  public static function parse(b:Bytes):QOLXmlNode
  {
    var p = new QOLXmlParser(b);
    while (!p.step(0x7FFFFFFF)) {}
    return p.root;
  }

  public static function isBlank(b:Bytes, from:Int, to:Int):Bool
  {
    for (i in from...to)
      if (b.get(i) > 32) return false;
    return true;
  }

  public static function indexOf2(b:Bytes, from:Int, c1:Int, c2:Int, len:Int):Int
  {
    var p = from;
    while (p + 1 < len && !(b.get(p) == c1 && b.get(p + 1) == c2))
      p++;
    return p;
  }

  #if js
  static var decoder:Dynamic = null;
  #end

  /**
   * UTF-8 bytes to a string (the browser's decoder is much faster for long strings).
   */
  public static inline function str(b:Bytes, pos:Int, len:Int):String
  {
    #if js
    if (len > 24)
    {
      if (decoder == null) decoder = js.Syntax.code('new TextDecoder("utf-8")');
      return decoder.decode(js.Syntax.code('{0}.subarray({1}, {2})', @:privateAccess b.b, pos, pos + len));
    }
    #end
    return b.getString(pos, len);
  }

  /**
   * Replace character references (&amp; &lt; &#33; &#x21; ...).
   */
  public static function decode(s:String):String
  {
    if (s.indexOf('&') < 0) return s;
    var out = new StringBuf();
    var i = 0;
    var n = s.length;
    while (i < n)
    {
      var c = StringTools.fastCodeAt(s, i);
      if (c != '&'.code)
      {
        out.addChar(c);
        i++;
        continue;
      }
      var semi = s.indexOf(';', i);
      if (semi < 0 || semi - i > 10)
      {
        out.addChar(c);
        i++;
        continue;
      }
      var ent = s.substring(i + 1, semi);
      switch (ent)
      {
        case 'amp': out.add('&');
        case 'lt': out.add('<');
        case 'gt': out.add('>');
        case 'quot': out.add('"');
        case 'apos': out.add("'");
        default:
          if (StringTools.startsWith(ent, '#'))
          {
            var hex = ent.length > 1 && (ent.charAt(1) == 'x' || ent.charAt(1) == 'X');
            var v = hex ? Std.parseInt('0x' + ent.substr(2)) : Std.parseInt(ent.substr(1));
            if (v != null && v > 0 && v <= 0x10FFFF && !(v >= 0xD800 && v <= 0xDFFF)) out.add(String.fromCharCode(v));
            else
              out.add('&' + ent + ';');
          }
          else
            out.add('&' + ent + ';');
      }
      i = semi + 1;
    }
    return out.toString();
  }

  /**
   * Escape text for an attribute value or element text.
   */
  public static function escape(s:String):String
  {
    if (s == null) return '';
    var out = new StringBuf();
    for (i in 0...s.length)
    {
      var c = StringTools.fastCodeAt(s, i);
      switch (c)
      {
        case '&'.code: out.add('&amp;');
        case '<'.code: out.add('&lt;');
        case '>'.code: out.add('&gt;');
        case '"'.code: out.add('&quot;');
        case 10: out.add('&#xA;');
        case 13: out.add('&#xD;');
        default: out.addChar(c);
      }
    }
    return out.toString();
  }
}

class QOLXmlNode
{
  public var name:String;

  /**
   * Attribute names and values, alternating.
   */
  public var attrs:Array<String> = [];

  public var children:Array<QOLXmlNode> = [];
  public var text:Null<String> = null;

  public function new(name:String)
  {
    this.name = name;
  }

  public function get(key:String):Null<String>
  {
    var i = 0;
    while (i < attrs.length)
    {
      if (attrs[i] == key) return attrs[i + 1];
      i += 2;
    }
    return null;
  }

  public inline function has(key:String):Bool
    return get(key) != null;

  public function float(key:String, def:Float = 0):Float
  {
    var v = get(key);
    if (v == null) return def;
    var f = Std.parseFloat(v);
    return Math.isNaN(f) ? def : f;
  }

  public function int(key:String, def:Int = 0):Int
  {
    var v = get(key);
    if (v == null) return def;
    var i = Std.parseInt(v);
    return i == null ? def : i;
  }

  public function bool(key:String, def:Bool = false):Bool
  {
    var v = get(key);
    if (v == null) return def;
    return v == 'true' || v == '1';
  }

  /**
   * The first child element with this name.
   */
  public function child(name:String):Null<QOLXmlNode>
  {
    for (c in children)
      if (c.name == name) return c;
    return null;
  }

  /**
   * Every child element with this name (all children when null).
   */
  public function all(?name:String):Array<QOLXmlNode>
    return name == null ? children : [for (c in children) if (c.name == name) c];

  /**
   * Follow child names down: `node.path('timeline', 'DOMTimeline', 'layers')`.
   */
  public function path(...names:String):Null<QOLXmlNode>
  {
    var n:Null<QOLXmlNode> = this;
    for (name in names)
    {
      if (n == null) return null;
      n = n.child(name);
    }
    return n;
  }

  /**
   * The first element (for a document root).
   */
  public function first():Null<QOLXmlNode>
    return children.length > 0 ? children[0] : null;
}

/**
 * `QOLXml.parse` a piece at a time (so a big document doesn't freeze the screen): call `step` until it returns true,
 * then read `root`.
 */
class QOLXmlParser
{
  public var root(default, null):QOLXmlNode;

  var b:Bytes;
  var len:Int;
  var pos:Int = 0;
  var stack:Array<QOLXmlNode>;

  public function new(b:Bytes)
  {
    this.b = b;
    len = b.length;
    root = new QOLXmlNode('#document');
    stack = [root];
    // Skip a UTF-8 byte order mark.
    if (len >= 3 && b.get(0) == 0xEF && b.get(1) == 0xBB && b.get(2) == 0xBF) pos = 3;
  }

  /**
   * How far through the bytes (0..1).
   */
  public var progress(get, never):Float;

  inline function get_progress():Float
    return len == 0 ? 1 : pos / len;

  /**
   * Read about `bytes` more bytes. True when the whole document is read.
   */
  public function step(bytes:Int):Bool
  {
    var b = this.b, len = this.len, stack = this.stack;
    var stop = pos + bytes;
    if (stop < 0 || stop > len) stop = len;
    var pos = this.pos;
    while (pos < stop)
    {
      var c = b.get(pos);
      if (c != '<'.code)
      {
        // Text up to the next tag.
        var start = pos;
        while (pos < len && b.get(pos) != '<'.code)
          pos++;
        if (!QOLXml.isBlank(b, start, pos))
        {
          var top = stack[stack.length - 1];
          var t = QOLXml.decode(QOLXml.str(b, start, pos - start));
          top.text = top.text == null ? t : top.text + t;
        }
        continue;
      }
      var next = pos + 1 < len ? b.get(pos + 1) : 0;
      if (next == '?'.code)
      {
        pos = QOLXml.indexOf2(b, pos + 2, '?'.code, '>'.code, len) + 2;
        continue;
      }
      if (next == '!'.code)
      {
        if (pos + 3 < len && b.get(pos + 2) == '-'.code && b.get(pos + 3) == '-'.code)
        {
          // Comment.
          var p = pos + 4;
          while (p + 2 < len && !(b.get(p) == '-'.code && b.get(p + 1) == '-'.code && b.get(p + 2) == '>'.code))
            p++;
          pos = p + 3;
          continue;
        }
        if (pos + 8 < len && b.get(pos + 2) == '['.code && b.getString(pos + 2, 7) == '[CDATA[')
        {
          var start = pos + 9;
          var p = start;
          while (p + 2 < len && !(b.get(p) == ']'.code && b.get(p + 1) == ']'.code && b.get(p + 2) == '>'.code))
            p++;
          var top = stack[stack.length - 1];
          var t = QOLXml.str(b, start, p - start);
          top.text = top.text == null ? t : top.text + t;
          pos = p + 3;
          continue;
        }
        // DOCTYPE and the like.
        while (pos < len && b.get(pos) != '>'.code)
          pos++;
        pos++;
        continue;
      }
      if (next == '/'.code)
      {
        // Closing tag.
        while (pos < len && b.get(pos) != '>'.code)
          pos++;
        pos++;
        if (stack.length > 1) stack.pop();
        continue;
      }
      // Opening tag: name, attributes, then '>' or '/>'.
      pos++;
      var nameStart = pos;
      while (pos < len)
      {
        var ch = b.get(pos);
        if (ch <= 32 || ch == '/'.code || ch == '>'.code) break;
        pos++;
      }
      var node = new QOLXmlNode(b.getString(nameStart, pos - nameStart));
      var parent = stack[stack.length - 1];
      parent.children.push(node);
      var selfClosing = false;
      while (pos < len)
      {
        var ch = b.get(pos);
        if (ch <= 32)
        {
          pos++;
          continue;
        }
        if (ch == '>'.code)
        {
          pos++;
          break;
        }
        if (ch == '/'.code)
        {
          selfClosing = true;
          pos++;
          continue;
        }
        // Attribute.
        var an = pos;
        while (pos < len)
        {
          var ac = b.get(pos);
          if (ac == '='.code || ac <= 32 || ac == '>'.code || ac == '/'.code) break;
          pos++;
        }
        var attrName = b.getString(an, pos - an);
        while (pos < len && b.get(pos) <= 32)
          pos++;
        if (pos < len && b.get(pos) == '='.code)
        {
          pos++;
          while (pos < len && b.get(pos) <= 32)
            pos++;
          var quote = b.get(pos);
          if (quote == '"'.code || quote == "'".code)
          {
            pos++;
            var vs = pos;
            var amp = false;
            while (pos < len && b.get(pos) != quote)
            {
              if (b.get(pos) == '&'.code) amp = true;
              pos++;
            }
            var v = QOLXml.str(b, vs, pos - vs);
            node.attrs.push(attrName);
            node.attrs.push(amp ? QOLXml.decode(v) : v);
            pos++;
          }
          else
          {
            var vs = pos;
            while (pos < len && b.get(pos) > 32 && b.get(pos) != '>'.code)
              pos++;
            node.attrs.push(attrName);
            node.attrs.push(QOLXml.str(b, vs, pos - vs));
          }
        }
        else
        {
          node.attrs.push(attrName);
          node.attrs.push('');
        }
      }
      if (!selfClosing) stack.push(node);
        }
    this.pos = pos;
    if (pos >= len)
    {
      this.b = null;
      return true;
    }
    return false;
  }
}
