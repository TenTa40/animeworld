# جزیره‌ی آرام (نمونه‌ی اولیه‌ی دنیای باز انیمه‌ای)

نمونه‌ی کوچیک Godot 4.3 (GL Compatibility): جزیره‌ی procedural با cel-shading و خط دور، دوربین سوم‌شخص،
جمع کردن باتری، زامبی‌ها و حمله.

- کنترل موبایل: جوی‌استیک چپ، کشیدن انگشت روی سمت راست برای دوربین، دکمه‌ی پرش و حمله.
- دسکتاپ: WASD، Space، J یا F برای حمله، کلیدهای جهت برای دوربین (ماوس هم لمس رو شبیه‌سازی می‌کنه).
- بیلد APK: هر push روی `main` توی GitHub Actions اجرا می‌شه (`.github/workflows/build-android.yml`).

اعتبارها: مدل کاراکتر Kenney (CC0)، آیتم‌ها از Artjom Shebunin (ذکر نام لازم).

- درخت، بوته، چمن، گل و سنگ: «Stylized Nature MegaKit» از Quaternius (CC0) توی `assets/nature/`. بافت‌ها برای موبایل کوچیک شدن و normal map ها حذف شدن.

- آسمون: Kenney Skyboxes (CC0) توی `assets/sky/`.
- زمین: `assets/ground/grass.jpg` (از کارت چمنی که فرستادی ساخته شده) و `stones.jpg` (بافت سنگ‌فرش، لایسنسش رو چک کن).
- دشمن سوسک: `tools/Roach.blend` توی CI با Blender به `assets/enemies/roach.glb` تبدیل می‌شه (اگه تبدیل نشد، زامبی جاش میاد). لایسنس مدل رو چک کن.
