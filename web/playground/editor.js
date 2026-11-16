import { HighlightStyle, StreamLanguage, syntaxHighlighting } from "@codemirror/language";
import { EditorState } from "@codemirror/state";
import { EditorView, lineNumbers } from "@codemirror/view";
import { Tag, tags } from "@lezer/highlight";
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

const modalityTag = Tag.define();
const afterHandleArguments = Symbol();

// The ordinary token forms follow core/lexer.mll.
function readToken(stream, state, group) {
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
  // Like core/parse.ml, split runs of angle brackets at modality boundaries.
  if (group.close === ">" && stream.match(/^(?:\|>|>)/)) {
    return "operator";
  }
  if (group.inType && stream.match(/^(?:<>|<(?!-))/)) return "operator";
  if (stream.match(/^(?:<-t-|<-v-|=~|::|`[a-z][a-zA-Z_0-9']*`|[!$&*+/<=>@\\^|-][.!$&*+/<=>@\\^|-]*)/)) {
    return "operator";
  }
  if (stream.match(/^[.,:;?~%]/)) return "punctuation";
  stream.next();
  return null;
}

function groupFor(close, inType = false, modality = false, kind = null) {
  return { close, inType, typeGroup: inType, modality, kind, beforeGeneratorArrow: kind === "generators" };
}

// Track datatype contexts and their brackets. The same characters can be
// modalities in a datatype, and lists or operators in an expression.
function trackToken(groups, group, token, style) {
  const previous = group.previous;
  group.previous = token;
  const couldApplyType = group.couldApplyType;
  const literal = ["string", "character", "number", "bool"].includes(style);
  group.couldApplyType = literal || style === null && /^[a-z]/.test(token);
  if (literal) return group.modality;

  if (token === group.close || (token === "|)" && group.close === ")") ||
      (token === "|>" && group.close === ">" && group.modality)) {
    groups.pop();
    const outer = groups[groups.length - 1];
    outer.couldApplyType = (!group.typeGroup && !group.kind) || group.kind === "typeArguments";
    if (group.kind === "handle") outer.previous = afterHandleArguments;
    return group.modality;
  }
  if (group.inType && (token === "[" || token === "<")) {
    groups.push(groupFor(token === "[" ? "]" : ">", true, true));
    return true;
  }
  if (group.inType && token === "<>") return true;

  if (token === "(" || token === "{" || token === "[") {
    const close = { "(": ")", "{": "}", "[": "]" }[token];
    let kind = null;
    if (!group.inType && token === "(") {
      if (previous === "for" || previous === afterHandleArguments) kind = "generators";
      if (previous === "handle") kind = "handle";
      if (previous === "if" || previous === "where" || previous === "orderby") kind = "control";
    }
    if (token === "[" && couldApplyType) kind = "typeArguments";
    groups.push(groupFor(close, group.inType || kind === "typeArguments", group.modality, kind));
  } else if (previous === "case" && token === "<") {
    groups.push(groupFor(">", false, false, "operation"));
  } else if (token === ":" || (token === "=" && group.typeAlias)) {
    group.inType = true;
    group.typeAlias = false;
  } else if ((token === "forall" || token === "mu") && group.inType) {
    group.inQuantifier = true;
  } else if (token === "." && group.inQuantifier) {
    group.inQuantifier = false;
  } else if ((token === "," && !group.inQuantifier) || token === ";" ||
             (token === "<-" && group.beforeGeneratorArrow) || (token === "->" && group.casePattern)) {
    group.inType = group.typeGroup;
    group.casePattern = false;
    group.beforeGeneratorArrow = token === "," && group.kind === "generators";
    group.typeAlias = false;
    group.inQuantifier = false;
  } else if (style === "keyword" && token !== "forall" && token !== "mu") {
    group.inType = group.typeGroup;
    group.typeAlias = token === "typename";
    if (token !== "as") group.casePattern = token === "case";
    group.inQuantifier = false;
  }

  return group.modality;
}

const smallLinks = StreamLanguage.define({
  name: "SmallLinks",
  languageData: { commentTokens: { line: "#" } },
  tokenTable: { modality: modalityTag },
  startState: () => ({ inString: false, groups: [groupFor(null)] }),
  copyState: state => ({ ...state, groups: state.groups.map(group => ({ ...group })) }),
  token(stream, state) {
    let group = state.groups[state.groups.length - 1];
    const style = readToken(stream, state, group);
    if (style === "lineComment") return style;
    const token = stream.current();
    // Leave an unfinished modality when the next declaration or expression starts.
    if ((token === ";" && style === "punctuation") ||
        (style === "keyword" && token !== "forall" && token !== "mu")) {
      while (group.modality) {
        state.groups.pop();
        group = state.groups[state.groups.length - 1];
      }
    }
    const modality = /\S/.test(token) ? trackToken(state.groups, group, token, style) : group.modality;
    return modality ? "modality" : style;
  },
});

const highlights = syntaxHighlighting(HighlightStyle.define([
  { tag: modalityTag, class: "cm-smalllinks-modality" },
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
  ".cm-smalllinks-modality": { color: "#173f92" },
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
  const previewExtensions = [
    extensions,
    EditorState.readOnly.of(true),
    EditorView.editable.of(false),
    EditorView.contentAttributes.of({ "aria-readonly": "true", tabindex: "0" }),
  ];
  let draft = null;

  function replaceState(state, scrollTop = 0) {
    view.setState(state);
    view.scrollDOM.scrollTop = scrollTop;
    textarea.value = state.doc.toString();
    textarea.readOnly = state.readOnly;
  }

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
      draft = null;
      replaceState(EditorState.create({ doc: text, extensions }));
    },
    showPreview(text) {
      draft ??= { state: view.state, scrollTop: view.scrollDOM.scrollTop };
      replaceState(EditorState.create({ doc: text, extensions: previewExtensions }));
    },
    restoreDraft() {
      if (!draft) return;
      replaceState(draft.state, draft.scrollTop);
      draft = null;
    },
    editPreview() {
      const { doc, selection } = view.state;
      draft = null;
      replaceState(EditorState.create({ doc, selection, extensions }), view.scrollDOM.scrollTop);
    },
    focus() {
      view.focus();
    },
  };
}
