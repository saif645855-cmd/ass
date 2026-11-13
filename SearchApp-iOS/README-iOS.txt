بنك المعلومات - نسخة iOS (مبنية من النسخة 13)

على الـ Mac:
1) افتح SearchApp.xcodeproj في Xcode (15 أو أحدث).
2) من اليسار اضغط على المشروع SearchApp ثم Targets > SearchApp > Signing & Capabilities:
   - اختر Team (حساب Apple Developer حقك).
   - غيّر Bundle Identifier إلى معرّف خاص بك (مثلاً com.yourname.bankinfo).
3) اختر Any iOS Device (arm64) من أعلى.
4) Product > Archive.
5) من نافذة Organizer: Distribute App > Ad Hoc (أو Development) > Export.
   يطلع لك مجلد فيه ملف SearchApp.ipa جاهز للرفع على الاستضافة / متجر بلس.

ملاحظات:
- الواجهة كلها داخل SearchApp/www (نفس ملفات index.html القديمة). أي تعديل عليها يتم هناك.
- حفظ ملف الحزمة (.pack) يفتح نافذة المشاركة: اختر "حفظ في الملفات" أو أرسله مباشرة.
- الدخول بالبصمة/الوجه يستخدم Face ID أو Touch ID والسر يُحفظ في Keychain.
- نظام "تحديث الآن" القديم يفتح رابط APK، وهذا ما يفيد على iOS. عطّل UPD_URL أو بدّل الرابط برابط الـ IPA/المتجر.

--- بدون Mac (من لابتوب ويندوز) ---
1) أنشئ حساب GitHub ومستودع جديد (Private).
2) ارفع محتويات هذا المجلد كلها (يجب أن يكون .github في جذر المستودع).
3) تبويب Actions > Build IPA (unsigned) > Run workflow.
4) بعد ما يخلص (5-10 دقائق) نزّل SearchApp-ipa من Artifacts، فك الضغط يطلع SearchApp.ipa.
5) ارفعه في متجر بلس > توقيع تطبيقات خارجية.
