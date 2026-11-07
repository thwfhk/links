(* Keep effect requirements separate from Lib's optimiser purity flags.
   For example, take is PURE with a wild requirement; random is IMPURE
   without one. These signatures preserve the source types in Lib.env. *)
let signatures =
  let named names signature = List.map (fun name -> name, signature) names in
  let empty names arrow = named names ("modal [] (" ^ arrow ^ ")") in
  let wild names arrow = named names ("modal [Wild] (" ^ arrow ^ ")") in
  let poly names arrow = named names ("forall a. modal [] (" ^ arrow ^ ")") in
  let poly_wild names arrow = named names ("forall a. modal [Wild] (" ^ arrow ^ ")") in
  let xml_forest = "XmlVariant" and xml_item = "XmlItemVariant" in
  let regex = "Regex" in
  List.concat [
    empty ["+"; "-"; "*"; "/"; "^"; "mod"] "(Int, Int) -> Int";
    empty ["+."; "-."; "*."; "/."; "^."] "(Float, Float) -> Float";
    empty ["^^"] "(String, String) -> String";
    named ["max_int"; "min_int"] "Int";
    named ["infinity"; "neg_infinity"] "Float";
    named ["javascript"] "Bool";
    poly ["=="; "<>"; "<"; ">"; "<="; ">="] "(a, a) -> Bool";
    empty ["not"] "(Bool) -> Bool";
    empty ["negate"] "(Int) -> Int";
    empty ["negatef"; "floor"; "ceiling"; "cos"; "sin"; "tan"; "log"; "log10"; "exp"; "sqrt"] "(Float) -> Float";
    empty ["intToString"] "(Int) -> String";
    empty ["stringToInt"] "(String) -> Int";
    empty ["intToFloat"] "(Int) -> Float";
    empty ["floatToInt"] "(Float) -> Int";
    empty ["floatToString"] "(Float) -> String";
    empty ["stringToFloat"] "(String) -> Float";
    empty ["stringToXml"; "parseXml"] "(String) -> Xml";
    empty ["intToXml"] "(Int) -> Xml";
    empty ["floatToXml"] "(Float) -> Xml";
    empty ["ord"] "(Char) -> Int";
    empty ["chr"] "(Int) -> Char";
    named ["sysexit"] "forall a. modal [Wild] ((Int) -> a)";
    poly_wild ["show"; "objectType"] "(a) -> String";
    named ["exit"; "unsafe_cast"] "forall a, b. modal [Wild] ((a) -> b)";
    named ["error"] "forall a. modal [Wild] ((String) -> a)";
    wild ["debug"; "print"] "(String) -> ()";
    poly_wild ["debugObj"; "dump"; "jsSave"; "jsRestore"] "(a) -> ()";
    named ["Nil"] "forall a. List a";
    poly ["Cons"] "(a, List a) -> List a";
    poly ["Concat"] "(List a, List a) -> List a";
    poly ["length"] "(List a) -> Int";
    poly_wild ["hd"] "(List a) -> a";
    poly_wild ["tl"] "(List a) -> List a";
    empty ["Sum"] "(List Int) -> Int";
    poly_wild ["take"; "drop"] "(Int, List a) -> List a";
    poly_wild ["max"; "min"] "(List a) -> [|Just:a | Nothing:()|]";
    wild ["charAt"] "(String, Int) -> Char";
    wild ["strsub"] "(String, Int, Int) -> String";
    wild ["strlen"] "(String) -> Int";
    wild ["strescape"; "strunescape"] "(String) -> String";
    wild ["strContains"] "(String, Char) -> Bool";
    wild ["implode"] "(List Char) -> String";
    wild ["explode"] "(String) -> List Char";
    empty ["tilde"] ("(String, " ^ regex ^ ") -> Bool");
    wild ["ltilde"] ("(String, " ^ regex ^ ") -> List String");
    wild ["stilde"] ("(String, " ^ regex ^ ") -> String");
    empty ["addAttributes"] "(Xml, List (String, String)) -> Xml";
    empty ["itemChildNodes"] "(XmlItem) -> Xml";
    empty ["attribute"] "(Xml, String) -> [|Just:String | Nothing:()|]";
    empty ["makeXml"] "(String, List (String, String), Xml) -> XmlItem";
    wild ["xmlToVariant"] ("(Xml) -> (" ^ xml_forest ^ ")");
    wild ["xmlItemToVariant"] ("(XmlItem) -> (" ^ xml_item ^ ")");
    wild ["variantToXml"] ("((" ^ xml_forest ^ ")) -> Xml");
    wild ["variantToXmlItem"] ("((" ^ xml_item ^ ")) -> XmlItem");
    wild ["getTagName"; "getNamespace"] "(Xml) -> String";
    wild ["itemTextContent"] "(XmlItem) -> String";
    wild ["getAttributes"] "(Xml) -> List (String, String)";
    wild ["hasAttribute"] "(Xml, String) -> Bool";
    wild ["getAttribute"] "(Xml, String) -> String";
    wild ["textContent"; "domGetNodeValueFromRef"; "domGetTagNameFromRef"] "(DomNode) -> String";
    wild ["isElementNode"; "isNull"] "(DomNode) -> Bool";
    wild ["insertBefore"; "appendChildren"; "replaceNode"; "domReplaceChildren"] "(Xml, DomNode) -> ()";
    wild ["replaceDocument"] "(Xml) -> ()";
    wild ["domInsertBeforeRef"; "domAppendChildRef"; "swapNodes"] "(DomNode, DomNode) -> ()";
    wild ["removeNode"] "(DomNode) -> ()";
    wild ["cloneNode"] "(DomNode, Bool) -> DomNode";
    wild ["getDocumentNode"] "() -> DomNode";
    wild ["getNodeById"] "(String) -> DomNode";
    wild ["getValue"] "(DomNode) -> Xml";
    wild ["domGetPropertyFromRef"; "domGetAttributeFromRef"; "domGetStyleAttrFromRef"] "(DomNode, String) -> String";
    wild ["domSetPropertyFromRef"; "domSetAttributeFromRef"; "domSetStyleAttrFromRef"] "(DomNode, String, String) -> ()";
    wild ["domHasAttribute"] "(DomNode, String) -> Bool";
    wild ["domRemoveAttributeFromRef"] "(DomNode, String) -> ()";
    wild ["domGetChildrenFromRef"] "(DomNode) -> List DomNode";
    wild ["parentNode"; "firstChild"; "nextSibling"] "(DomNode) -> DomNode";
    wild ["getTarget"; "getTargetElement"; "getFromElement"; "getToElement"] "(Event) -> DomNode";
    wild ["getTargetValue"] "(Event) -> String";
    wild ["getPageX"; "getPageY"; "getTime"; "getCharCode"] "(Event) -> Int";
    wild ["getInputValue"] "(String) -> String";
    wild ["getRadioGroupValue"] "(List String) -> String";
    named ["event"] "Event";
    wild ["domSetAnchor"; "redirect"] "(String) -> ()";
    wild ["domGetAnchor"] "() -> String";
    wild ["setCookie"] "(String, String) -> ()";
    wild ["getCookie"] "(String) -> String";
    wild ["sleep"] "(Int) -> ()";
    wild ["clientTime"; "clientTimeMilliseconds"; "serverTime"; "serverTimeMilliseconds"; "utcOffset"] "() -> Int";
    wild ["dateToInt"] "(DateTime) -> Int";
    wild ["intToDate"] "(Int) -> DateTime";
    empty ["dateYear"; "dateDay"; "dateMonth"; "dateHours"] "(DateTime, Int) -> Int";
    empty ["dateMinutes"; "dateSeconds"; "dateMilliseconds"] "(DateTime) -> Int";
    wild ["parseDate"] "(String) -> DateTime";
    empty ["now"] "() -> DateTime";
    wild ["showUTC"] "(DateTime) -> String";
    named ["forever"; "beginningOfTime"] "DateTime";
    wild ["environment"] "() -> List (String, String)";
    empty ["random"] "() -> Float";
    empty ["gensym"] "() -> Int";
    poly_wild ["jsSaveGlobalObject"] "(String, a) -> ()";
    named ["jsLoadGlobalObject"] "forall a. modal [Wild] ((String) -> a)";
    named ["jsGetContext2D"] "forall a. modal [Wild] ((DomNode) -> a)";
    poly_wild ["jsFillText"] "(a, String, Float, Float) -> ()";
    poly_wild ["jsCanvasFont"; "jsSetFillColor"] "(a, String) -> ()";
    poly_wild ["jsDrawImage"] "(a, DomNode, Float, Float) -> ()";
    poly_wild ["jsFillRect"; "jsClearRect"] "(a, Float, Float, Float, Float) -> ()";
    poly_wild ["jsFillCircle"] "(a, Float, Float, Float) -> ()";
    poly_wild ["jsBeginPath"; "jsClosePath"; "jsFill"; "jsStroke"] "(a) -> ()";
    poly_wild ["jsArc"] "(a, Float, Float, Float, Float, Float, Bool) -> ()";
    poly_wild ["jsMoveTo"; "jsLineTo"; "jsScale"; "jsTranslate"] "(a, Float, Float) -> ()";
    poly_wild ["jsLineWidth"] "(a, Float) -> ()";
    poly_wild ["jsStrokeStyle"] "(a, a) -> ()";
    poly_wild ["jsCanvasWidth"; "jsCanvasHeight"] "(a) -> Float";
    wild ["jsSaveCanvas"] "(DomNode, DomNode, String) -> ()";
    wild ["connectSocket"] "(String, Int) -> [|Nothing:() | Just:Socket|]";
    wild ["writeToSocket"] "(String, Socket) -> ()";
    wild ["readFromSocket"] "(Socket) -> [|Nothing:() | Just:String|]";
    wild ["closeSocket"] "(Socket) -> ()";
    wild ["addStaticRoute"] "(String, String, List (String, String)) -> ()";
    wild ["servePages"; "serveWebsockets"] "() -> ()";
    wild ["crypt"] "(String) -> String";
    wild ["verify"] "(String, String) -> Bool";
    wild ["getArgs"] "() -> List String";
  ]

let internal_signatures = [
  "$$hd", "forall a. (List a) -> a";
  "$$tl", "forall a. (List a) -> List a";
]

let deferred = [
  "actors", ["Send"; "self"; "here"; "there"; "haveMail"; "recv"; "spawn";
    "spawnAt"; "spawnClient"; "spawnAngel"; "spawnAngelAt"; "spawnWait"; "spawnWait'"];
  "sessions", ["send"; "receive"; "link"; "new"; "newAP"; "newClientAP";
    "newServerAP"; "accept"; "request"; "cancel"; "close"];
  "callbacks", ["registerEventHandlers"; "unsafePickleCont"; "jsSetInterval";
    "jsRequestAnimationFrame"; "jsSetOnKeyDown"; "jsSetOnEvent";
    "jsSetWindowEvent"; "jsSetOnLoad"; "unsafeAddRoute"];
  "database and query support", ["least"; "greatest"; "withValidity"; "ttData";
    "ttFrom"; "ttTo"; "vtData"; "vtFrom"; "vtTo"; "AsList"; "AsListT";
    "AsListV"; "Distinct"; "getDatabaseConfig"; "lensQueryTimeMilliseconds";
    "lensQueryCount"; "lensQueryStatisticsReset"; "sparql"];
]

let read elaboration (name, signature) =
  let _, annotation = FrescoElaborate.read elaboration signature in
  name, (Env.String.find name Lib.nenv, annotation.FrescoElaborate.typ)

(* Checked recursive declarations retain their binder identities when their
   snapshots pass through contextual inference and the IR checker. Publish
   the aliases so printed primitive types can be used in source annotations. *)
let initialise elaboration =
  FrescoElaborate.declarations elaboration {|
    typename Repeat = [|Star | Plus | Question|];
    typename XmlVariant = List [|Text:String | Attr:(String, String)
      | Node:(String, XmlVariant) | NsAttr:(String, String, String)
      | NsNode:(String, String, XmlVariant)|];
    typename XmlItemVariant = [|Text:String | Attr:(String, String)
      | Node:(String, List XmlItemVariant) | NsAttr:(String, String, String)
      | NsNode:(String, String, List XmlItemVariant)|];
    typename Regex = [|Range:(Char, Char) | Simply:String | Quote:Regex
      | Any | StartAnchor | EndAnchor | Seq:List Regex
      | Alternate:(Regex, Regex) | Group:Regex
      | Repeat:(Repeat, Regex) | Replace:(Regex, String)|];
  |}

let bindings elaboration = List.map (read elaboration) signatures
let internal_bindings elaboration = List.map (read elaboration) internal_signatures
let names = List.map fst signatures
