import SwiftUI
import UIKit

// MARK: - جزء واحد من الرسالة (نص/كود)
enum ChatPart: Equatable {
    case text(String)
    case code(lang: String?, body: String)
}

// MARK: - محلّل أسوار الكود الثلاثية ```lang
struct ChatPartsParser {
    static func parse(_ s: String) -> [ChatPart] {
        var parts: [ChatPart] = []
        var remainder = s[...]
        let fence = "```"
        
        while let fenceStart = remainder.range(of: fence) {
            // نص قبل السور
            if fenceStart.lowerBound > remainder.startIndex {
                parts.append(.text(String(remainder[..<fenceStart.lowerBound])))
            }
            // بعد ```: قد تأتي لغة ثم سطر جديد
            let afterFence = fenceStart.upperBound
            guard let lineBreak = remainder[afterFence...].firstIndex(of: "\n") else {
                // لا يوجد سطر جديد => اعتبر الباقي نصًا
                parts.append(.text(String(remainder[afterFence...])))
                return parts
            }
            let maybeLang = remainder[afterFence..<lineBreak].trimmingCharacters(in: .whitespacesAndNewlines)
            let lang: String? = maybeLang.isEmpty ? nil : String(maybeLang)
            
            // ابحث عن السور الختامي
            let afterHeader = remainder.index(after: lineBreak)
            if let fenceEnd = remainder[afterHeader...].range(of: fence) {
                let codeBody = String(remainder[afterHeader..<fenceEnd.lowerBound])
                parts.append(.code(lang: lang, body: codeBody))
                remainder = remainder[fenceEnd.upperBound...]
            } else {
                // لا سور إغلاق -> اعتبره نصًا
                parts.append(.text(String(remainder[fenceStart.lowerBound...])))
                return parts
            }
        }
        if !remainder.isEmpty {
            parts.append(.text(String(remainder)))
        }
        return parts
    }
}

// MARK: - زر نسخ يتبدّل نصّه مؤقتًا
struct CopyButton: View {
    let textToCopy: String
    @State private var copied = false
    
    var body: some View {
        Button {
            UIPasteboard.general.string = textToCopy
            withAnimation(.spring()) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut) { copied = false }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                Text(copied ? "تم النسخ" : "نسخ")
            }
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 6)
            // تم حذف .background(.ultraThinMaterial, in: Capsule())
        }
        .animation(.default, value: copied)
    }
}

// MARK: - جسم رسالة دردشة (نص + كتل كود)
struct ChatMessageBodyView: View {
    let content: String
    let fontSize: Double
    
    // نص ماركداون مبسّط (غامق/مائل/inline code)
    private func richText(_ s: String) -> AttributedString {
        var opts = AttributedString.MarkdownParsingOptions()
        opts.interpretedSyntax = .inlineOnlyPreservingWhitespace
        opts.allowsExtendedAttributes = true
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }
    
    var body: some View {
        let parts = ChatPartsParser.parse(content)
        
        VStack(alignment: .leading, spacing: 10) {        // في RTL: leading = يمين
            ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                switch p {
                case .text(let s):
                    Text(richText(s))
                        .font(.system(size: fontSize))
                        .foregroundColor(.white)
                        .textSelection(.enabled)
                    
                case .code(let lang, let body):
                    // يستخدم SimpleSyntaxHighlighter داخل CodeBlockView
                    CodeBlockView(code: body, language: normalize(lang))
                        .frame(maxWidth: .infinity, alignment: .leading) // ✅ الآن ياخذ كامل عرض الشاشة
                }
            }
        }
    }
    
    /// توحيد/تطبيع أسماء اللغات لعرض الشارة الصحيحة.
    /// - إن لم تُذكر لغة نعيد "code" كي تُعرض شارة عامة.
    /// - المرادفات تُحوّل لاسم موحّد (javascript, typescript, bash, css, …).
    private func normalize(_ lang: String?) -> String {
        guard let raw0 = lang?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw0.isEmpty else {
            return "code" // لا لغة محددة
        }
        let raw = raw0.lowercased()
        
        switch raw {
            // أساسيات الويب
        case "js", "javascript", "node", "nodejs": return "javascript"
        case "ts", "typescript": return "typescript"
        case "html", "htm": return "html"
        case "css": return "css"
        case "scss", "sass": return "scss"
        case "less": return "less"
            
            // بايثون والأسرة
        case "py", "python": return "python"
            
            // شِل
        case "sh", "bash", "zsh", "shell": return "bash"
            
            // تكوينات وبيانات
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "toml": return "toml"
        case "ini": return "ini"
        case "xml": return "xml"
        case "md", "markdown": return "markdown"
            
            // قواعد بيانات
        case "sql", "postgres", "postgresql", "mysql", "sqlite", "mssql": return "sql"
            
            // لغات سي وعائلتها
        case "c": return "c"
        case "cpp", "c++", "cxx": return "cpp"
        case "cs", "csharp", "c#": return "csharp"
        case "objective-c", "objc", "objectivec": return "objective-c"
            
            // أخرى شائعة
        case "swift": return "swift"
        case "java": return "java"
        case "kotlin", "kt": return "kotlin"
        case "go", "golang": return "go"
        case "rs", "rust": return "rust"
        case "php": return "php"
        case "rb", "ruby": return "ruby"
        case "dart": return "dart"
        case "r": return "r"
        case "scala": return "scala"
        case "perl", "pl": return "perl"
        case "matlab": return "matlab"
        case "powershell", "ps", "ps1": return "powershell"
        case "lua": return "lua"
        case "haskell", "hs": return "haskell"
        case "elixir", "ex", "exs": return "elixir"
        case "clojure", "clj", "cljs": return "clojure"
        case "groovy": return "groovy"
        case "dart": return "dart"
            
            // أدوات/ملفات بناء
        case "dockerfile", "docker": return "dockerfile"
        case "makefile", "make": return "makefile"
        case "gradle": return "gradle"
        case "cmake": return "cmake"
            
            // إطار عام: إن كانت لغة غير معروفة لدينا، أعِدها كما هي بدون إجبارها على swift
        default:
            return raw
        }
    }
}
