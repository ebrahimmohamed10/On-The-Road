# دالة قراءة البطاقة الشخصية المصرية (ocr-egyptian-id)

تعتمد هذه الدالة على **Google Cloud Vision API** لقراءة بيانات بطاقة الرقم القومي المصرية واستخراج:
- النص الكامل للبطاقة.
- الرقم القومي (14 رقم) والتحقق من صحة تاريخ الميلاد المدمج به.

---

## تنبيه مهم جداً ⚠️
> **نشر الكود على GitHub لا ينشر الوظيفة أو مفاتيح الـ API إلى Supabase تلقائياً.**
> يجب نشر الدالة يدويًا وإضافة المفتاح السري إلى مشروع Supabase إما من خلال لوحة تحكم الموقع (Dashboard) أو عبر Supabase CLI.

---

## الطريقة الأولى: عبر لوحة تحكم Supabase (بدون تثبيت أي أدوات)

### 1. إضافة المفتاح السري (Secret Key):
1. افتح مشروعك على [Supabase Dashboard](https://supabase.com/dashboard/project/chwbyhqcmxedhfezdmfi).
2. من القائمة الجانبية، توجّه إلى **Project Settings** (أيقونة الترس ⚙️) ثم اختر **Edge Functions** أو **Configuration -> Secrets**.
3. اضغط على **Add new secret** وأدخل:
   - **Name:** `GOOGLE_CLOUD_VISION_API_KEY`
   - **Value:** `<ضع هنا مفتاح الـ API الخاص بـ Google Cloud Vision>`
4. احفظ المفتاح.

---

## الطريقة الثانية: عبر Supabase CLI (سطر الأوامر)

### 1. تسجيل الدخول والربط بالمشروع:
```bash
# تسجيل الدخول
npx supabase login

# ربط المشروع المحلي بمشروع Supabase (Project ID: chwbyhqcmxedhfezdmfi)
npx supabase link --project-ref chwbyhqcmxedhfezdmfi
```

### 2. إضافة المفتاح السري (Secret Key):
```bash
npx supabase secrets set GOOGLE_CLOUD_VISION_API_KEY="YOUR_GOOGLE_CLOUD_VISION_API_KEY_HERE"
```

### 3. نشر الوظيفة (Deploy):
```bash
npx supabase functions deploy ocr-egyptian-id
```

### 4. التحقق من النشر:
```bash
# التأكد من ظهور الوظيفة ضمن القائمة وحالتها ACTIVE
npx supabase functions list

# التأكد من وجود المفتاح ضمن أسرار المشروع
npx supabase secrets list
```
