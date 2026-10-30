# Windows-da O'rnatish va Ishlatish Qo'llanmasi

Ushbu dasturni Windows operatsion tizimida ishga tushirish uchun quyidagi qadamlarni bajaring.

## 1. Talablar (Requirements)

Dasturni Windows-da qurish (build) qilish uchun quyidagilar kerak bo'ladi:
1.  **Windows 10 yoki 11** operatsion tizimi.
2.  **Flutter SDK** o'rnatilgan bo'lishi kerak.
3.  **Visual Studio 2022** (yoki 2019) o'rnatilgan bo'lishi kerak. 
    *   O'rnatish paytida **"Desktop development with C++"** opsiyasini tanlashni unutmang.

## 2. Loyihani Ko'chirib O'tkazish

1.  Ushbu loyiha papkasini (`clinical_warehouse`) to'lig'icha Windows kompyuteringizga ko'chirib o'tkazing.
2.  Windows-da **PowerShell** yoki **Command Prompt (CMD)** ni oching va loyiha papkasiga kiring:
    ```cmd
    cd C:\Papkalar\MeningLoyiham\clinical_warehouse
    ```

## 3. Kutubxonalarni Yuklash

Kerakli paketlarni internetdan yuklab olish uchun quyidagi buyruqni bering:

```cmd
flutter pub get
```

## 4. Dasturni Ishga Tushirish (Test rejimi)

Dasturni tekshirish uchun uni "Debug" rejimida ochishingiz mumkin:

```cmd
flutter run -d windows
```

## 5. Yakuniy Dastur Faylini Yaratish (Build .EXE)

Foydalanishga tayyor `.exe` faylni yaratish uchun quyidagi buyruqni bering:

```cmd
flutter build windows
```

Ushbu jarayon biroz vaqt olishi mumkin. Tugagach, tayyor dastur quyidagi manzilda paydo bo'ladi:

`build\windows\runner\Release\` papkasi ichida `clinical_warehouse.exe` fayli va unga tegishli `data` papkalari bo'ladi.

> **Muhim:** Dasturni boshqa kompyuterga ko'chirganda faqat `.exe` faylni emas, balki butun `Release` papkasini ko'chirib o'tkazish kerak.

## 6. Ehtimoliy Muammolar

*   **SQLite Xatoligi:** Agar ma'lumotlar bazasi ishlamasa, Windows uchun `sqlite3.dll` fayli tizimda yetishmayotgan bo'lishi mumkin. Odatda Flutter buni avtomatik hal qiladi, lekin muammo bo'lsa, rasmiy saytdan yuklab olish kerak bo'ladi.
*   **Visual Studio C++:** Agar `CMake` bilan bog'liq xato chiqsa, Visual Studio Installer-ni ochib, "Desktop development with C++" o'rnatilganligini qayta tekshiring.
