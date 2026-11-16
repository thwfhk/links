import { HighlightStyle, StreamLanguage, syntaxHighlighting } from "@codemirror/language";
import { EditorState } from "@codemirror/state";
import { EditorView, lineNumbers } from "@codemirror/view";
import { tags } from "@lezer/highlight";
import { minimalSetup } from "codemirror";

const keywords = new Set([
  "as", "case", "do", "effect", "else", "escape", "for", "forall",
  "fun", "handle", "if", "import", "in", "infix", "infixl", "infixr",
  "linfun", "module", "mu", "mutual", "op", "open", "orderby", "postfix",
  "prefix", "shallowhandle", "sig", "switch", "typename", "unsafe", "var",
  "where", "with",
]);

function readString(stream, state) {
  while (!stream.eol()) {
    const char = stream.next();
    if (char === "\\") {
      stream.next();
    } else if (char === '"') {
      state.inString = false;
      break;
    }
  }
  return "string";
}

// The token forms follow core/lexer.mll. Angle delimiters share the operator
// style because the lexer also uses these tokens in comparisons and expressions.
const smallLinks = StreamLanguage.define({
  name: "SmallLinks",
  languageData: { commentTokens: { line: "#" } },
  startState: () => ({ inString: false }),
  token(stream, state) {
    if (state.inString) return readString(stream, state);
    if (stream.eatSpace()) return null;
    if (stream.eat("#")) {
      stream.skipToEnd();
      return "lineComment";
    }
    if (stream.eat('"')) {
      state.inString = true;
      return readString(stream, state);
    }
    if (stream.match(/^'(?:[^"\\]|\\(?:["\\nrtb]|[0-3][0-7]{2}|[xX][0-9a-fA-F]{2}))'/)) {
      return "character";
    }
    if (stream.match(/^(?:0|[1-9][0-9]*)(?:\.[0-9]+(?:e-?(?:0|[1-9][0-9]*))?)?/)) {
      return "number";
    }
    if (stream.match(/^~(?:fun|linfun)/)) return "keyword";
    if (stream.match(/^[\x07@$][a-zA-Z][a-zA-Z_0-9']*/)) return "meta";
    if (stream.match(/^%[a-zA-Z][a-zA-Z_0-9']*/)) return "name";
    const name = stream.match(/^[a-zA-Z][a-zA-Z_0-9']*/);
    if (name) {
      const word = name[0];
      if (keywords.has(word)) return "keyword";
      if (word === "true" || word === "false") return "bool";
      if (/^[A-Z]/.test(word)) return "name";
      return null;
    }
    if (stream.match(/^(?:\|\)|[()[\]{}])/)) return "bracket";
    if (stream.match(/^(?:<-t-|<-v-|=~|::|`[a-z][a-zA-Z_0-9']*`|[!$&*+/<=>@\\^|-][.!$&*+/<=>@\\^|-]*)/)) {
      return "operator";
    }
    if (stream.match(/^[.,:;?~%]/)) return "punctuation";
    stream.next();
    return null;
  },
});

const highlights = syntaxHighlighting(HighlightStyle.define([
  { tag: tags.keyword, color: "#81244c", fontWeight: "600" },
  { tag: tags.name, color: "#19596e" },
  { tag: [tags.string, tags.character], color: "#31623e" },
  { tag: [tags.number, tags.bool], color: "#824019" },
  { tag: [tags.operator, tags.bracket, tags.meta], color: "#54477b" },
  { tag: tags.comment, color: "#5d635e" },
]));

const theme = EditorView.theme({
  "&": { height: "var(--source-height, clamp(18rem, 57vh, 39rem))", minWidth: "0" },
  "&.cm-focused": { outline: "2px solid var(--accent, #175c43)", outlineOffset: "-2px" },
  ".cm-scroller": { fontFamily: "var(--code-font, ui-monospace, monospace)", lineHeight: "1.6" },
  ".cm-content": { padding: "0.75rem 0" },
  ".cm-line": { padding: "0 0.875rem" },
  ".cm-gutters": {
    backgroundColor: "transparent",
    borderColor: "var(--border, #d5ded9)",
    color: "var(--muted, #485b52)",
  },
  ".cm-lineNumbers .cm-gutterElement": { padding: "0 0.625rem", minWidth: "2.5ch" },
});

export function createEditor(textarea, onChange) {
  const labels = Array.from(textarea.labels);
  const contentAttributes = {
    "aria-label": textarea.getAttribute("aria-label") ||
      labels.map(label => label.textContent.trim()).join(" "),
  };
  for (const attribute of ["aria-labelledby", "aria-describedby"]) {
    const value = textarea.getAttribute(attribute);
    if (value) contentAttributes[attribute] = value;
  }

  const extensions = [
    minimalSetup,
    lineNumbers(),
    EditorState.tabSize.of(2),
    EditorView.lineWrapping,
    smallLinks,
    highlights,
    theme,
    EditorView.contentAttributes.of(contentAttributes),
    EditorView.updateListener.of(update => {
      if (update.docChanged) {
        textarea.value = update.state.doc.toString();
        onChange?.(textarea.value);
      }
    }),
  ];
  const view = new EditorView({ doc: textarea.value, extensions });
  view.setTabFocusMode(true);
  const hadFocus = textarea.matches(":focus");
  textarea.after(view.dom);
  textarea.hidden = true;
  for (const label of labels) {
    label.addEventListener("click", event => {
      event.preventDefault();
      view.focus();
    });
  }
  if (hadFocus) view.focus();

  return {
    getSource() {
      return view.state.doc.toString();
    },
    setSource(text) {
      view.setState(EditorState.create({ doc: text, extensions }));
      view.scrollDOM.scrollTop = 0;
      textarea.value = text;
    },
    focus() {
      view.focus();
    },
  };
}
