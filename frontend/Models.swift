import Foundation

// ======================================================================
// MARK: - المزوّدون والمفاتيح
// ======================================================================

enum Provider: String, Codable, CaseIterable {
    case gemini
    case openrouter
    case custom
}

enum APIKeyStatus: String, Codable { case active, disabled }

struct APIKeyEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var key: String
    var status: APIKeyStatus = .active
}

enum APIKeyRetryStrategy: String, Codable { case sequential, roundRobin }

// ======================================================================
// MARK: - مزوّدون/نماذج مخصّصة
// ======================================================================

struct CustomModel: Codable, Equatable, Identifiable {
    var id: String              // مثال: "my-model-1"
    var name: String            // اسم العرض
    var providerId: String?     // ربطه بالمزوّد المخصّص
    var defaultTemperature: Double?
    var description: String?
}

struct CustomProvider: Codable, Equatable, Identifiable {
    var id: String              // مثال: "custom_123"
    var name: String            // مثال: "مزود مؤسّسي"
    var baseUrl: URL            // جذر الـ API (مثلاً: https://api.example.com/v1)
    var models: [CustomModel] = []
    var apiKeys: [APIKeyEntry] = []
}

// ======================================================================
// MARK: - الإعدادات العامة للتطبيق (متوافقة مع Services)
// ======================================================================

struct AppSettings: Codable, Equatable {
    var provider: Provider = .gemini
    var model: String = "gemini-1.5-flash"
    var temperature: Double = 0.7
    var fontSize: Double = 18
    var customPrompt: String = ""
    
    var apiKeyRetryStrategy: APIKeyRetryStrategy = .sequential
    var geminiApiKeys: [APIKeyEntry] = []
    var openrouterApiKeys: [APIKeyEntry] = []
    
    var customProviders: [CustomProvider] = []
    var customModels: [CustomModel] = []
}

// ======================================================================
// MARK: - نماذج المحادثة (مطابقة لبنية الويب ومستخدمة في Services)
// ======================================================================

enum SenderRole: String, Codable { case user, assistant }

struct Attachment: Codable, Equatable {
    var name: String
    var size: Int64?
    var type: String?      // MIME type (مثل: image/png أو text/plain)
    var dataType: String?  // "text" أو "image"
    var content: String?   // محتوى النص أو Base64 للصورة
}

struct MessageDTO: Codable, Equatable, Identifiable {
    var id = UUID()
    var role: SenderRole
    var content: String
    var attachments: [Attachment] = []
    var timestamp: TimeInterval   // milliseconds منذ Epoch
}

struct ChatDTO: Codable, Equatable, Identifiable {
    var id: String                // عادةً رقم الوقت كـ String
    var title: String
    var messages: [MessageDTO]
    var createdAt: TimeInterval
    var updatedAt: TimeInterval
    var order: Double             // للفرز نزولياً في القائمة
}

struct ZeusStore: Codable, Equatable {
    var chats: [String: ChatDTO]  // قاموس المحادثات بواسطة id
    var currentChatId: String?    // المفعّلة حالياً
}

// ملاحظة: إذا كان لديك امتداد String.clippedTitle(...) في ملف آخر (مثلاً Views),
// فلا تضِفّه مجدداً هنا لتجنّب "Invalid redeclaration".
