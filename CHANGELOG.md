# Changelog

## 3.1.1 — Kira Plus Credit Badge Build Fix

- Fixed the Objective-C build error by replacing the Swift-only `children` property with UIKit's `childViewControllers` API.
- Removed the unused block-parameter warning in `WGTranslations.m`.
- No behavioral change to the draggable Kira Plus badge or Telegram link.

## 3.1.0 — Kira Plus Credit Badge

- يضيف شارة حقوق عائمة داخل صفحة **مميزات وايت كرام** فقط.
- تعرض `كيرا بلس` و`@iKiraPlus` مع علامة `K+` مدمجة دون ملفات صور خارجية.
- يمكن سحب الشارة وتحريكها، ويُحفظ موقعها تلقائياً.
- الضغط مرة واحدة يفتح حساب `@iKiraPlus` في تيليغرام، مع رابط ويب احتياطي.
- لا يعتمد على اعتراض كلاسات Whitegram الداخلية أو تغيير منطق تسجيل الدخول.

## 3.0.0 — NodeFix

- يصلح بقاء عناصر إعدادات Whitegram باللغة الإنجليزية.
- يضيف مترجماً مرئياً لعُقد AsyncDisplayKit/Texture التي لا تستخدم UIKit setters.
- يتعامل مع `ImmediateTextNode` و`ImmediateTextView` وواجهات `ComponentFlow.Text`.
- لا يعيد الاعتراض الواسع الذي تسبب بكرش تسجيل الدخول في الإصدار الأول.
- يضيف النصوص المختصرة الظاهرة في القائمة الرئيسية وصفحة Liquid Glass.
- يعيد فحص الواجهة عند ظهور الشاشة، وعند دخول عُقد Texture إلى النافذة، وعند العودة للتطبيق.
