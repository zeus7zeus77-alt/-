import SwiftUI
import UIKit

// MARK: - Helpers
extension String {
    /// تقليم اسم العنوان كي لا يطول في القائمة
    func clippedTitle(max: Int = 40) -> String {
        let t = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > max else { return t }
        let end = t.index(t.startIndex, offsetBy: max)
        return t[t.startIndex..<end] + "…"
    }
}

private func bytesString(_ n: Int64?) -> String {
    guard let n else { return "—" }
    let f = ByteCountFormatter()
    f.allowedUnits = [.useKB, .useMB]
    f.countStyle = .file
    return f.string(fromByteCount: n)
}

private func imageFromBase64(_ b64: String) -> UIImage? {
    guard let data = Data(base64Encoded: b64) else { return nil }
    return UIImage(data: data)
}

// MARK: - Sidebar icon (شكل الخطّين)
struct SidebarIcon: View {
    var body: some View {
        VStack(spacing: 3) {
            Capsule().frame(width: 22, height: 3)
            Capsule().frame(width: 12, height: 3)
        }
        .foregroundStyle(Color.primary)
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Sidebar
struct SidebarView: View {
    @Binding var store: ZeusStore
    @Binding var showSidebar: Bool
    @Binding var showSettings: Bool
    
    var selectChat: (String) -> Void
    var createChat: () -> Void
    var deleteChat: (String) -> Void
    
    @State private var query: String = ""
    
    // للحوار الخاص بإعادة التسمية
    @State private var renamePresented = false
    @State private var renameText = ""
    @State private var renameTargetId: String? = nil
    
    var sortedChats: [ChatDTO] {
        store.chats.values.sorted(by: { $0.order > $1.order })
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            // رأس الشريط: جديد + بحث
            HStack(spacing: 10) {
                Button {
                    createChat()
                    withAnimation(.easeInOut) { showSidebar = false }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .padding(10)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                }
                
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("بحث", text: $query)
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.trailing)
                }
                .padding(10)
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            
            // قائمة المحادثات
            ScrollView {
                LazyVStack(alignment: .trailing, spacing: 8) {
                    ForEach(filteredChats(), id: \.id) { chat in
                        Button {
                            selectChat(chat.id)
                            withAnimation(.easeInOut) { showSidebar = false }
                        } label: {
                            Text(chat.title.isEmpty ? "محادثة" : chat.title)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteChat(chat.id)
                            } label: {
                                Label("حذف المحادثة", systemImage: "trash")
                            }
                            
                            Button {
                                renameTargetId = chat.id
                                renameText = chat.title
                                renamePresented = true
                            } label: {
                                Label("إعادة التسمية", systemImage: "pencil")
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
            
            Spacer(minLength: 8)
            
            // تذييل الشريط: الإعدادات
            Button {
                showSettings = true
                withAnimation(.easeInOut) { showSidebar = false }
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                    Text("الإعدادات")
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(Color(.systemGray6))
        // نافذة إعادة التسمية
        .sheet(isPresented: $renamePresented) {
            NavigationStack {
                Form {
                    Section(header: Text("اسم المحادثة")) {
                        TextField("أدخل اسمًا", text: $renameText)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .navigationTitle("إعادة التسمية")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("إلغاء") { renamePresented = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("حفظ") {
                            if let id = renameTargetId, !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                var chat = store.chats[id]
                                chat?.title = renameText.clippedTitle()
                                if let chat { store.chats[id] = chat }
                            }
                            renamePresented = false
                        }
                    }
                }
            }
        }
    }
    
    private func filteredChats() -> [ChatDTO] {
        let list = sortedChats
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return list }
        let q = query.lowercased()
        return list.filter { chat in
            if chat.title.lowercased().contains(q) { return true }
            return chat.messages.contains { $0.content.lowercased().contains(q) }
        }
    }
}

// MARK: - شريط الإدخال (⬆️ يسار + نص وسط + + يمين)
struct InputBarView: View {
    @Binding var text: String
    var fontSize: Double = 18
    var onSend: (String) -> Void
    var onPlus: () -> Void = {}
    
    private let barHeight: CGFloat = 56
    private let buttonSize: CGFloat = 40
    private let corner: CGFloat = 22
    
    var body: some View {
        HStack(spacing: 8) {
            // يسار: زر إرسال
            Button {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSend(trimmed)
                text = ""
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Color.white, in: Circle())
            }
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1.0)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("إرسال")
            
            // الوسط: حقل الكتابة
            ZStack(alignment: .trailing) {
                if text.isEmpty {
                    Text("اسأل عن أي شيء")
                        .foregroundColor(Color.white.opacity(0.5))
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .font(.system(size: fontSize))
                }
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 40, maxHeight: 120)
                    .font(.system(size: fontSize))
                    .accessibilityLabel("حقل الإدخال")
            }
            .padding(.vertical, 8)
            .background(Color(.darkGray).opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: corner))
            
            // يمين: زر زائد
            Button(action: onPlus) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Color(.darkGray).opacity(0.7), in: Circle())
            }
            .accessibilityLabel("خيارات إضافية")
        }
        .frame(height: barHeight)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - شارات/مصغّرات المرفقات (قبل الإرسال)
struct PendingAttachmentChip: View {
    let att: Attachment
    let remove: () -> Void
    
    var body: some View {
        if att.dataType == "image", let b64 = att.content, let ui = imageFromBase64(b64) {
            ZStack(alignment: .topLeading) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipped()
                    .cornerRadius(10)
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .offset(x: -6, y: -6)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                Text(att.name).lineLimit(1)
                Text(bytesString(att.size)).foregroundColor(.secondary).font(.footnote)
                Button(role: .destructive, action: remove) {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.15), in: Capsule())
        }
    }
}

// MARK: - عرض المرفقات داخل الرسائل
struct MessageAttachmentsView: View {
    let atts: [Attachment]
    @State private var previewImage: UIImage?
    @State private var previewText: String?
    
    // عمودان للصور المتعددة
    private let twoCols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            // الصور
            let images = atts.filter { $0.dataType == "image" && ($0.content?.isEmpty == false) }
            if !images.isEmpty {
                if images.count == 1, let b64 = images.first?.content, let ui = imageFromBase64(b64) {
                    // صورة واحدة: أعرضها كاملة فوق النص، بمحاذاة يمين
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, alignment: .trailing)   // 👈 حد أقصى مثل GPT
                        .cornerRadius(12)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                        .onTapGesture { previewImage = ui }
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.white.opacity(0.08))
                        )
                        .transition(.opacity)
                } else {
                    // صور متعددة: شبكة 2 أعمدة
                    LazyVGrid(columns: twoCols, alignment: .trailing, spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, a in
                            if let b64 = a.content, let ui = imageFromBase64(b64) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 140)
                                    .clipped()
                                    .cornerRadius(12)
                                    .contentShape(Rectangle())
                                    .onTapGesture { previewImage = ui }
                            }
                        }
                    }
                }
            }
            
            // ملفات نصّية/ملفات عامة
            let texts = atts.filter { $0.dataType == "text" }
            ForEach(Array(texts.enumerated()), id: \.offset) { _, a in
                Button {
                    previewText = a.content ?? ""
                } label: {
                    // بطاقة مدمجة لا تتمدّد بعرض الشاشة
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(a.name).lineLimit(1)
                            Text(bytesString(a.size))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        Image(systemName: "chevron.left")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: 340, alignment: .trailing)   // حد أقصى للعرض
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)  // تبقى البطاقة يميناً
            }
        }
        // معاينات
        .sheet(item: Binding(get: {
            previewImage.map { _ImageWrap(image: $0) }
        }, set: { _ in previewImage = nil })) { wrap in
            Image(uiImage: wrap.image).resizable().scaledToFit().ignoresSafeArea()
        }
        .sheet(item: Binding(get: {
            previewText.map { _TextWrap(text: $0) }
        }, set: { _ in previewText = nil })) { wrap in
            ScrollView {
                Text(wrap.text).textSelection(.enabled)
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
        }
    }
    // Helpers for sheet identifiable
    struct _ImageWrap: Identifiable { let id = UUID(); let image: UIImage }
    struct _TextWrap: Identifiable { let id = UUID(); let text: String }
}

// MARK: - Chat View + شريط الإدخال
struct ChatView: View {
    var messages: [MessageDTO]
    @Binding var chatText: String
    var settings: AppSettings                   // لاستخدام fontSize
    @Binding var pendingAttachments: [Attachment] // عرض المرفقات قبل الإرسال
    var onSend: (String) -> Void
    var onPlus: () -> Void
    
    // مُهيّئ افتراضي لجعل الاستدعاء القديم يعمل دون أخطاء
    init(
        messages: [MessageDTO],
        chatText: Binding<String>,
        settings: AppSettings = AppSettings(),
        pendingAttachments: Binding<[Attachment]> = .constant([]),
        onSend: @escaping (String) -> Void,
        onPlus: @escaping () -> Void = {}
    ) {
        self.messages = messages
        self._chatText = chatText
        self.settings = settings
        self._pendingAttachments = pendingAttachments
        self.onSend = onSend
        self.onPlus = onPlus
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .trailing, spacing: 12) {
                        ForEach(messages) { message in
                            VStack(alignment: .trailing, spacing: 8) {
                                // 👇 الآن المرفقات فوق النص مباشرة مثل تطبيق GPT
                                if !message.attachments.isEmpty {
                                    MessageAttachmentsView(atts: message.attachments)
                                }
                                ChatMessageView(message: message, fontSize: settings.fontSize)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .background(Color.black)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation(.easeOut) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            
            // شارات المرفقات المختارة قبل الإرسال
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(pendingAttachments.enumerated()), id: \.offset) { idx, att in
                            PendingAttachmentChip(att: att) {
                                pendingAttachments.remove(at: idx)
                            }
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 6)
                }
                .background(Color.black)
            }
            
            Divider()
            
            // شريط الإدخال
            InputBarView(
                text: $chatText,
                fontSize: settings.fontSize,
                onSend: onSend,
                onPlus: onPlus
            )
            .background(Color(.systemGray6))
        }
    }
}

// MARK: - Chat Bubble
struct ChatMessageView: View {
    var message: MessageDTO
    var fontSize: Double
    private let maxBubbleWidth: CGFloat = 560
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                // المستخدم يمين
                Spacer(minLength: 0)
                userBubble(message: message, fontSize: fontSize)
                    .frame(maxWidth: maxBubbleWidth, alignment: .trailing)
            } else {
                // المساعد يسار، ويمتد على كامل العرض
                assistantBubble(message: message, fontSize: fontSize)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
    }

    
    // تأكد أن تعريفات userBubble و assistantBubble موجودة هنا
}

private func userBubble(message: MessageDTO, fontSize: Double) -> some View {
    Text(message.content)
        .font(.system(size: fontSize))
        .padding(12)
        .background(Color.gray)
        .foregroundColor(.black)
        .cornerRadius(10)
        .fixedSize(horizontal: false, vertical: true)
}

private func assistantBubble(message: MessageDTO, fontSize: Double) -> some View {
    ChatMessageBodyView(content: message.content, fontSize: fontSize)
        .padding(12)
        .fixedSize(horizontal: false, vertical: true)
}



// MARK: - Settings (متوافقة مع تعديلات Services: تعدّد مفاتيح + مزوّدات مخصّصة)
struct SettingsView: View {
    @Binding var settings: AppSettings
    
    var body: some View {
        NavigationStack {
            Form {
                // المزوّد والنموذج والحرارة والخط والبرومبت
                Section(header: Text("المزوّد والنموذج")) {
                    Picker("اختر المزود", selection: $settings.provider) {
                        ForEach(Provider.allCases, id: \.self) { p in
                            Text(displayName(for: p)).tag(p)
                        }
                    }
                    TextField("معرّف النموذج", text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.trailing)
                    
                    HStack {
                        Text("درجة الحرارة")
                        Slider(value: $settings.temperature, in: 0...1, step: 0.1)
                        Text(String(format: "%.1f", settings.temperature))
                    }
                    
                    HStack {
                        Text("حجم خط الرسائل")
                        Slider(value: $settings.fontSize, in: 14...24, step: 1)
                        Text("\(Int(settings.fontSize))")
                    }
                    
                    TextField("برومبت مخصّص للنظام (اختياري)", text: $settings.customPrompt, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                }
                
                // إستراتيجية تدوير المفاتيح
                Section(header: Text("إستراتيجية تدوير المفاتيح")) {
                    Picker("الطريقة", selection: $settings.apiKeyRetryStrategy) {
                        Text("تسلسلي").tag(APIKeyRetryStrategy.sequential)
                        Text("Round-Robin").tag(APIKeyRetryStrategy.roundRobin)
                    }
                    .pickerStyle(.segmented)
                }
                
                // مفاتيح Gemini
                Section(header: Text("مفاتيح Gemini")) {
                    ForEach($settings.geminiApiKeys) { $k in
                        HStack {
                            SecureField("مفتاح", text: $k.key)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Toggle("نشط", isOn: Binding(
                                get: { k.status == .active },
                                set: { k.status = $0 ? .active : .disabled }
                            ))
                            .labelsHidden()
                        }
                    }
                    Button("إضافة مفتاح") {
                        settings.geminiApiKeys.append(APIKeyEntry(key: ""))
                    }
                }
                
                // مفاتيح OpenRouter
                Section(header: Text("مفاتيح OpenRouter")) {
                    ForEach($settings.openrouterApiKeys) { $k in
                        HStack {
                            SecureField("مفتاح", text: $k.key)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Toggle("نشط", isOn: Binding(
                                get: { k.status == .active },
                                set: { k.status = $0 ? .active : .disabled }
                            ))
                            .labelsHidden()
                        }
                    }
                    Button("إضافة مفتاح") {
                        settings.openrouterApiKeys.append(APIKeyEntry(key: ""))
                    }
                }
                
                // مزوّدون مخصّصون (توافق OpenAI-style)
                Section(header: Text("مزودون مخصّصون")) {
                    if settings.customProviders.isEmpty {
                        Text("لم تُضِف أي مزوّد مخصّص بعد.")
                            .foregroundColor(.secondary)
                    }
                    ForEach($settings.customProviders) { $p in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("اسم المزود", text: $p.name)
                                .multilineTextAlignment(.trailing)
                            TextField("أساس الـAPI (URL)", text: Binding(
                                get: { p.baseUrl.absoluteString },
                                set: { newVal in
                                    if let u = URL(string: newVal.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                        p.baseUrl = u
                                    }
                                }
                            ))
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                            
                            Text("المفاتيح").font(.footnote).foregroundColor(.secondary)
                            ForEach($p.apiKeys) { $k in
                                HStack {
                                    SecureField("مفتاح", text: $k.key)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                    Toggle("نشط", isOn: Binding(
                                        get: { k.status == .active },
                                        set: { k.status = $0 ? .active : .disabled }
                                    ))
                                    .labelsHidden()
                                }
                            }
                            Button("إضافة مفتاح للمزوّد") {
                                p.apiKeys.append(APIKeyEntry(key: ""))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Button("إضافة مزود مخصّص") {
                        settings.customProviders.append(
                            CustomProvider(
                                id: "custom_\(UUID().uuidString.prefix(8))",
                                name: "مزود جديد",
                                baseUrl: URL(string: "https://api.example.com/v1")!,
                                models: [],
                                apiKeys: []
                            )
                        )
                    }
                }
            }
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                SettingsPersistence.shared.save(settings)
            }
        }
    }
    
    private func displayName(for p: Provider) -> String {
        switch p {
        case .gemini: return "Gemini"
        case .openrouter: return "OpenRouter"
        case .custom: return "Custom"
        }
    }
}
