// =================================================================
// 1. التحميل اليدوي لمتغيرات البيئة (الحل الجذري)
// =================================================================
const fs = require('fs');
const path = require('path');

try {
    const envConfig = fs.readFileSync(path.join(__dirname, '.env'), 'utf8');
    envConfig.split('\n').forEach(line => {
        const [key, value] = line.split('=');
        if (key && value) {
            process.env[key.trim()] = value.trim();
        }
    });
    console.log('✅ Environment variables loaded manually.');
} catch (error) {
    // ✨ لا توقف الخادم، فقط اعرض تحذيرًا بأنه سيستخدم متغيرات البيئة من المنصة ✨
    console.warn('⚠️  Could not find .env file. Using platform environment variables instead.');
}


// =================================================================
// 2. استدعاء المكتبات المطلوبة
// =================================================================
const http = require('http' );
const https = require('https' );
const { GoogleGenerativeAI } = require('@google/generative-ai');
const express = require('express');
const { OAuth2Client } = require('google-auth-library');
const cors = require('cors'); // Import cors
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const User = require('./models/user.model.js');
const Chat = require('./models/chat.model.js');
const Settings = require('./models/settings.model.js');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const cloudinary = require('cloudinary').v2;

// =================================================================
// 3. إعداد تطبيق Express والخادم
// =================================================================
const app = express();
const server = http.createServer(app );

// ✨ إعدادات CORS النهائية والمحصّنة ✨
app.use(cors({
  origin: 'https://chatzeus.vercel.app', // السماح لواجهتك الأمامية فقط
  credentials: true, // السماح بإرسال الكوكيز والتوكن
  allowedHeaders: ['Content-Type', 'Authorization'] // السماح بالهيدرات الضرورية
} ));

// معالجة طلبات OPTIONS تلقائيًا (مهم لـ pre-flight)
app.options('*', cors({
  origin: 'https://chatzeus.vercel.app',
  credentials: true,
  allowedHeaders: ['Content-Type', 'Authorization']
} ));

const oauth2Client = new OAuth2Client(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    "https://chatzeus-production.up.railway.app/auth/google/callback"
  );

app.use(express.json({ limit: '50mb' }));

// ✨ تهيئة Cloudinary ✨

cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
    secure: true // استخدام HTTPS
});
console.log('✅ Cloudinary configured.');

// =================================================================
// 4. Middleware للتحقق من التوكن
// =================================================================
function verifyToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1]; // استخراج التوكن من 'Bearer TOKEN'

    if (token == null) {
        return res.status(401).json({ loggedIn: false, message: 'No token provided.' });
    }

    jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
        if (err) {
            return res.status(403).json({ loggedIn: false, message: 'Token is not valid.' });
        }
        req.user = user;
        next();
    });
}

// ✨ إزالة تهيئة مجلد الرفع المحلي (لم نعد نستخدمه) ✨
// const uploadsDir = path.join(__dirname, 'uploads');
// if (!fs.existsSync(uploadsDir)) {
//   fs.mkdirSync(uploadsDir, { recursive: true });
//   console.log('✅ Created uploads directory at:', uploadsDir);
// }

// إعداد التخزين لـ Multer - الآن في الذاكرة
const storage = multer.memoryStorage(); // ✨ تم التغيير هنا ✨

// فلترة بسيطة للأنواع المسموحة (اختياري — عدّل حسب حاجتك)
// أضف HEIC/HEIF وأنواع شائعة أخرى (PDF/SVG)، أو ألغِ الفلترة تمامًا إن أردت
const allowedMime = new Set([
  'text/plain','text/markdown','text/csv','application/json','application/xml',
  'text/html','text/css','application/javascript',
  'image/jpeg','image/png','image/gif','image/webp','image/bmp',
  'image/heic','image/heif','image/heif-sequence','image/svg+xml',
  'application/pdf'
]);

const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: (req, file, cb) => {
    // اسمح إن كان النوع معلوم أو يبدأ بـ image/
    if (allowedMime.has(file.mimetype) || (file.mimetype && file.mimetype.startsWith('image/'))) {
      return cb(null, true);
    }
    cb(new Error('نوع الملف غير مسموح: ' + file.mimetype));
  }
});

// ✨ إزالة خدمة الملفات المرفوعة بشكل ثابت (لم نعد نخدمها محليًا) ✨
// app.use('/uploads', express.static(uploadsDir));


// =================================================================
// 5. نقاط النهاية (Routes)
// =================================================================
// =================================================================
// مسار رفع الملفات (يرجع معلومات يمكن حفظها داخل الرسالة فقط)
// =================================================================
app.post('/api/uploads', verifyToken, upload.array('files', 10), async (req, res) => {
  try {
    const uploadedFilesInfo = [];
    
    for (const file of req.files) {
        const fileInfo = {
            originalName: file.originalname,
            filename: uuidv4(), // Generate a unique ID for internal tracking
            size: file.size,
            mimeType: file.mimetype,
            fileUrl: null, // هذا سيكون رابط Cloudinary أو placeholder
            dataType: null, // 'image', 'text', 'binary'
            content: null // للملفات النصية، تخزين المحتوى هنا
        };

        // التحقق مما إذا كانت صورة
        if (file.mimetype.startsWith('image/')) {
            fileInfo.dataType = 'image';
            try {
                // تحويل Buffer إلى Base64 Data URI للرفع إلى Cloudinary
                const b64 = Buffer.from(file.buffer).toString('base64');
                const dataUri = `data:${file.mimetype};base64,${b64}`;
                
                const isHeic = /image\/heic|image\/heif/i.test(file.mimetype);
const uploadResult = await cloudinary.uploader.upload(dataUri, {
  folder: 'chatzeus_uploads',
  public_id: fileInfo.filename,
  // اجعل Cloudinary يتصرف تلقائيًا، وحوّل HEIC إلى JPG ليكون مفهومًا للنماذج والمتصفحات
  resource_type: 'auto',
  format: isHeic ? 'jpg' : undefined
});
                fileInfo.fileUrl = uploadResult.secure_url;
                console.log(`✅ Uploaded image to Cloudinary: ${fileInfo.fileUrl}`);
            } catch (uploadError) {
                console.error('Cloudinary upload failed for image:', file.originalname, uploadError);
                fileInfo.fileUrl = null; // الإشارة إلى الفشل
                // يمكن هنا رمي خطأ أو الاستمرار وتسجيله
            }
        } else if (file.mimetype.startsWith('text/') || file.mimetype.includes('json') || file.mimetype.includes('xml') || file.mimetype.includes('javascript') || file.mimetype.includes('csv') || file.mimetype.includes('markdown')) {
            fileInfo.dataType = 'text';
            // للملفات النصية/الكود، تخزين المحتوى مباشرة (حسب "لا لاحقا")
            fileInfo.content = file.buffer.toString('utf8');
            // لا يوجد رفع خارجي للملفات النصية/الكود في الوقت الحالي
        } else {
            fileInfo.dataType = 'binary';
            // لا يوجد محتوى أو رفع خارجي للملفات الثنائية الأخرى في الوقت الحالي
        }
        uploadedFilesInfo.push(fileInfo);
    }

    return res.status(201).json({ files: uploadedFilesInfo });
  } catch (e) {
    console.error('Upload error:', e);
    return res.status(500).json({ message: 'فشل رفع الملفات', error: e.message });
  }
});

// معالج أخطاء multer ليعيد 400 بدلاً من 500 مع رسالة واضحة
app.use((err, req, res, next) => {
  if (err && err.message && /multer/i.test(err.stack || '') || /نوع الملف غير مسموح/i.test(err.message)) {
    console.error('Multer error:', err.message);
    return res.status(400).json({ message: err.message });
  }
  next(err);
});

app.get('/auth/google', (req, res) => {
    const authorizeUrl = oauth2Client.generateAuthUrl({
        access_type: 'offline',
        scope: 'https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email',
    } );
    res.redirect(authorizeUrl);
});

app.get('/auth/google/callback', async (req, res) => {
    try {
        const { code } = req.query;
        const { tokens } = await oauth2Client.getToken(code);
        oauth2Client.setCredentials(tokens);
        const userInfoResponse = await oauth2Client.request({ url: 'https://www.googleapis.com/oauth2/v3/userinfo' } );
        const userInfo = userInfoResponse.data;

        // ابحث عن المستخدم في قاعدة البيانات أو أنشئ مستخدمًا جديدًا
        let user = await User.findOne({ googleId: userInfo.sub });

        if (!user) {
            // مستخدم جديد
            user = new User({
                googleId: userInfo.sub, // .sub هو المعرف الفريد من جوجل
                email: userInfo.email,
                name: userInfo.name,
                picture: userInfo.picture,
            });
            await user.save();

            // إنشاء إعدادات افتراضية للمستخدم الجديد
            const newSettings = new Settings({ user: user._id });
            await newSettings.save();
            console.log(`✨ New user created and saved: ${user.email}`);
        } else {
            console.log(`👋 Welcome back, user: ${user.email}`);
        }

        // إنشاء حمولة التوكن مع معرّف قاعدة البيانات
        const payload = {
            id: user._id,
            googleId: user.googleId,
            name: user.name,
            email: user.email,
            picture: user.picture,
        };

        // توقيع التوكن
        const token = jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: '7d' });

        // إعادة التوجيه إلى الواجهة الأمامية مع التوكن
        res.redirect(`https://chatzeus.vercel.app/?token=${token}` );

    } catch (error) {
        console.error('Authentication callback error:', error);
        res.redirect('https://chatzeus.vercel.app/?auth_error=true' );
    }
});

app.get('/api/user', verifyToken, (req, res) => {
    // إذا وصل الطلب إلى هنا، فالـ middleware قد تحقق من التوكن بنجاح
    // ومعلومات المستخدم موجودة في req.user
    res.json({ loggedIn: true, user: req.user });
});

app.post('/api/chat', verifyToken, async (req, res) => {
    await handleChatRequest(req, res);
});

// =================================================================
// 🚩 مسار وضع الفريق (بث حي حقيقي — مع علامات BEGIN/END لكل متحدث)
// =================================================================
app.post('/api/team_chat', verifyToken, async (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/plain; charset=utf-8',
    'Transfer-Encoding': 'chunked'
  });

  try {
    // قراءة البيانات من chatHistory أو history
    const { chatHistory, history, settings } = req.body || {};
    const messages = chatHistory || history || [];
    
    if (!settings || !settings.team || !Array.isArray(settings.team.members) || settings.team.members.length === 0) {
      res.write('❌ لا يوجد أعضاء محددون في وضع الفريق.\n');
      return res.end();
    }

    const lastUser = [...messages].reverse().find(m => m.role === 'user')?.content || '';
    const shortContext = Array.isArray(messages) ? messages.slice(-10) : [];
    const teamThread = [];

    teamThread.push({
      role: 'system',
      content:
`أنت منسّق لفريق خبراء حقيقي. القواعد:
- النقاش تتابعي صارم: عضو واحد يتحدث ثم يتوقف ليرى التالي ردّه.
- كل عضو يرى كامل خيط الفريق حتى لحظته.
- احترم شخصية ودور كل عضو.
- الهدف: حلول عملية مختصرة مع كود/خطوات عند الحاجة.`
    });

    teamThread.push({
      role: 'user',
      content: `مهمة المستخدم:\n${lastUser}\n\nملخص الحوار الأخير:\n${JSON.stringify(shortContext)}`
    });

    const coord = settings.team.coordinator || {};

    // 2) خطة المنسّق
const coordName = coord.name || 'الوكيل';
const coordRole = coord.role || 'منسّق';
const coordPersona = coord.persona || '';

res.write(`⟦AGENT:BEGIN|${coordName}|${coordRole}⟧`);
await streamOneModel(
  coord.provider || 'gemini',
  coord.model || 'gemini-1.5-pro',
  [
    ...teamThread,
    {
      role: 'system',
      content: `المنسّق: ${coordName}\nالدور: ${coordRole}\n${coordPersona ? 'الوصف: ' + coordPersona : ''}`
    }
  ],
  settings,
  (text) => res.write(text)
);
res.write(`⟦AGENT:END⟧`);
    teamThread.push({ role: 'assistant', content: '(تم بث خطة المنسّق)' });

    // 3) الأعضاء
    for (const mem of settings.team.members) {
      const sysPersona = (mem.persona || mem.role)
        ? `شخصية العضو: ${mem.name || 'عضو'} — ${mem.role || ''}\n${mem.persona || ''}`
        : '';

      const memName = mem.name || 'عضو';
const memRole = mem.role || 'مشارك';
const memPersona = mem.persona || '';

res.write(`⟦AGENT:BEGIN|${memName}|${memRole}⟧`);
await streamOneModel(
  mem.provider || 'gemini',
  mem.model || 'gemini-1.5-flash',
  [
    ...teamThread,
    {
      role: 'system',
      content: `العضو: ${memName}\nالدور: ${memRole}\n${memPersona ? 'الوصف: ' + memPersona : ''}`
    }
  ],
  settings,
  (text) => res.write(text)
);
res.write(`⟦AGENT:END⟧`);
      teamThread.push({ role: 'assistant', content: `(تم بث رد ${mem.name || 'عضو'})` });
    }

    // 4) خلاصة المنسّق
    res.write(`⟦AGENT:BEGIN|${coordName}|خلاصة⟧`);
await streamOneModel(
  coord.provider || 'gemini',
  coord.model || 'gemini-1.5-pro',
  [
    ...teamThread,
    {
      role: 'system',
      content: `المطلوب: خلاصة نهائية من ${coordName} (${coordRole})\nالتعليمات: لخّص مخرجات الفريق في نقاط تنفيذية موجزة، مع أي كود/أوامر لازمة.`
    }
  ],
  settings,
  (text) => res.write(text)
);
res.write(`⟦AGENT:END⟧`);

    res.end();
  } catch (e) {
    console.error('team_chat (live stream) error:', e);
    try { res.write(`\n❌ خطأ: ${e.message || 'Team mode failed'}`); } catch(_) {}
    res.end();
  }
});

// =================================================================
// ✨ نقاط نهاية جديدة للبيانات (تضاف في القسم 5)
// =================================================================

app.get('/api/data', verifyToken, async (req, res) => {
    try {
        // 1. التحقق من صلاحية الـ ID في التوكن
        if (!req.user || !req.user.id || !mongoose.Types.ObjectId.isValid(req.user.id)) {
            return res.status(400).json({ message: 'Invalid or missing user ID in token.' });
        }

        let user = await User.findById(req.user.id);

        // 2. خطة احتياطية: إذا لم يتم العثور على المستخدم بالـ ID، جرب googleId
        if (!user && req.user.googleId) {
            console.warn(`User not found by ID ${req.user.id}, trying googleId...`);
            user = await User.findOne({ googleId: req.user.googleId });

            // 3. إذا لم يكن موجودًا على الإطلاق، أنشئه الآن (هذا يمنع أي فشل)
            if (!user) {
                console.warn(`User not found by googleId either. Creating a new user record now.`);
                user = await User.create({
                    _id: req.user.id, // استخدم نفس الـ ID من التوكن لضمان التوافق
                    googleId: req.user.googleId,
                    email: req.user.email,
                    name: req.user.name,
                    picture: req.user.picture,
                });
            }
        }
        
        // إذا لم يتم العثور على المستخدم بعد كل المحاولات، فهناك مشكلة حقيقية
        if (!user) {
             return res.status(404).json({ message: 'User could not be found or created.' });
        }

        // 4. الآن بعد التأكد من وجود المستخدم، اجلب بياناته
                const filter = { user: user._id };
        if (req.query.mode) filter.mode = req.query.mode; // 🚩 فلترة اختيارية حسب الوضع

        const chats = await Chat.find(filter).sort({ order: -1 });
        let settings = await Settings.findOne({ user: user._id });

        // 5. إذا لم تكن لديه إعدادات، أنشئها
        if (!settings) {
            settings = await new Settings({ user: user._id }).save();
        }

        // 6. أرجع دائمًا ردًا ناجحًا
        return res.json({
            settings,
            chats,
            user: { id: user._id, name: user.name, picture: user.picture, email: user.email }
        });

    } catch (e) {
        console.error('FATAL Error in /api/data:', e);
        return res.status(500).json({ message: 'Failed to fetch user data.', error: e.message });
    }
});

// ====== دالة تطبيع الرسائل قبل الحفظ ======
function sanitizeChatForSave(chatData) {
  const out = { ...chatData };

  // طبّع الرسائل فقط إن كانت مصفوفة
  if (Array.isArray(out.messages)) {
    out.messages = out.messages.map(m => {
      const msg = { ...m };

      // 1) احرص أن المحتوى نص
      if (msg.content != null && typeof msg.content !== 'string') {
        msg.content = String(msg.content);
      }

      // 2) حوّل attachments إلى [string]
      if (Array.isArray(msg.attachments)) {
        msg.attachments = msg.attachments
          .map(a => {
            if (typeof a === 'string') return a.trim();
            if (a && typeof a === 'object') {
              return a.fileUrl || a.fileId || a.url || a.name || '';
            }
            return '';
          })
          .filter(Boolean); // أزل الفارغ
      } else {
        msg.attachments = []; // المخطط يتوقع مصفوفة
      }

      return msg;
    });
  }

  return out;
}

// حفظ أو تحديث محادثة
app.post('/api/chats', verifyToken, async (req, res) => {
  try {
    const userIdString = req.user.id;
    if (!mongoose.Types.ObjectId.isValid(userIdString)) {
      return res.status(400).json({ message: 'Invalid User ID format.' });
    }
    const userId = new mongoose.Types.ObjectId(userIdString);

    // ✅ طهّر الداتا قبل أي حفظ/تحديث
    const chatDataRaw = req.body;
    const chatData = sanitizeChatForSave(chatDataRaw);

    // إذا كانت المحادثة موجودة (لديها ID صالح)
    if (chatData._id && mongoose.Types.ObjectId.isValid(chatData._id)) {
      const { _id, ...rest } = chatData;         // ❗️لا تمرّر _id في التحديث
      const updatedChat = await Chat.findOneAndUpdate(
        { _id: new mongoose.Types.ObjectId(_id), user: userId },
        { $set: { ...rest, user: userId } },     // الآن rest.messages.attachments هي [string]
        { new: true, runValidators: true }
      );
      if (!updatedChat) {
        return res.status(404).json({ message: "Chat not found or user not authorized" });
      }
      return res.json(updatedChat);
    } else {
      // إنشاء جديد
      delete chatData._id;
      const newChat = new Chat({
        ...chatData,
        user: userId,
        mode: chatData.mode || 'chat'
      });
      await newChat.save();
      return res.status(201).json(newChat);
    }
  } catch (error) {
    console.error('Error saving chat:', error);
    res.status(500).json({ message: 'Failed to save chat' });
  }
});

app.put('/api/settings', verifyToken, async (req, res) => {
    try {
        if (!req.user || !req.user.id || !mongoose.Types.ObjectId.isValid(req.user.id)) {
            return res.status(400).json({ message: 'Invalid or missing user ID in token.' });
        }
        const userId = new mongoose.Types.ObjectId(req.user.id);
        const receivedSettings = req.body;

// ✨✨✨ الإصلاح الحاسم: انتقاء الحقول المعروفة فقط ✨✨✨
const allowedUpdates = {
    provider: receivedSettings.provider,
    model: receivedSettings.model,
    temperature: receivedSettings.temperature,
    customPrompt: receivedSettings.customPrompt,
    apiKeyRetryStrategy: receivedSettings.apiKeyRetryStrategy,
    fontSize: receivedSettings.fontSize,
    theme: receivedSettings.theme,
    geminiApiKeys: receivedSettings.geminiApiKeys,
    openrouterApiKeys: receivedSettings.openrouterApiKeys,
    customProviders: receivedSettings.customProviders,
    customModels: receivedSettings.customModels,
    // ✨ إعدادات البحث الجديدة ✨
    enableWebBrowsing: receivedSettings.enableWebBrowsing,
    browsingMode: receivedSettings.browsingMode,
    showSources: receivedSettings.showSources,
    dynamicThreshold: receivedSettings.dynamicThreshold,
    // 🚩 إعدادات وضع الفريق
    activeMode: receivedSettings.activeMode,
    team: receivedSettings.team
};

        // إزالة أي حقول غير معرفة (undefined) لتجنب المشاكل
        Object.keys(allowedUpdates).forEach(key => allowedUpdates[key] === undefined && delete allowedUpdates[key]);

        const updatedSettings = await Settings.findOneAndUpdate(
            { user: userId },
            { $set: allowedUpdates }, // استخدام $set لتحديث الحقول المحددة فقط
            { new: true, upsert: true, runValidators: false }
        );

        res.json(updatedSettings);

    } catch (error) {
        console.error('Error updating settings:', error);
        // إرسال رسالة خطأ أكثر تفصيلاً للمساعدة في التشخيص
        res.status(500).json({ message: 'Failed to update settings.', error: error.message });
    }
});

// حذف محادثة
app.delete('/api/chats/:chatId', verifyToken, async (req, res) => {
    try {
        const userIdString = req.user.id;
        const { chatId } = req.params;

        // ✨ 1. التحقق من صلاحية كلا المعرّفين قبل أي شيء ✨
        if (!mongoose.Types.ObjectId.isValid(userIdString) || !mongoose.Types.ObjectId.isValid(chatId)) {
            return res.status(400).json({ message: 'Invalid ID format.' });
        }

        // ✨ 2. استخدام المعرّفات المحوّلة والصحيحة في الاستعلام ✨
        const result = await Chat.findOneAndDelete({ 
            _id: new mongoose.Types.ObjectId(chatId), 
            user: new mongoose.Types.ObjectId(userIdString) 
        });

        if (!result) {
            // هذا يعني أن المحادثة غير موجودة أو لا تخص هذا المستخدم
            return res.status(404).json({ message: 'Chat not found or user not authorized' });
        }

        res.status(200).json({ message: 'Chat deleted successfully' });
    } catch (error) {
        console.error('Error deleting chat:', error);
        res.status(500).json({ message: 'Failed to delete chat' });
    }
});

// =================================================================
// 5. عرض الملفات الثابتة
// =================================================================
app.use(express.static(path.join(__dirname, '..', 'frontend')));

// مسار للصفحة الرئيسية فقط (بدلاً من * التي تسبب تضارب)
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, '..', 'frontend', 'index.html'));
});


// =================================================================
// 6. دوال معالجة الدردشة (تبقى كما هي)
// =================================================================
const keyManager = {
    keys: {
        gemini: (process.env.GEMINI_API_KEYS || '').split(',').filter(k => k),
        openrouter: (process.env.OPENROUTER_API_KEYS || '').split(',').filter(k => k)
    },
    // هذا المتغير سيتتبع المفتاح التالي الذي يجب استخدامه لكل مزود
    indices: {
        gemini: 0,
        openrouter: 0
    },

    tryKeys: async function(provider, strategy, customKeys, action) {
    const keyPool = (customKeys && customKeys.length > 0) ? customKeys : this.keys[provider] || [];
    if (keyPool.length === 0) {
        throw new Error(`No API keys available for provider: ${provider}`);
    }

    let tryCount = 0; // ✨ تعريف tryCount هنا
    while (tryCount < keyPool.length) { // ✨ حلقة while بدل continue خارج الحلقة
        const keyIndex = (this.indices[provider] || 0);
        const keyToTry = keyPool[keyIndex];
        console.log(`[Key Manager] Load Balancing: Selected key index ${keyIndex} for provider ${provider}.`);

        try {
            const result = await action(keyToTry);
            this.indices[provider] = (keyIndex + 1) % keyPool.length;
            return result;
        } catch (error) {
            console.error(`[Key Manager] Key index ${keyIndex} for ${provider} failed. Error: ${error.message}`);
            this.indices[provider] = (keyIndex + 1) % keyPool.length;

            const msg = String(error && (error.message || error.toString()) || '');
            const retriable = /429|Too\s*Many\s*Requests|quota|rate\s*limit|5\d\d|ECONNRESET|ETIMEDOUT|network/i.test(msg);

            if (retriable && tryCount < keyPool.length - 1) {
                tryCount++;
                continue; // ✅ الآن في مكان صحيح داخل الحلقة
            }

            throw error;
        }
    }
}
};

async function handleChatRequest(req, res) {
    try {
        const payload = req.body;
        // ✨ التحقق من وجود الإعدادات والمزود قبل أي شيء آخر ✨
        if (!payload.settings || !payload.settings.provider) {
            // إذا لم يكن هناك مزود، أرسل خطأ واضحًا بدلاً من الانهيار
            throw new Error('Provider information is missing in the request settings.');
        }
        const { provider } = payload.settings;

        // الآن يمكننا استخدام 'provider' بأمان
        if (provider === 'gemini') await handleGeminiRequest(payload, res);
        else if (provider === 'openrouter') await handleOpenRouterRequest(payload, res);
        else if (provider.startsWith('custom_')) await handleCustomProviderRequest(payload, res);
        else throw new Error(`مزود غير معروف: ${provider}`);
        
    } catch (error) {
        console.error('Error processing chat request:', error.message);
        res.status(500).json({ error: error.message });
    }
}
// =================================================================
// إصلاح شامل لدعم البحث في Gemini 2.5
// =================================================================

async function handleGeminiRequest(payload, res) {
    const { chatHistory, attachments, settings, meta } = payload;
    const userApiKeys = (settings.geminiApiKeys || []).map(k => k.key).filter(Boolean);

    await keyManager.tryKeys('gemini', settings.apiKeyRetryStrategy, userApiKeys, async (apiKey) => {
        const genAI = new GoogleGenerativeAI(apiKey);

        // ✅ تفعيل البحث إذا كان مفعّل بالإعدادات أو مفروض من الرسالة
        const triggerByUser = meta && meta.forceWebBrowsing === true;
const useSearch = (settings.enableWebBrowsing === true || triggerByUser)
                  && (settings.browsingMode || 'gemini') === 'gemini';

        console.log(`🔍 Search Debug:`, {
          enableWebBrowse: settings.enableWebBrowse,
          triggerByUser,
          useSearch,
          model: settings.model
        });

        // ✅ النماذج المدعومة للبحث (محدثة)
        const searchSupportedModels = [
          'gemini-1.5-flash', 
          'gemini-1.5-pro',
          'gemini-2.5-flash',
          'gemini-2.5-pro',
          'gemini-2.0-flash'
        ];

        let chosenModel = settings.model || 'gemini-1.5-flash';

        // ✅ التحقق من دعم النموذج للبحث
        if (useSearch && !searchSupportedModels.includes(chosenModel)) {
          console.log(`⚠️ Model ${chosenModel} doesn't support search, falling back to gemini-1.5-flash`);
          chosenModel = 'gemini-1.5-flash';
        }

        console.log(`🤖 Using model: ${chosenModel} with search: ${useSearch}`);

        // 🚨 الإصلاح الحاسم: لا تستخدم apiVersion مطلقاً مع البحث
        let model;
if (useSearch) {
  // بدون apiVersion أثناء البحث
  model = genAI.getGenerativeModel({ model: chosenModel });
  console.log('🔍 Gemini model initialized for search (no apiVersion)');
} else {
  // apiVersion كوسيط ثانٍ
  model = genAI.getGenerativeModel(
    { model: chosenModel },
    { apiVersion: "v1beta" }
  );
}

        // ✅ إعداد أدوات البحث المحسنة
        let tools = undefined;
        if (useSearch) {
          const dynThreshold = typeof settings.dynamicThreshold === 'number' 
            ? Math.max(0, Math.min(1, settings.dynamicThreshold)) 
            : 0.6;
            
          // ✨✨✨ الإضافة المقترحة للتوافق مع النماذج الجديدة ✨✨✨
          const isLegacyModel = chosenModel.startsWith('gemini-1.5') || chosenModel.startsWith('gemini-2.0');
          
          if (isLegacyModel) {
              tools = [{
                googleSearchRetrieval: {
                  dynamicRetrievalConfig: {
                    mode: "MODE_DYNAMIC",
                    dynamicThreshold: dynThreshold
                  }
                }
              }];
          } else {
              tools = [{
                  googleSearch: {}
              }];
          }
          // ✨✨✨ نهاية الإضافة ✨✨✨

          console.log(`🎯 Search tools configured with threshold: ${dynThreshold}`);
        }

// تجهيز السجل بصيغة contents مع إضافة البرومبت المخصص
        const contents = [];
        
        // إضافة البرومبت المخصص في البداية إذا كان موجوداً
        if (settings.customPrompt && settings.customPrompt.trim()) {
            contents.push({
                role: 'user',
                parts: [{ text: settings.customPrompt }]
            });
            contents.push({
                role: 'model',
                parts: [{ text: 'مفهوم، سأتبع هذه التعليمات في جميع ردودي.' }]
            });
        }
        
        // إضافة المحادثات السابقة
        contents.push(...chatHistory.slice(0, -1).map(msg => ({
            role: msg.role === 'user' ? 'user' : 'model',
            parts: [{ text: msg.content || '' }]
        })));
        
        // إضافة الرسالة الأخيرة مع المرفقات
        contents.push({ role: 'user', parts: buildUserParts(chatHistory[chatHistory.length - 1], attachments) });

        // ✅ إعداد الطلب النهائي
        const requestConfig = {
          contents,
          generationConfig: { 
            temperature: settings.temperature || 0.7,
            maxOutputTokens: 8192 // زيادة الحد الأقصى
          }
        };

        // ✅ أضف الأدوات فقط عند البحث
        if (useSearch && tools) {
          requestConfig.tools = tools;
          console.log('🔍 Search tools added to request');
        }

        try {
          console.log('📤 Sending request to Gemini...');
          const result = await model.generateContentStream(requestConfig);

          // بث الرد
          res.writeHead(200, {
            'Content-Type': 'text/plain; charset=utf-8',
            'Transfer-Encoding': 'chunked'
          });

          let totalText = '';
          for await (const chunk of result.stream) {
            const text = chunk.text();
            if (text) {
              totalText += text;
              res.write(text);
            }
          }

          console.log(`✅ Response generated successfully (${totalText.length} chars)`);
          
          // إضافة سياق البحث للرد إذا تم استخدام البحث
          if (useSearch) {
            totalText = `[تم البحث في الويب للحصول على أحدث المعلومات]\n\n${totalText}`;
          }

          // ✅ إلحاق المصادر مع معالجة محسنة
          if (useSearch && settings.showSources) {
            try {
              console.log('🔍 Extracting search sources...');
              const finalResp = await result.response;
              const candidate = finalResp?.candidates?.[0];
              const gm = candidate?.groundingMetadata;
              
              console.log('📊 Grounding metadata:', JSON.stringify(gm, null, 2));
              
              const sources = [];

              // استخراج المصادر من citations
              if (Array.isArray(gm?.citations)) {
                console.log(`📚 Found ${gm.citations.length} citations`);
                gm.citations.forEach((citation, i) => {
                  const uri = citation?.uri || citation?.sourceUri || citation?.source?.uri;
                  let title = citation?.title || citation?.sourceTitle || citation?.source?.title;
                  
                  // تنظيف العنوان وتقصيره إذا كان طويلاً
                  if (title && title.length > 80) {
                    title = title.substring(0, 77) + '...';
                  }
                  if (!title) title = `مصدر ${i + 1}`;
                  
                  if (uri && uri.startsWith('http')) {
                    sources.push(`- [${title}](${uri})`);
                  }
                });
              }

              // استخراج من groundingChunks كبديل
              if (sources.length === 0 && Array.isArray(gm?.groundingChunks)) {
                console.log(`🌐 Found ${gm.groundingChunks.length} grounding chunks`);
                gm.groundingChunks.forEach((chunk, i) => {
                  const uri = chunk?.web?.uri || chunk?.source?.uri;
                  let title = chunk?.web?.title || chunk?.title || chunk?.source?.title;
                  
                  // تنظيف العنوان وتقصيره إذا كان طويلاً
                  if (title && title.length > 80) {
                    title = title.substring(0, 77) + '...';
                  }
                  if (!title) title = `مصدر ${i + 1}`;
                  
                  if (uri && uri.startsWith('http')) {
                    sources.push(`- [${title}](${uri})`);
                  }
                });
              }
              
              // استخراج من أي هياكل أخرى محتملة
              if (sources.length === 0 && gm?.searchEntryPoints) {
                console.log(`🎯 Found search entry points`);
                gm.searchEntryPoints.forEach((entry, i) => {
                  if (entry?.renderedContent && entry.url) {
                    const title = entry.title || `نتيجة البحث ${i + 1}`;
                    sources.push(`- [${title}](${entry.url})`);
                  }
                });
              }

              // استخراج من groundingChunks كبديل
              if (sources.length === 0 && Array.isArray(gm?.groundingChunks)) {
                console.log(`🌐 Found ${gm.groundingChunks.length} grounding chunks`);
                gm.groundingChunks.forEach((chunk, i) => {
                  const uri = chunk?.web?.uri || chunk?.source?.uri;
                  const title = chunk?.web?.title || chunk?.title || `مصدر ${i + 1}`;
                  if (uri) {
                    sources.push(`- [${title}](${uri})`);
                  }
                });
              }

              // عرض المصادر
              if (sources.length > 0) {
                console.log(`✅ Found ${sources.length} sources`);
                res.write(`\n\n**🔍 المصادر:**\n${sources.join('\n')}`);
              } else {
                console.log('⚠️ No sources found in response metadata');
                // تشخيص إضافي
                if (gm) {
                  console.log('🔍 Available grounding metadata keys:', Object.keys(gm));
                } else {
                  console.log('❌ No grounding metadata found');
                }
              }

            } catch (sourceError) {
              console.error('❌ Error extracting sources:', sourceError.message);
              res.write('\n\n*تعذر استخراج المصادر*');
            }
          }

          res.end();

        } catch (requestError) {
          console.error('❌ Gemini request failed:', requestError.message);
          
          // معالجة أخطاء محددة
          if (requestError.message.includes('Search Grounding is not supported')) {
            console.log('🔄 Retrying without search tools...');
            // إعادة المحاولة بدون البحث
            const fallbackConfig = {
              contents,
              generationConfig: { temperature: settings.temperature || 0.7 }
            };
            
            const fallbackResult = await model.generateContentStream(fallbackConfig);
            res.writeHead(200, {
              'Content-Type': 'text/plain; charset=utf-8',
              'Transfer-Encoding': 'chunked'
            });
            
            for await (const chunk of fallbackResult.stream) {
              const text = chunk.text();
              if (text) res.write(text);
            }
            
            res.write('\n\n*ملاحظة: تم تعطيل البحث مؤقتاً لهذا الطلب*');
            res.end();
          } else {
            throw requestError;
          }
        }
    });
}


async function handleOpenRouterRequest(payload, res) {
    const { chatHistory, settings } = payload;
    // ✨✨✨ الإصلاح هنا: استخراج مفاتيح المستخدم من الإعدادات ✨✨✨
    const userApiKeys = (settings.openrouterApiKeys || []).map(k => k.key).filter(Boolean);

    await keyManager.tryKeys('openrouter', settings.apiKeyRetryStrategy, userApiKeys, async (apiKey) => {
        const formattedMessages = formatMessagesForOpenAI(chatHistory);
        const requestBody = JSON.stringify({ model: settings.model, messages: formattedMessages, temperature: settings.temperature, stream: true });
        const options = { hostname: 'openrouter.ai', path: '/api/v1/chat/completions', method: 'POST', headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' } };
        await streamOpenAICompatibleAPI(options, requestBody, res);
    });
}
async function handleCustomProviderRequest(payload, res) {
    const { chatHistory, settings, customProviders } = payload;
    const providerId = settings.provider;
    const providerConfig = customProviders.find(p => p.id === providerId);
    if (!providerConfig) throw new Error(`لم يتم العثور على إعدادات المزود المخصص: ${providerId}`);
    const customKeys = (providerConfig.apiKeys || []).map(k => k.key).filter(Boolean);
    await keyManager.tryKeys(providerId, settings.apiKeyRetryStrategy, customKeys, async (apiKey) => {
        const formattedMessages = formatMessagesForOpenAI(chatHistory);
        const requestBody = JSON.stringify({ model: settings.model, messages: formattedMessages, temperature: settings.temperature, stream: true });
        const url = new URL(providerConfig.baseUrl);
        const options = { hostname: url.hostname, path: url.pathname, method: 'POST', headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' } };
        await streamOpenAICompatibleAPI(options, requestBody, res);
    });
}
function buildUserParts(lastMessage, attachments) {
    const userParts = [];
    if (lastMessage.content) userParts.push({ text: lastMessage.content });
    
    if (attachments) {
        attachments.forEach(file => {
            if (file.dataType === 'image' && file.fileUrl) { // ✨ استخدام file.fileUrl للصور
                userParts.push({ fileData: { mimeType: file.mimeType, fileUri: file.fileUrl } });
            } else if (file.dataType === 'text' && file.content) {
                userParts.push({ text: `\n\n--- محتوى الملف: ${file.name} ---\n${file.content}\n--- نهاية الملف ---` });
            } 
            // ✨ إزالة الجزء القديم الذي كان يتعامل مع file.fileUrl كـ text
            // هذا الجزء لم يعد ضرورياً لأننا نستخدم fileData للصور
            // أما الملفات النصية، فنحن نقرأ المحتوى مباشرة (file.content)
            // إذا كان هناك أي نوع ملف آخر (binary) لم تتم معالجته، يمكن إهماله حالياً أو التعامل معه لاحقاً.
        });
    }
    
    // هذا الشرط يضيف "حلل المرفقات:" فقط إذا كانت هناك مرفقات وليس هناك نص أساسي
    // مع التغييرات، قد لا يكون ضرورياً جداً إذا كان النموذج ذكياً بما يكفي
    // ولكن لا بأس من إبقائه كطبقة أمان
    if (userParts.length > 0 && userParts.every(p => !p.text)) {
        userParts.unshift({ text: "حلل المرفقات:" });
    }
    return userParts;
}


// إضافة دالة مساعدة لتنسيق حجم الملف
function formatBytes(bytes, decimals = 2) {
    if (bytes === 0) return '0 بايت';
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['بايت', 'ك.ب', 'م.ب', 'ج.ب', 'ت.ب'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

function formatMessagesForOpenAI(chatHistory) {
    return chatHistory.map(msg => ({ role: msg.role, content: msg.content || '' }));
}

// =================================================================
// 🎧 دالة موحّدة لبث ردّ نموذج واحد لحظيًا إلى كاتب خارجي (onToken)
// =================================================================
async function streamOneModel(provider, model, messages, settings, onToken) {
  const apiKeyStrategy = settings?.apiKeyRetryStrategy || 'sequential';

  if (provider === 'gemini') {
    const userKeys = (settings.geminiApiKeys || []).map(k => k.key).filter(Boolean);
    return await keyManager.tryKeys('gemini', apiKeyStrategy, userKeys, async (apiKey) => {
      const genAI = new GoogleGenerativeAI(apiKey);

      // Gemini لا يدعم role=system مباشرة — نطوّعها كـ user
      const contents = messages.map(m => ({
        role: m.role === 'user' ? 'user' : (m.role === 'system' ? 'user' : 'model'),
        parts: [{ text: m.content || '' }]
      }));

      // تهيئة الموديل والبث
      const gm = genAI.getGenerativeModel({ model });
      const result = await gm.generateContentStream({
        contents,
        generationConfig: { temperature: settings.temperature || 0.7 }
      });

      for await (const chunk of result.stream) {
        const text = typeof chunk.text === 'function' ? chunk.text() : (chunk?.candidates?.[0]?.content?.parts?.[0]?.text || '');
        if (text) onToken(text);
      }
    });
  }

  if (provider === 'openrouter') {
    const userKeys = (settings.openrouterApiKeys || []).map(k => k.key).filter(Boolean);
    return await keyManager.tryKeys('openrouter', apiKeyStrategy, userKeys, async (apiKey) => {
      // صيغة OpenAI-compatible
      const formatted = messages.map(m => {
        let role = m.role;
        if (role !== 'system' && role !== 'user' && role !== 'assistant') {
          role = (m.role === 'model') ? 'assistant' : 'user';
        }
        return { role, content: m.content || '' };
      });

      const body = JSON.stringify({
        model,
        messages: formatted,
        temperature: settings.temperature || 0.7,
        stream: true
      });

      const options = {
        hostname: 'openrouter.ai',
        path: '/api/v1/chat/completions',
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json'
        }
      };

      await streamOpenAIToWriter(options, body, onToken);
    });
  }

  // مزود مخصّص (OpenAI-compatible)
  if (provider && provider.startsWith('custom_') && Array.isArray(settings?.customProviders)) {
    const prov = settings.customProviders.find(p => p.id === provider);
    if (!prov) throw new Error(`لم يتم العثور على المزود المخصص: ${provider}`);
    const customKeys = (prov.apiKeys || []).map(k => k.key).filter(Boolean);

    return await keyManager.tryKeys(provider, apiKeyStrategy, customKeys, async (apiKey) => {
      const formatted = messages.map(m => {
        let role = m.role;
        if (role !== 'system' && role !== 'user' && role !== 'assistant') {
          role = (m.role === 'model') ? 'assistant' : 'user';
        }
        return { role, content: m.content || '' };
      });

      const url = new URL(prov.baseUrl);
      const body = JSON.stringify({ model, messages: formatted, temperature: settings.temperature || 0.7, stream: true });
      const options = {
        hostname: url.hostname,
        path: url.pathname + (url.search || ''),
        method: 'POST',
        headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' }
      };

      await streamOpenAIToWriter(options, body, onToken);
    });
  }

  throw new Error(`مزود غير مدعوم للبث الحي: ${provider}`);
}

// =================================================================
// 🧩 مُحوّل بث OpenAI-compatible إلى كاتب خارجي (Callback)
// =================================================================
function streamOpenAIToWriter(options, body, onToken) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (apiRes) => {
      if (apiRes.statusCode !== 200) {
        let errorBody = '';
        apiRes.on('data', d => errorBody += d);
        apiRes.on('end', () => reject(new Error(`API Error: ${apiRes.statusCode} - ${errorBody}`)));
        return;
      }
      let buffer = '';
      apiRes.on('data', (chunk) => {
        buffer += chunk.toString('utf8');
        const parts = buffer.split('\n');
        buffer = parts.pop(); // أبقِ آخر سطر غير مكتمل
        for (const line of parts) {
          const s = line.trim();
          if (!s || !s.startsWith('data:')) continue;
          const data = s.slice(5).trim();
          if (data === '[DONE]') continue;
          try {
            const parsed = JSON.parse(data);
            const text = parsed?.choices?.[0]?.delta?.content || '';
            if (text) onToken(text);
          } catch (_e) { /* تجاهل */ }
        }
      });
      apiRes.on('end', () => resolve());
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function streamOpenAICompatibleAPI(options, body, res) {
    return new Promise((resolve, reject) => {
        const request = https.request(options, (apiResponse ) => {
            if (apiResponse.statusCode !== 200) {
                let errorBody = '';
                apiResponse.on('data', d => errorBody += d);
                apiResponse.on('end', () => reject(new Error(`API Error: ${apiResponse.statusCode} - ${errorBody}`)));
                return;
            }
            res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Transfer-Encoding': 'chunked' });
            apiResponse.on('data', (chunk) => {
                const lines = chunk.toString().split('\n');
                for (const line of lines) {
                    if (line.startsWith('data: ')) {
                        const data = line.slice(6);
                        if (data.trim() === '[DONE]') continue;
                        try {
                            const parsed = JSON.parse(data);
                            const text = parsed.choices?.[0]?.delta?.content || '';
                            if (text) res.write(text);
                        } catch (e) {}
                    }
                }
            });
            apiResponse.on('end', () => { res.end(); resolve(); });
        });
        request.on('error', reject);
        request.write(body);
        request.end();
    });
}

// ✨✨✨ معالج الأخطاء العام (Global Error Handler) ✨✨✨
app.use((err, req, res, next) => {
    console.error('[GLOBAL ERROR HANDLER]:', err.stack);
    res.status(500).json({
        message: 'حدث خطأ غير متوقع في الخادم.',
        error: err.message 
    });
});


// =================================================================
// ✨ الاتصال بقاعدة البيانات
// =================================================================
mongoose.connect(process.env.MONGODB_URI)
    .then(() => console.log('✅ Successfully connected to MongoDB Atlas.'))
    .catch(err => {
        console.error('❌ Could not connect to MongoDB Atlas.', err);
        process.exit(1); // إيقاف الخادم إذا فشل الاتصال
    });

// =================================================================
// 7. تشغيل الخادم
// =================================================================
const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`✅ Zeus Pro Server (Manual Env) is now running on http://0.0.0.0:${PORT}` );
});
