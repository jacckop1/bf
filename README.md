# WhitegramArabic NodeFix v3

ديلب مستقل لتعريب قسم **Whitegram Features** في Whitegram 12.8 (55)، ومخصص للحقن داخل ملف IPA ثم إعادة توقيعه. لا يعتمد على Substrate أو ElleKit.

## لماذا بقيت الخيارات إنجليزية في Safe v2؟

صفحات Whitegram لا ترسم أغلب الصفوف بواسطة `UILabel`. التطبيق يستخدم عُقد Telegram المبنية على Texture / AsyncDisplayKit، وخصيصة النص فيها Swift وغير مكشوفة كدالة Objective-C باسم `setAttributedText:`. لذلك كانت النسخة السابقة تعرّب عنوان الصفحة فقط، بينما تبقى عناوين الصفوف ووصفها إنجليزية.

## ما الذي تغيّر في NodeFix v3؟

- الإبقاء على اعتراضات UIKit الآمنة للعناوين والتنبيهات وحقول البحث.
- فحص عُقد العرض المرئية فقط من `_ASDisplayView`.
- تعريب `ImmediateTextNode` و`ImmediateTextView` و`TextNodeWithEntities`.
- دعم النصوص المبنية بواسطة `ComponentFlow.Text`.
- إجبار العقدة المترجمة على إعادة التخطيط والرسم.
- عدم فحص جميع كلاسات التطبيق وعدم اعتراض مُنشئات `NSAttributedString`، وهي الطريقة التي سببت كرش تسجيل الدخول في النسخة الأولى.
- إضافة النصوص المختصرة الظاهرة في القائمة الرئيسية وصفحة Liquid Glass، إضافة إلى ترجمة حقل البحث الروسي الظاهر في بعض البنايات.

## حقوق كيرا بلس

يتضمن الإصدار 3.1.1 شارة عائمة تظهر فقط داخل صفحة **Whitegram Features / مميزات وايت كرام**:

- تعرض `كيرا بلس` و`@iKiraPlus`.
- قابلة للسحب، ويُحفظ آخر موقع لها.
- الضغط عليها يفتح `tg://resolve?domain=iKiraPlus` ثم ينتقل إلى `https://t.me/iKiraPlus` إذا تعذّر فتح مخطط تيليغرام.
- الشارة مرسومة بالكامل بالكود ولا تحتاج إلى صورة أو Resource إضافي.

يمكن تعديل الاسم واليوزر من الثوابت أعلى الملف:

`Sources/WGKiraBadge.m`

## التغطية

- 698 نصاً مستخرجاً ومطابقاً من Whitegram: مترجمة بنسبة 100%.
- قاموس البناء الكامل: 742 مدخلاً بعد إضافة النصوص المرئية الإضافية.
- أخطاء المتغيرات مثل `%@` و`%d`: صفر.

## البناء عبر GitHub Actions

1. ارفع محتويات هذا المجلد إلى جذر مستودع GitHub.
2. افتح تبويب **Actions**.
3. اختر **Build Whitegram Arabic Dylib**.
4. اضغط **Run workflow**.
5. نزّل Artifact باسم `WhitegramArabic-NodeFix-v3`.

سيحتوي على:

- `WhitegramArabic.dylib`
- `SHA256.txt`
- `coverage-report.txt`

## الحقن الصحيح

استخدم نسخة IPA أصلية ونظيفة، ولا تحقن v3 فوق IPA ما زال يحتوي على الديلب القديم.

ضع الديلب داخل:

`Payload/Telegram.app/Frameworks/WhitegramArabic.dylib`

ثم أضف تحميله إلى Mach-O الرئيسي باسم:

`@rpath/WhitegramArabic.dylib`

بعدها أعد توقيع التطبيق بالكامل. يجب ألا توجد إحالتان للديلب نفسه داخل `LC_LOAD_DYLIB`.

## التوافق

- Whitegram: 12.8 (55)
- Bundle ID المفحوص: `ph.telegra.Telegraph4`
- المعمارية: `arm64`
- الحد الأدنى: iOS 15
- لا توجد مكتبات خارجية مطلوبة

## تعديل الترجمات

عدّل:

`Resources/ar.json`

ثم شغّل:

```bash
python3 tools/verify_translations.py
python3 tools/generate_translations.py
```
