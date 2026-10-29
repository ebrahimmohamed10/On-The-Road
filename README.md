# 🛣️ On the Road — على الطريق

> تطبيق جوال لمشاركة الرحلات وحجز المقاعد بين المدن في مصر  
> Built with **Flutter (Dart)** & **Supabase** • يدعم العربية (RTL) والإنجليزية (LTR) بالكامل مع الوضع الداكن والفاتح.

---

## 📱 مميزات التطبيق

- **15 شاشة مكتملة** متطابقة بدقة مع تصاميم Figma.
- **تبديل اللغات الفوري (AR / EN)**: دعم كامل للغة العربية (RTL) والإنجليزية (LTR) بزر تفاعلي في كل الشاشات.
- **الوضع الداكن والفاتح (Dark & Light Mode)** بنظام إدارة الحالة الحديث (Riverpod).
- **منطق حجز المقاطع (Segment-based Seat Booking)**: حجز مقاعد على أي جزء من الرحلة (مثال: القاهرة ← طنطا ← الإسكندرية).
- **توثيق أمان الهويات**:
  - رفع بطاقة الرقم القومي ورخصة القيادة.
  - إطار سيلفي حي للتحقق من تطابق الوجه.
- **حساب المقاعد التفاعلي**: رسم بياني لمقاعد السيارة واختيار المقاعد وحساب السعر التلقائي.

---

## 🛠️ التقنيات المستخدمة

- **Framework**: [Flutter](https://flutter.dev) (iOS, Android, Web, Windows)
- **Language**: [Dart](https://dart.dev)
- **State Management**: [Flutter Riverpod 3](https://riverpod.dev)
- **Navigation & Routing**: [GoRouter](https://pub.dev/packages/go_router)
- **Backend / Database**: [Supabase](https://supabase.com) (PostgreSQL, Auth, Storage, Realtime)
- **Fonts**: [Google Fonts (Cairo)](https://fonts.google.com/specimen/Cairo)

---

## 🚀 تشغيل المشروع محلياً

```bash
# 1. استنساخ المستودع
git clone https://github.com/YOUR_USERNAME/on-the-road.git
cd on-the-road

# 2. تحميل الحزم
flutter pub get

# 3. تشغيل التطبيق على المتصفح
flutter run -d chrome

# أو تشغيله على محاكي أندرويد
flutter run
```

---

## 📄 الترخيص
هذا المشروع خاص بـ **On The Road App**.
