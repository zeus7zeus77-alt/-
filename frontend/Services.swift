import Foundation

// MARK: - تخزين محادثات ZeusStore في ملف JSON واحد
final class ZeusPersistence {
    static let shared = ZeusPersistence(); private init() {}
    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("zeus_store_v1.json")
    }()
    
    func save(store: ZeusStore) {
        do {
            let data = try JSONEncoder().encode(store)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("❌ فشل حفظ zeus_store: \(error)")
        }
    }
    
    func load() -> ZeusStore? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(ZeusStore.self, from: data)
        } catch {
            print("❌ فشل قراءة zeus_store: \(error)")
            return nil
        }
    }
}

// MARK: - تخزين/قراءة AppSettings من ملف JSON
final class SettingsPersistence {
    static let shared = SettingsPersistence(); private init() {}
    
    private var url: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("zeus_settings_v1.json")
    }
    
    func load() -> AppSettings {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return AppSettings() // افتراضي
        }
    }
    
    func save(_ s: AppSettings) {
        do {
            let data = try JSONEncoder().encode(s)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("❌ فشل حفظ الإعدادات: \(error)")
        }
    }
}

// ======================================================================
// MARK: - APIManager موحّد (يدعم Gemini / OpenRouter / Custom + مفاتيح متعددة)
// ======================================================================

final class APIManager {
    static let shared = APIManager(); private init() {}
    
    // فهارس Round-Robin لكل "سطل" مفاتيح
    private var rrIndex: [String: Int] = [:]
    
    // تنقية رسائل المحادثة قبل الإرسال (منع عناصر الواجهة/الفارغ)
    private func sanitizedMessages(_ messages: [MessageDTO]) -> [MessageDTO] {
        let blockedExact: Set<String> = [
            "جاري الكتابة…", "جاري الكتابة...", "جارٍ الكتابة…", "جارٍ الكتابة...",
            "typing…", "typing...", "…", "..."
        ]
        return messages.filter { msg in
            let t = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return false }
            if msg.role == .assistant {
                if blockedExact.contains(t) { return false }
                if t.contains("جاري الكتابة") || t.contains("جارٍ الكتابة") || t.lowercased().contains("typing") {
                    return false
                }
            }
            return true
        }
    }
    
    // اختيار المفتاح التالي بحسب الاستراتيجية
    private func nextKey(from keys: [APIKeyEntry],
                         strategy: APIKeyRetryStrategy,
                         bucket: String) -> String? {
        let active = keys.filter { $0.status == .active && !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !active.isEmpty else { return nil }
        switch strategy {
        case .sequential:
            return active.first?.key
        case .roundRobin:
            let idx = rrIndex[bucket, default: 0] % active.count
            rrIndex[bucket] = idx + 1
            return active[idx].key
        }
    }
    
    // نقطة الدخول العامة
    func sendMessage(from chat: ChatDTO,
                     settings: AppSettings,
                     completion: @escaping (String) -> Void) {
        // أنشئ نسخة مُصفّاة من الرسائل
        let cleanChat = ChatDTO(
            id: chat.id,
            title: chat.title,
            messages: sanitizedMessages(chat.messages),
            createdAt: chat.createdAt,
            updatedAt: chat.updatedAt,
            order: chat.order
        )
        
        switch settings.provider {
        case .gemini:
            sendToGemini(chat: cleanChat, settings: settings, completion: completion)
        case .openrouter:
            sendToOpenRouter(chat: cleanChat, settings: settings, completion: completion)
        case .custom:
            sendToCustomProvider(chat: cleanChat, settings: settings, completion: completion)
        }
    }
}

// =======================================================
// MARK: - OpenRouter
// =======================================================

private extension APIManager {
    func openrouterMessages(for chat: ChatDTO,
                            customPrompt: String?) -> [[String: Any]] {
        var msgs: [[String: Any]] = []
        if let p = customPrompt, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            msgs.append(["role": "system", "content": p])
        }
        for m in chat.messages {
            var text = m.content
            for a in m.attachments {
                if a.dataType == "text", let t = a.content {
                    text += "\n\n--- محتوى الملف: \(a.name) ---\n\(t)\n--- نهاية الملف ---"
                } else if a.dataType == "image" {
                    // بعض النماذج لا تدعم الصور مباشرة في chat/completions؛ نضيف إشارة
                    text += "\n\n[صورة مرفقة: \(a.name)]"
                }
            }
            msgs.append(["role": (m.role == .user ? "user" : "assistant"), "content": text])
        }
        return msgs
    }
    
    func sendToOpenRouter(chat: ChatDTO,
                          settings: AppSettings,
                          completion: @escaping (String) -> Void) {
        guard let key = nextKey(from: settings.openrouterApiKeys,
                                strategy: settings.apiKeyRetryStrategy,
                                bucket: "openrouter") else {
            completion("❌ لا توجد مفاتيح OpenRouter نشطة")
            return
        }
        
        let body: [String: Any] = [
            "model": settings.model,
            "messages": openrouterMessages(for: chat, customPrompt: settings.customPrompt),
            "temperature": settings.temperature,
            "stream": false,
            "max_tokens": 4096
        ]
        
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data else {
                completion("❌ لا توجد بيانات من OpenRouter")
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let reply = msg["content"] as? String {
                completion(reply)
            } else {
                completion("❌ تعذّر تحليل استجابة OpenRouter")
            }
        }.resume()
    }
}

// =======================================================
// MARK: - مزوّد مخصّص (توافق OpenAI-style)
// =======================================================

private extension APIManager {
    func resolveCustomProvider(settings: AppSettings) -> CustomProvider? {
        // اختر أول مزوّد مخصّص أو يمكنك تحسين المنطق للبحث حسب model/providerId
        return settings.customProviders.first
    }
    
    func sendToCustomProvider(chat: ChatDTO,
                              settings: AppSettings,
                              completion: @escaping (String) -> Void) {
        guard let provider = resolveCustomProvider(settings: settings) else {
            completion("❌ لا يوجد مزوّد مخصّص مُعرّف")
            return
        }
        guard let key = nextKey(from: provider.apiKeys,
                                strategy: settings.apiKeyRetryStrategy,
                                bucket: provider.id) else {
            completion("❌ لا توجد مفاتيح للمزوّد المخصّص")
            return
        }
        
        // نفترض توافق /chat/completions
        let body: [String: Any] = [
            "model": settings.model,
            "messages": openrouterMessages(for: chat, customPrompt: settings.customPrompt),
            "temperature": settings.temperature
        ]
        
        var req = URLRequest(url: provider.baseUrl.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data else {
                completion("❌ لا توجد بيانات من المزود المخصّص")
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let reply = msg["content"] as? String {
                completion(reply)
            } else {
                completion("❌ تعذّر تحليل استجابة المزوّد المخصّص")
            }
        }.resume()
    }
}

// =======================================================
// MARK: - Gemini (نص + صور Base64 عبر inline_data)
// =======================================================

private extension APIManager {
    func geminiBody(for chat: ChatDTO,
                    model: String,
                    temperature: Double,
                    customPrompt: String?) -> [String: Any] {
        var contents: [[String: Any]] = []
        
        // برومبت مخصّص (إن وُجد) كبداية للحوار
        if let p = customPrompt, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contents.append(["role": "user", "parts": [["text": p]]])
            contents.append(["role": "model", "parts": [["text": "مفهوم، سأتبع هذه التعليمات."]]])
        }
        
        for m in chat.messages {
            var parts: [[String: Any]] = []
            if !m.content.isEmpty { parts.append(["text": m.content]) }
            
            // المرفقات: نصوص تُلحق كنص؛ صور تُرسل inline_data (Base64)
            for a in m.attachments {
                if a.dataType == "image", let b64 = a.content, let mime = a.type {
                    parts.append(["inline_data": ["mime_type": mime, "data": b64]])
                } else if a.dataType == "text", let t = a.content {
                    parts.append(["text": "\n\n--- محتوى الملف: \(a.name) ---\n\(t)\n--- نهاية الملف ---"])
                }
            }
            contents.append(["role": (m.role == .user ? "user" : "model"), "parts": parts])
        }
        
        return [
            "contents": contents,
            "generationConfig": [
                "temperature": temperature,
                "maxOutputTokens": 4096
            ]
        ]
    }
    
    func sendToGemini(chat: ChatDTO,
                      settings: AppSettings,
                      completion: @escaping (String) -> Void) {
        guard let key = nextKey(from: settings.geminiApiKeys,
                                strategy: settings.apiKeyRetryStrategy,
                                bucket: "gemini") else {
            completion("❌ لا توجد مفاتيح Gemini نشطة")
            return
        }
        
        let body = geminiBody(for: chat,
                              model: settings.model,
                              temperature: settings.temperature,
                              customPrompt: settings.customPrompt)
        
        // بدايةً بدون بث (يمكن تحويلها لاحقاً إلى SSE)
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(settings.model):generateContent?key=\(key)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data else {
                completion("❌ لا توجد بيانات من Gemini")
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let reply = parts.first?["text"] as? String {
                completion(reply)
            } else {
                completion("❌ تعذّر تحليل استجابة Gemini")
            }
        }.resume()
    }
}
