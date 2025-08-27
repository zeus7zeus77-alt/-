import Foundation
import UniformTypeIdentifiers

// MARK: - Allowed Doc Types (Cached & Fast)
private enum DocTypesCache {
    static let allowed: [UTType] = {
        // ✳️ الأساسيات المعروفة سلفًا
        var types: [UTType] = [.plainText, .json, .xml, .sourceCode]
        
        // ✳️ تقسيم الامتدادات إلى مجموعات صغيرة لتقليل تعقيد الاستدلال
        let groups: [[String]] = [
            ["js", "ts", "tsx", "jsx"],
            ["md", "markdown", "yaml", "yml"],
            ["css", "scss"],
            ["html", "htm"],
            ["txt", "log", "swift"]
        ]
        
        // ✳️ تحويل كل مجموعة إلى UTType ثم إضافتها
        for group in groups {
            let extra = group.compactMap { (ext: String) -> UTType? in
                UTType(filenameExtension: ext)
            }
            types.append(contentsOf: extra)
        }
        
        // ✳️ إزالة التكرار إن وُجد (احترازًا) ثم الإرجاع
        return Array(Set(types))
    }()
}

// ✅ واجهة الاستدعاء
func allowedDocTypes() -> [UTType] {
    return DocTypesCache.allowed
}

// MARK: - Helpers
func guessImageMime(from data: Data, fallback: String? = nil) -> (mime: String, ext: String) {
    // PNG
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return ("image/png", "png") }
    // JPEG
    if data.starts(with: [0xFF, 0xD8, 0xFF]) { return ("image/jpeg", "jpg") }
    // GIF
    if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return ("image/gif", "gif") }
    // WEBP: "RIFF....WEBP"
    if data.starts(with: [0x52, 0x49, 0x46, 0x46]) &&
        data.dropFirst(8).starts(with: [0x57, 0x45, 0x42, 0x50]) {
        return ("image/webp", "webp")
    }
    return (fallback ?? "image/jpeg", "jpg")
}
