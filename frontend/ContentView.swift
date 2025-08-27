import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - MAIN APP
struct ContentView: View {
    @State private var showSidebar = false
    @State private var showSettings = false
    
    // المتجر الجديد للمحادثات
    @State private var store = ZeusStore(chats: [:], currentChatId: nil)
    
    // الإعدادات (من SettingsPersistence)
    @State private var settings: AppSettings = SettingsPersistence.shared.load()
    
    @State private var chatText: String = ""
    
    // ✅ مرفقات قيد التحضير قبل الإرسال
    @State private var pendingAttachments: [Attachment] = []
    
    // ✅ عناصر تحكم بالمرفقات
    @State private var showAttachSheet = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var pickedPhotoItem: PhotosPickerItem? = nil
    
    // المحادثة الحالية
    private var currentChat: ChatDTO? {
        guard let id = store.currentChatId else { return nil }
        return store.chats[id]
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                // ✅ التعديلات هنا
                let isWide = geo.size.width >= 700
                let calculatedSidebarWidth = geo.size.width * 0.33
                let sidebarWidth = min(max(320, calculatedSidebarWidth), 420)
                let contentOffset = (showSidebar && isWide) ? sidebarWidth : 0
                
                ZStack(alignment: .leading) {
                    // المحتوى الرئيسي
                    ChatView(
                        messages: currentChat?.messages ?? [],
                        chatText: $chatText,
                        settings: settings,                      // تمرير الإعدادات للخط
                        pendingAttachments: $pendingAttachments, // عرض وإدارة المرفقات قبل الإرسال
                        onSend: { sendMessage(text: $0) },
                        onPlus: { showAttachSheet = true }       // ربط زر +
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle(providerDisplayName(settings.provider))
                    .offset(x: contentOffset) // ✅ استخدام المتغير الجديد
                    .animation(.easeInOut(duration: 0.25), value: showSidebar)
                    
                    // طبقة التعتيم
                    if showSidebar {
                        Color.black.opacity(isWide ? 0.35 : 0.5)
                            .ignoresSafeArea()
                            .onTapGesture { withAnimation(.easeInOut) { showSidebar = false } }
                            .transition(.opacity)
                            .allowsHitTesting(true)
                    }
                    
                    // الشريط (يسار)
                    SidebarView(
                        store: $store,
                        showSidebar: $showSidebar,
                        showSettings: $showSettings,
                        selectChat: { id in switchToChat(id) },
                        createChat: { startNewChat() },
                        deleteChat: { id in deleteChat(id) }
                    )
                    .frame(width: sidebarWidth, height: geo.size.height)
                    .background(Color(.systemGray6))
                    .offset(x: showSidebar ? 0 : -sidebarWidth)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 4, y: 0)
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onEnded { value in
                                if value.translation.width < -60 {
                                    withAnimation(.easeInOut) { showSidebar = false }
                                }
                            }
                    )
                    .animation(.easeInOut(duration: 0.25), value: showSidebar)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onEnded { value in
                            if !showSidebar,
                               value.startLocation.x < 20,
                               value.translation.width > 40 {
                                withAnimation(.easeInOut) { showSidebar = true }
                            }
                        }
                )
            }
            // زر «الشخطتين» في شريط العنوان
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showSidebar.toggle() }
                    } label: {
                        SidebarIcon()
                    }
                    .accessibilityLabel(Text(showSidebar ? "إغلاق الشريط" : "فتح الشريط"))
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: $settings)
        }
        .onAppear {
            // تحميل المحادثات
            if let loaded = ZeusPersistence.shared.load() {
                store = loaded
            }
            // ضمان وجود محادثة
            if store.currentChatId == nil {
                startNewChat(title: "مرحبا! اكتب سؤالك…", seedAssistant: true)
            }
        }
        .onChange(of: store) { _, newVal in
            ZeusPersistence.shared.save(store: newVal)
        }
        .onChange(of: settings) { _, newVal in
            SettingsPersistence.shared.save(newVal)
        }
        .environment(\.layoutDirection, .rightToLeft)
        
        // ✅ قائمة خيارات المرفقات
        .confirmationDialog("إضافة مرفق", isPresented: $showAttachSheet, titleVisibility: .visible) {
            Button("اختيار صورة من الصور") { showPhotoPicker = true }
            Button("استيراد ملف") { showFileImporter = true }
            Button("إلغاء", role: .cancel) { }
        }
        // ✅ منتقي الصور (نحمل Data فقط)
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhotoItem, matching: .images)
        .onChange(of: pickedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    // مصدر MIME من UTType (إن وُجد) + تخمين عبر البصمة
                    let utMime = item.supportedContentTypes.first?.preferredMIMEType
                    let (mime, ext) = guessImageMime(from: data, fallback: utMime)
                    let name = "image.\(ext)"
                    let att = Attachment(
                        name: name,
                        size: Int64(data.count),
                        type: mime,
                        dataType: "image",
                        content: data.base64EncodedString()
                    )
                    pendingAttachments.append(att)
                }
                pickedPhotoItem = nil
            }
        }
        // ✅ مستورد ملفات (JS/نصوص…)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: allowedDocTypes(),   // ✅ بدل [.javascript ...]
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    // 🔐 فتح الصلاحية الأمنية
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    
                    do {
                        // ✅ نسخ الملف إلى مجلد مؤقت لتفادي مشاكل iCloud/permissions
                        let dst = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(url.pathExtension)
                        
                        try? FileManager.default.copyItem(at: url, to: dst)
                        
                        let data = try Data(contentsOf: dst)
                        let txt = String(data: data, encoding: .utf8) ?? ""
                        
                        let mime = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.preferredMIMEType)
                        ?? "text/plain"
                        
                        let att = Attachment(
                            name: url.lastPathComponent,
                            size: Int64(data.count),
                            type: mime,
                            dataType: "text",
                            content: txt
                        )
                        pendingAttachments.append(att)
                    } catch {
                        print("❌ فشل قراءة الملف: \(error)")
                    }
                }
            case .failure(let err):
                print("❌ فشل الاستيراد: \(err)")
            }
        }
    }
    
    // MARK: - عمليات المحادثات
    private func startNewChat(title: String = "محادثة جديدة", seedAssistant: Bool = false) {
        let now = Date().timeIntervalSince1970 * 1000
        let id = String(Int64(now))
        var msgs: [MessageDTO] = []
        if seedAssistant {
            msgs.append(.init(role: .assistant, content: title, attachments: [], timestamp: now))
        }
        let chat = ChatDTO(id: id, title: title, messages: msgs, createdAt: now, updatedAt: now, order: now)
        store.chats[id] = chat
        store.currentChatId = id
    }
    
    private func switchToChat(_ id: String) {
        guard store.chats[id] != nil else { return }
        store.currentChatId = id
    }
    
    private func deleteChat(_ id: String) {
        store.chats.removeValue(forKey: id)
        if store.currentChatId == id {
            store.currentChatId = store.chats
                .values.sorted(by: { $0.order > $1.order })
                .first?.id
        }
    }
    
    private func updateCurrentChat(_ chat: ChatDTO) {
        store.chats[chat.id] = chat
    }
    
    private func appendUserMessage(_ text: String, attachments: [Attachment] = []) {
        guard var chat = currentChat else { return }
        let now = Date().timeIntervalSince1970 * 1000
        chat.messages.append(.init(role: .user, content: text, attachments: attachments, timestamp: now))
        chat.updatedAt = now
        chat.order = now
        
        if chat.title == "محادثة جديدة" || chat.title == "مرحبا! اكتب سؤالك…" || chat.title.trimmingCharacters(in: .whitespaces).isEmpty {
            chat.title = text.clippedTitle() // تأكّد من وجود الامتداد في Views
        }
        updateCurrentChat(chat)
    }
    
    private func appendAssistantMessage(_ text: String) {
        guard var chat = currentChat else { return }
        let now = Date().timeIntervalSince1970 * 1000
        chat.messages.append(.init(role: .assistant, content: text, attachments: [], timestamp: now))
        chat.updatedAt = now
        chat.order = now
        updateCurrentChat(chat)
    }
    
    private func removeTypingIfExists() {
        guard var chat = currentChat else { return }
        if let last = chat.messages.last,
           last.role == .assistant, last.content == "جاري الكتابة..." {
            _ = chat.messages.popLast()
            updateCurrentChat(chat)
        }
    }
    
    private func sendMessage(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if store.currentChatId == nil { startNewChat() }
        
        // ✅ أرسل المرفقات المُختارة ثم صفّرها
        let toSend = pendingAttachments
        pendingAttachments = []
        
        appendUserMessage(trimmed, attachments: toSend)
        appendAssistantMessage("جاري الكتابة...")
        
        // ✅ APIManager يتوقع ChatDTO غير اختياري
        guard let chat = currentChat else { return }
        APIManager.shared.sendMessage(from: chat, settings: settings) { reply in
            DispatchQueue.main.async {
                removeTypingIfExists()
                appendAssistantMessage(reply)
            }
        }
    }
    
    // MARK: - عرض اسم المزوّد في شريط العنوان
    private func providerDisplayName(_ p: Provider) -> String {
        switch p {
        case .gemini: return "Gemini"
        case .openrouter: return "OpenRouter"
        case .custom: return "Custom"
        }
    }
}
