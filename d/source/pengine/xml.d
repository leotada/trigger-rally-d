// xml [pengine]
//
// A small XML DOM with an API shaped like the subset of tinyxml2 used by the game.
// Comments and declarations are preserved so the user's config file can be rewritten.
//
// License: GPL version 2 (see included gpl.txt)
module pengine.xml;

import std.array : appender;
import std.conv : to;
import std.format : format;
import std.string : indexOf, startsWith;

enum XMLNodeKind { element, text, comment, declaration, unknown }

final class XMLNode
{
  XMLNodeKind kind;
  string value;         ///< element name, text, or comment/declaration body
  string[] attrNames;
  string[] attrValues;
  XMLNode parent;
  XMLNode[] children;

  this(XMLNodeKind k, string v) { kind = k; value = v; }

  // --- tinyxml2-like read API ---

  string Value() const { return value; }

  /// Returns the attribute value, or null when absent.
  string Attribute(string name) const
  {
    foreach (i, n; attrNames)
      if (n == name) return attrValues[i];
    return null;
  }

  bool hasAttribute(string name) const
  {
    foreach (n; attrNames)
      if (n == name) return true;
    return false;
  }

  XMLNode FirstChildElement(string name = null)
  {
    foreach (c; children)
      if (c.kind == XMLNodeKind.element && (name is null || c.value == name))
        return c;
    return null;
  }

  XMLNode NextSiblingElement(string name = null)
  {
    if (parent is null) return null;
    bool found = false;
    foreach (c; parent.children) {
      if (found) {
        if (c.kind == XMLNodeKind.element && (name is null || c.value == name))
          return c;
      } else if (c is this) {
        found = true;
      }
    }
    return null;
  }

  // --- write API ---

  void SetAttribute(string name, string val)
  {
    foreach (i, n; attrNames)
      if (n == name) {
        attrValues[i] = val;
        return;
      }
    attrNames ~= name;
    attrValues ~= val;
  }

  void SetAttribute(string name, float val)
  {
    SetAttribute(name, format("%.8g", val));
  }

  void SetAttribute(string name, int val)
  {
    SetAttribute(name, to!string(val));
  }
}

alias XMLElement = XMLNode;

final class XMLDocument
{
  XMLNode root; ///< pseudo-node holding the top-level children
  string errorStr;

  this() { root = new XMLNode(XMLNodeKind.element, ""); }

  XMLNode FirstChildElement(string name = null) { return root.FirstChildElement(name); }

  /// Parses the document. Returns false (and sets `errorStr`) on error.
  bool Parse(const(char)[] text)
  {
    root = new XMLNode(XMLNodeKind.element, "");
    errorStr = null;

    size_t i = 0;
    XMLNode cur = root;
    const n = text.length;

    bool fail(string msg)
    {
      errorStr = msg;
      return false;
    }

    while (i < n) {
      if (text[i] == '<') {
        if (text[i .. $].startsWith("<!--")) {
          auto e = indexOf(text[i + 4 .. $], "-->");
          if (e < 0) return fail("unterminated comment");
          auto c = new XMLNode(XMLNodeKind.comment, text[i + 4 .. i + 4 + e].idup);
          c.parent = cur;
          cur.children ~= c;
          i += 4 + e + 3;
        } else if (text[i .. $].startsWith("<?")) {
          auto e = indexOf(text[i + 2 .. $], "?>");
          if (e < 0) return fail("unterminated declaration");
          auto c = new XMLNode(XMLNodeKind.declaration, text[i + 2 .. i + 2 + e].idup);
          c.parent = cur;
          cur.children ~= c;
          i += 2 + e + 2;
        } else if (text[i .. $].startsWith("<![CDATA[")) {
          auto e = indexOf(text[i + 9 .. $], "]]>");
          if (e < 0) return fail("unterminated CDATA");
          auto c = new XMLNode(XMLNodeKind.text, text[i + 9 .. i + 9 + e].idup);
          c.parent = cur;
          cur.children ~= c;
          i += 9 + e + 3;
        } else if (text[i .. $].startsWith("<!")) {
          auto e = indexOf(text[i .. $], ">");
          if (e < 0) return fail("unterminated unknown node");
          auto c = new XMLNode(XMLNodeKind.unknown, text[i + 2 .. i + e].idup);
          c.parent = cur;
          cur.children ~= c;
          i += e + 1;
        } else if (i + 1 < n && text[i + 1] == '/') {
          auto e = indexOf(text[i .. $], ">");
          if (e < 0) return fail("unterminated closing tag");
          string name = strip(text[i + 2 .. i + e]).idup;
          if (cur is root || cur.value != name) return fail("mismatched closing tag: " ~ name);
          cur = cur.parent;
          i += e + 1;
        } else {
          // element start
          size_t j = i + 1;
          while (j < n && !isSpace(text[j]) && text[j] != '>' && text[j] != '/') j++;
          string name = text[i + 1 .. j].idup;
          if (name.length == 0) return fail("malformed element");
          auto el = new XMLNode(XMLNodeKind.element, name);
          el.parent = cur;
          cur.children ~= el;

          bool selfClose = false;
          while (true) {
            while (j < n && isSpace(text[j])) j++;
            if (j >= n) return fail("unterminated element start tag");
            if (text[j] == '>') {
              j++;
              break;
            }
            if (text[j] == '/') {
              if (j + 1 < n && text[j + 1] == '>') {
                selfClose = true;
                j += 2;
                break;
              }
              return fail("malformed element");
            }
            // attribute
            size_t k = j;
            while (k < n && !isSpace(text[k]) && text[k] != '=' && text[k] != '>' && text[k] != '/') k++;
            string an = text[j .. k].idup;
            while (k < n && isSpace(text[k])) k++;
            if (k >= n || text[k] != '=') return fail("attribute without value: " ~ an);
            k++;
            while (k < n && isSpace(text[k])) k++;
            if (k >= n || (text[k] != '"' && text[k] != '\'')) return fail("attribute value not quoted: " ~ an);
            const q = text[k];
            k++;
            size_t vs = k;
            while (k < n && text[k] != q) k++;
            if (k >= n) return fail("unterminated attribute value");
            el.attrNames ~= an;
            el.attrValues ~= decodeEntities(text[vs .. k]);
            j = k + 1;
          }
          i = j;
          if (!selfClose) cur = el;
        }
      } else {
        size_t j = i;
        while (j < n && text[j] != '<') j++;
        auto raw = text[i .. j];
        bool allSpace = true;
        foreach (ch; raw)
          if (!isSpace(ch)) {
            allSpace = false;
            break;
          }
        if (!allSpace && cur !is root) {
          auto c = new XMLNode(XMLNodeKind.text, decodeEntities(raw));
          c.parent = cur;
          cur.children ~= c;
        }
        i = j;
      }
    }

    if (cur !is root) return fail("unclosed element: " ~ cur.value);
    return true;
  }

  string ErrorStr() const { return errorStr; }

  /// Serializes the document in a tinyxml2-like format.
  string Print() const
  {
    auto outp = appender!string();
    foreach (c; root.children)
      printNode(outp, c, 0);
    return outp.data;
  }
}

private bool isSpace(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }

private string strip(const(char)[] s)
{
  size_t a = 0, b = s.length;
  while (a < b && isSpace(s[a])) a++;
  while (b > a && isSpace(s[b - 1])) b--;
  return s[a .. b].idup;
}

private string decodeEntities(const(char)[] s)
{
  if (s.indexOf('&') < 0) return s.idup;
  auto outp = appender!string();
  size_t i = 0;
  while (i < s.length) {
    if (s[i] == '&') {
      auto e = indexOf(s[i .. $], ';');
      if (e > 1) {
        auto ent = s[i + 1 .. i + e];
        string repl;
        switch (ent) {
          case "amp": repl = "&"; break;
          case "lt": repl = "<"; break;
          case "gt": repl = ">"; break;
          case "quot": repl = "\""; break;
          case "apos": repl = "'"; break;
          default:
            if (ent.length > 1 && ent[0] == '#') {
              try {
                uint cp = (ent[1] == 'x' || ent[1] == 'X') ? to!uint(ent[2 .. $], 16) : to!uint(ent[1 .. $]);
                import std.utf : encode;
                char[4] buf;
                auto len = encode(buf, cast(dchar) cp);
                repl = buf[0 .. len].idup;
              } catch (Exception) {
              }
            }
            break;
        }
        if (repl.length) {
          outp ~= repl;
          i += e + 1;
          continue;
        }
      }
    }
    outp ~= s[i];
    i++;
  }
  return outp.data;
}

private string encodeEntities(string s, bool attr)
{
  auto outp = appender!string();
  foreach (c; s) {
    switch (c) {
      case '&': outp ~= "&amp;"; break;
      case '<': outp ~= "&lt;"; break;
      case '>': outp ~= "&gt;"; break;
      case '"':
        if (attr) outp ~= "&quot;"; else outp ~= c;
        break;
      default: outp ~= c; break;
    }
  }
  return outp.data;
}

private void printNode(Out)(ref Out outp, const(XMLNode) n, int depth)
{
  void indent()
  {
    foreach (_; 0 .. depth) outp ~= "    ";
  }

  final switch (n.kind) {
    case XMLNodeKind.declaration:
      indent();
      outp ~= "<?" ~ n.value ~ "?>\n";
      break;
    case XMLNodeKind.comment:
      indent();
      outp ~= "<!--" ~ n.value ~ "-->\n";
      break;
    case XMLNodeKind.unknown:
      indent();
      outp ~= "<!" ~ n.value ~ ">\n";
      break;
    case XMLNodeKind.text:
      indent();
      outp ~= encodeEntities(n.value, false) ~ "\n";
      break;
    case XMLNodeKind.element:
      indent();
      outp ~= "<" ~ n.value;
      foreach (i, an; n.attrNames)
        outp ~= " " ~ an ~ "=\"" ~ encodeEntities(n.attrValues[i], true) ~ "\"";
      if (n.children.length == 0) {
        outp ~= "/>\n";
      } else {
        outp ~= ">\n";
        foreach (c; n.children)
          printNode(outp, c, depth + 1);
        indent();
        outp ~= "</" ~ n.value ~ ">\n";
      }
      break;
  }
}
