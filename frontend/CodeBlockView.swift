import SwiftUI

// 🔹 مُلوّن بسيط يدعم عدّة لغات شائعة
struct SimpleSyntaxHighlighter {
    struct Style {
        var keyword: Color = .blue
        var string: Color  = .green
        var number: Color  = .orange
        var comment: Color = .gray
        var tag: Color     = .purple        // للـ HTML/CSS
        var attr: Color    = .teal          // للخواص/السمات
        var boolNil: Color = .pink          // true/false/null
        var plain: Color   = .white
        var fontSize: CGFloat = 14
    }
    var style = Style()
    
    // كلمات كل لغة (قابلة للتوسعة)
    private let swiftKeywords: [String] = [
        "import","func","let","var","if","else","guard","return","for","in","while",
        "class","struct","enum","protocol","extension","switch","case","default",
        "public","private","internal","fileprivate","open","where","do","try","catch",
        "throws","rethrows","defer","init","self","super","static","final","override"
    ]
    private let jsKeywords: [String] = [
        "import","from","export","function","const","let","var","if","else","return","for",
        "while","switch","case","default","break","continue","class","extends","new","try",
        "catch","finally","throw","async","await","this","super","typeof","instanceof"
    ]
    private let pyKeywords: [String] = [
        "import","from","def","class","return","if","elif","else","for","while","try",
        "except","finally","raise","with","as","pass","break","continue","lambda","yield",
        "global","nonlocal","assert","True","False","None","and","or","not","in","is"
    ]
    private let bashKeywords: [String] = [
        "if","then","elif","else","fi","for","in","do","done","case","esac","function",
        "while","until","select","time","coproc","return","exit","break","continue"
    ]
    private let sqlKeywords: [String] = [
        "select","from","where","group","by","having","order","limit","offset","join",
        "left","right","inner","outer","on","insert","into","values","update","set",
        "delete","create","table","drop","alter","view","index","and","or","not","null"
    ]
    
    /// يلوّن `code` بحسب `lang`. إن كانت `lang == nil` يطبّق تلوينًا عامًا بسيطًا.
    func highlight(_ code: String, lang: String?) -> AttributedString {
        var out = AttributedString(code)
        out.foregroundColor = style.plain
        out.font = .system(size: style.fontSize, design: .monospaced)
        
        let l = (lang ?? "").lowercased()
        
        // تلوين عام مشترك: سلاسل/تعليقات/أرقام (إن توفّر)
        // سلاسل "..."
        applyRegex(#"\"([^"\\]|\\.)*\""#, color: style.string, to: &out, in: code)
        // سلاسل مفردة '...' لبعض اللغات
        applyRegex(#"'([^'\\]|\\.)*'"#, color: style.string, to: &out, in: code)
        // أرقام
        applyRegex(#"\b\d+(\.\d+)?\b"#, color: style.number, to: &out, in: code)
        
        switch l {
        case "swift":
            // تعليقات Swift
            applyRegex(#"//[^\n]*"#, color: style.comment, to: &out, in: code)
            applyRegex(#"/\*[\s\S]*?\*/"#, color: style.comment, to: &out, in: code)
            // كلمات مفتاحية
            keywords(swiftKeywords, to: &out, in: code)
            
        case "javascript","typescript","js","ts":
            // تعليقات JS/TS
            applyRegex(#"//[^\n]*"#, color: style.comment, to: &out, in: code)
            applyRegex(#"/\*[\s\S]*?\*/"#, color: style.comment, to: &out, in: code)
            // كلمات مفتاحية
            keywords(jsKeywords, to: &out, in: code)
            
        case "python","py":
            // تعليقات بايثون
            applyRegex(#"#.*$"#, options: [.anchorsMatchLines], color: style.comment, to: &out, in: code)
            // سلاسل ثلاثية
            applyRegex(#"\"\"\"[\s\S]*?\"\"\""#, color: style.string, to: &out, in: code)
            applyRegex(#"'''[\s\S]*?''':"#, color: style.string, to: &out, in: code) // نغطي الحالة
            // كلمات مفتاحية
            keywords(pyKeywords, to: &out, in: code)
            
        case "bash","sh","zsh","shell":
            // تعليقات شِل
            applyRegex(#"#[^\n]*"#, color: style.comment, to: &out, in: code)
            keywords(bashKeywords, to: &out, in: code)
            
        case "css","scss","less":
            // تعليقات CSS
            applyRegex(#"/\*[\s\S]*?\*/"#, color: style.comment, to: &out, in: code)
            // الوسوم/المحددات (بسيط)
            applyRegex(#"[a-zA-Z\-]+(?=\s*:)"#, color: style.attr, weight: .semibold, to: &out, in: code) // الخصائص
            applyRegex(#"(?<=\.)[A-Za-z_][\w\-]*"#, color: style.tag, to: &out, in: code) // class
            applyRegex(#"(?<=#)[A-Za-z_][\w\-]*"#, color: style.tag, to: &out, in: code) // id
            
        case "html","htm":
            // تعليقات HTML
            applyRegex(#"<!--[\s\S]*?-->"#, color: style.comment, to: &out, in: code)
            // الوسوم والسمات
            applyRegex(#"</?[A-Za-z][A-Za-z0-9\-]*"#, color: style.tag, weight: .semibold, to: &out, in: code)
            applyRegex(#"\s+[A-Za-z_:][-A-Za-z0-9_:.]*(?=\=)"#, color: style.attr, to: &out, in: code)
            // قيم السمات داخل ""
            applyRegex(#"=\"([^\"\\]|\\.)*\""#, color: style.string, to: &out, in: code)
            
        case "json":
            // true/false/null
            applyRegex(#"\b(true|false|null)\b"#, color: style.boolNil, weight: .semibold, to: &out, in: code)
            // المفاتيح "key":
            applyRegex(#"\"([^\"\\]|\\.)*\"(?=\s*:)"#, color: style.tag, to: &out, in: code)
            
        case "sql":
            applyRegex(#"--[^\n]*"#, color: style.comment, to: &out, in: code)
            applyRegex(#"/\*[\s\S]*?\*/"#, color: style.comment, to: &out, in: code)
            keywords(sqlKeywords, to: &out, in: code)
            
        default:
            // لغة غير معرّفة: نكتفي بالتلوين العام (سلاسل/أرقام) وتعليقات عامة
            applyRegex(#"//[^\n]*"#, color: style.comment, to: &out, in: code) // لغات C-like
            applyRegex(#"#.*$"#, options: [.anchorsMatchLines], color: style.comment, to: &out, in: code) // بايثون/شِل
            applyRegex(#"/\*[\s\S]*?\*/"#, color: style.comment, to: &out, in: code)
        }
        
        return out
    }
    
    // MARK: - أدوات مساعدة
    
    private func keywords(_ list: [String], to attr: inout AttributedString, in raw: String) {
        let kw = list.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        applyRegex(#"\b(\#(kw))\b"#, color: style.keyword, weight: .semibold, to: &attr, in: raw)
    }
    
    private func applyRegex(_ pattern: String,
                            options: NSRegularExpression.Options = [],
                            color: Color,
                            weight: Font.Weight? = nil,
                            to attr: inout AttributedString,
                            in raw: String) {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let ns = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        re.enumerateMatches(in: raw, options: [], range: ns) { match, _, _ in
            guard let m = match, let r = Range(m.range, in: raw) else { return }
            // ملاحظة: نستخدم بحثًا نصيًا بسيطًا لربط المدى.
            if let ar = attr.range(of: String(raw[r])) {
                attr[ar].foregroundColor = color
                if let w = weight {
                    attr[ar].font = .system(
                        size: (attr[ar].font?.pointSize ?? style.fontSize),
                        weight: w,
                        design: .monospaced
                    )
                }
            }
        }
    }
}

// 🔹 صندوق الكود يستخدم الملوّن أعلاه
struct CodeBlockView: View {
    let code: String
    let language: String?
    private let highlighter = SimpleSyntaxHighlighter()
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CopyButton(textToCopy: code)
                Spacer()
                Text(language ?? "code")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.black))
            
            ScrollView(.horizontal) {
                ScrollView {
                    Text(highlighter.highlight(code, lang: language))
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground).opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.08))
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .environment(\.layoutDirection, .leftToRight) // الكود LTR
    }
}
