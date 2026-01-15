import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTranslations extends ChangeNotifier {
  static const String _kLocaleKey = 'app_locale';
  String _currentLocale = 'uz'; // Default to Uzbek

  String get currentLocale => _currentLocale;

  // Singleton
  static final AppTranslations _instance = AppTranslations._internal();
  factory AppTranslations() => _instance;
  AppTranslations._internal();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLocale = prefs.getString(_kLocaleKey) ?? 'uz';
    notifyListeners();
  }

  Future<void> setLocale(String localeCode) async {
    if (_currentLocale == localeCode) return;
    
    _currentLocale = localeCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, localeCode);
    notifyListeners();
  }

  String text(String key) {
    return _localizedValues[_currentLocale]?[key] ?? key;
  }

  static const Map<String, Map<String, String>> _localizedValues = {
    'uz': {
      // Sidebar
      'menu_dashboard': 'Bosh sahifa',
      'menu_inventory': 'Omborxona',
      'menu_location': 'Joylashuv',
      'menu_in': 'Kirim',
      'menu_out': 'Chiqim',
      'menu_reports': 'Hisobotlar',
      'menu_database': 'Katalog',
      'menu_backup': 'Zaxira (Backup)',
      'menu_settings': 'Sozlamalar',
      'menu_logout': 'Chiqish',
      
      // Actions
      'btn_save': 'Saqlash',
      'btn_cancel': 'Bekor qilish',
      'btn_add_new': 'Yangi qo‘shish',
      'btn_edit': 'Tahrirlash',
      'btn_delete': 'O‘chirish',
      'btn_search': 'Qidirish',
      'btn_scan': 'Skanerlash',
      'btn_confirm': 'Tasdiqlash',
      'btn_export_pdf': 'PDF yuklash',
      'btn_undo': 'Ortga qaytarish',

      // Clinical
      'label_reagent': 'Mahsulot / Reaktiv',
      'label_consumable': 'Sarflov materiali',
      'label_expiry': 'Yaroqlilik muddati',
      'label_batch': 'Partiya / Seriya',
      'label_quantity': 'Soni (Qoldiq)',
      'label_unit': 'O‘lchov birligi',
      'label_box': 'Korobka',
      'label_piece': 'Dona',
      'label_fridge': 'Muzlatgich',
      'label_shelf': 'Javon',

      // Alerts
      'msg_expired': 'Muddati o‘tgan!',
      'msg_expiring_soon': 'Muddati tugamoqda',
      'msg_low_stock': 'Kam qoldi',
      'msg_saved': 'Muvaffaqiyatli saqlandi',
      'msg_error': 'Xatolik yuz berdi',
      'msg_backup_ok': 'Zaxira nusxa olindi',
      'msg_enter_pass': 'Maxfiy kalitni kiriting',

      // Other
      // Dashboard
      'dash_total_value': 'Umumiy Qiymat',
      'dash_low_stock': 'Kam Qolgan Mahsulotlar',
      'dash_expiring': 'Tugagan mahsulotlar',
      'dash_list_title': 'Tugagan Mahsulotlar',
      'dash_quick_actions': 'Tezkor Amallar',

      // Locations
      'loc_title': 'Joylashuvni Boshqarish',
      'loc_new_shelf': 'Yangi Javon',
      'loc_new_fridge': 'Yangi Muzlatgich',
      'loc_new_safe': 'Yangi Seyf',
      'loc_fridge': 'Muzlatgich',
      'loc_shelf': 'Javon',
      'loc_safe': 'Seyf',
      'loc_temp': 'Harorat',
      'loc_items': 'Narsalar',
      'set_auth': 'Kirish ma\'lumotlari',
      'login': 'Login (Nomi)',
      'password': 'Maxfiy Parol',
      'msg_login_error': 'Login yoki parol xato!',

      // Reports
      'rep_title': 'Hisobotlar Markazi',
      'rep_filter_today': 'Bugun',
      'rep_filter_week': 'Shu Hafta',
      'rep_filter_month': 'Shu Oy',
      'rep_daily_activity': 'Kundalik Faoliyat',
      'rep_usage_stats': 'Ishlatilish Statistikasi',
      'btn_export_excel': 'Excel ga Yuklash',

      // Settings
      'set_profile': 'Profil',
      'set_general': 'Umumiy',
      'set_theme': 'Tungi Rejim',
      'set_security': 'Xavfsizlik',
      'set_change_pass': 'Parolni O\'zgartirish',
      'set_logout': 'Tizimdan Chiqish',
      'set_manager': 'Boshqaruvchi',

      // Input View
      'inp_title': 'Kirim / Qabul qilish',
      'inp_desc': 'Mahsulotlarni qabul qilish uchun barkodni skanerlang yoki ma\'lumotlarni kiriting.',
      'btn_start_receive': 'Qabul qilishni boshlash',

      // Output View
      'out_title': 'Chiqim / Tarqatish',
      'out_desc': 'Bo\'limlarga tarqatish uchun mahsulotlarni tanlang.',
      'btn_create_out': 'Chiqim hujjatini yaratish',
      'msg_items_dist': 'Mahsulotlar tarqatildi.',

      // Dialogs
      'dlg_backup_title': 'Ma\'lumotlarni zaxiralash',
      'dlg_backup_content': 'Ma\'lumotlar bazasini saqlash joyini tanlang (masalan, USB drayv).',

      // MISSING KEYS RESTORED
      'system_active': 'Tizim faol. Shifrlangan.',
      'title_app': 'Omborxona\nBoshqaruv Tizimi',
      'text_welcome': 'Xush kelibsiz',
      
      'header_inventory': 'Omborxona',
      'header_locations': 'Joylashuvni Boshqarish',
      'header_check_in': 'Kirim / Qabul qilish',
      'header_check_out': 'Chiqim / Tarqatish',
      'header_reports': 'Hisobotlar Markazi',

      'col_name': 'Nomi',
      'col_category': 'Kategoriya',
      'col_stock': 'Qoldiq',
      'col_expiry': 'Muddati',
      'col_status': 'Holati',

      'status_healthy': 'Yaxshi',
      'status_low': 'Oz qoldi',
      'status_critical': 'Xavf',

      // Grid Columns (Detailed)
      'col_date': 'SANA & VAQT',
      'col_id': 'ID',
      'col_product': 'MAHSULOT NOMI',
      'col_price': 'NARXI',
      'col_unit': 'BIRLIK',
      'col_qty': 'MIQDORI',
      'col_tax_percent': 'QQS %',
      'col_tax_sum': 'QQS SUM',
      'col_surcharge_percent': 'USTAMA %',
      'col_surcharge_sum': 'USTAMA SUM',
      'col_from': 'KIMDAN',
      'col_to_receiver': 'KIMGA',
      'col_to': 'KIMGA',
      'col_total_amount': 'JAMI SUMMA',
      'col_no': '#',

      // Grid Menu
      'grid_freeze_start': 'Boshiga qotirish',
      'grid_freeze_end': 'Oxiriga qotirish',
      'grid_unfreeze': 'Qotirishni bekor qilish',
      'grid_auto_fit': 'Avto kenglik',
      'grid_hide_column': 'Ustunni yashirish',
      'grid_set_columns': 'Ustunlarni sozlash',
      'grid_set_filter': 'Filtrni sozlash',
      'grid_reset_filter': 'Filtrni bekor qilish',

      // Database View
      'db_title': 'Ma\'lumotlar Bazasi',
      'db_products': 'Mahsulotlar',
      'db_suppliers': 'Yetkazib Beruvchilar',
      'db_receivers': 'Qabul Qiluvchilar',
      'db_save_products': 'Ro\'yxatni Saqlash',
      'db_col_id_manual': 'ID / Barcode',
      'db_msg_saved': 'Ma\'lumotlar saqlandi',

      // Locations
      'loc_general_storage': 'Umumiy Ombor',
      'loc_controlled': 'Nazorat Ostida',
      'loc_temp_label': 'Harorat',

      // Reports Specific
      'rep_select_date': 'Sana Tanlash',
      'rep_in_report': 'Kirim Hisoboti',
      'rep_out_report': 'Chiqim Hisoboti',
      'col_notes': 'Izoh',
      'msg_loading': 'Yuklanmoqda...',
      'msg_no_data': 'Hozircha ma\'lumot yo\'q',
      'unit_currency': 'so\'m',
      'unit_items': 'ta',
      'label_critical': 'tugagan',
      'msg_not_found': 'Topilmadi',
      'inventory_desc': 'Ombordagi mahsulotlarning umumiy holati va qoldig\'i.',
      'btn_select_folder': 'Papkani tanlash',
    },
    'ru': {
      // Sidebar
      'menu_dashboard': 'Главная',
      'menu_inventory': 'Склад',
      'menu_location': 'Место',
      'menu_in': 'Приход',
      'menu_out': 'Расход',
      'menu_reports': 'Отчеты',
      'menu_database': 'Каталог',
      'menu_backup': 'Резервная копия',
      'menu_settings': 'Настройки',
      'menu_logout': 'Выход',

      // Actions
      'btn_save': 'Сохранить',
      'btn_cancel': 'Отмена',
      'btn_add_new': 'Добавить',
      'btn_edit': 'Редактировать',
      'btn_delete': 'Удалить',
      'btn_search': 'Поиск',
      'btn_scan': 'Сканировать',
      'btn_confirm': 'Подтвердить',
      'btn_export_pdf': 'Скачать PDF',
      'btn_undo': 'Вернуть (Undo)',

      // Clinical
      'label_reagent': 'Реагент',
      'label_consumable': 'Расходный материал',
      'label_expiry': 'Срок годности',
      'label_batch': 'Партия / Серия',
      'label_quantity': 'Количество',
      'label_unit': 'Ед. измерения',
      'label_box': 'Коробка',
      'label_piece': 'Штука',
      'label_fridge': 'Холодильник',
      'label_shelf': 'Полка',

      // Alerts
      'msg_expired': 'Срок истек!',
      'msg_expiring_soon': 'Срок истекает',
      'msg_low_stock': 'Мало на складе',
      'msg_saved': 'Успешно сохранено',
      'msg_error': 'Произошла ошибка',
      'msg_backup_ok': 'Резервная копия создана',
      'msg_enter_pass': 'Введите ключ доступа',

      // Other
      'system_active': 'Система активна. Зашифровано.',
      'title_app': 'Система\nУправления Складом',
      
      // Headers & Titles
      'header_inventory': 'Складской учет',
      'header_locations': 'Управление местами',
      'header_check_in': 'Прием / Ввод',
      'header_check_out': 'Выдача / Расход',
      'header_reports': 'Центр отчетов',

      // Table Columns
      'col_name': 'Название',
      'col_category': 'Категория',
      'col_stock': 'Остаток',
      'col_expiry': 'Срок',
      'col_status': 'Статус',

      // Statuses
      'status_healthy': 'Норма',
      'status_low': 'Мало',
      'status_critical': 'Критично',

      // Other
      'text_welcome': 'Добро пожаловать',
      'msg_login_error': 'Неверный логин или пароль!',
      'text_backup_desc': 'Выберите место для сохранения',
      'btn_select_folder': 'Выбрать папку',
      
      // Dashboard
      'dash_total_value': 'Общая Стоимость',
      'dash_low_stock': 'Мало на складе',
      'dash_expiring': 'Истекает срок',
      'dash_list_title': 'Истекающие реагенты',
      'dash_quick_actions': 'Быстрые действия',

      // Locations
      'loc_title': 'Управление местами',
      'loc_new_shelf': 'Новая полка',
      'loc_new_fridge': 'Новый холодильник',
      'loc_new_safe': 'Новый сейф',
      'loc_fridge': 'Холодильник',
      'loc_shelf': 'Полка',
      'loc_safe': 'Сейф',
      'loc_temp': 'Температура',
      'loc_items': 'Предметы',
      'set_auth': 'Данные для входа',
      'login': 'Логин',
      'password': 'Пароль',

      // Reports
      'rep_title': 'Центр отчетов',
      'rep_filter_today': 'Сегодня',
      'rep_filter_week': 'Эта неделя',
      'rep_filter_month': 'Этот месяц',
      'rep_daily_activity': 'Дневная активность',
      'rep_usage_stats': 'Статистика использования',
      'btn_export_excel': 'Скачать Excel',

      // Settings
      'set_profile': 'Профиль',
      'set_general': 'Общие',
      'set_theme': 'Темная тема',
      'set_security': 'Безопасность',
      'set_change_pass': 'Сменить пароль',
      'set_logout': 'Выйти из системы',
      'set_manager': 'Менеджер',
      
      // Input View
      'inp_title': 'Прием / Регистрация',
      'inp_desc': 'Сканируйте штрих-код или введите данные для приема товара.',
      'btn_start_receive': 'Начать прием',

      // Output View
      'out_title': 'Выдача / Распределение',
      'out_desc': 'Выберите товары для выдачи в отделения.',
      'btn_create_out': 'Создать накладную',
      'msg_items_dist': 'Товары выданы.',

      // Dialogs
      'dlg_backup_title': 'Резервное копирование',
      'dlg_backup_content': 'Выберите место для сохранения базы данных (например, USB-накопитель).',

      // Grid Columns (Detailed)
      'col_date': 'ДАТА И ВРЕМЯ',
      'col_id': 'ID',
      'col_product': 'ПРОДУКТ',
      'col_price': 'ЦЕНА',
      'col_unit': 'ЕД.',
      'col_qty': 'КОЛ-ВО',
      'col_tax_percent': 'НДС %',
      'col_tax_sum': 'СУММА НДС',
      'col_surcharge_percent': 'НАЦЕНКА %',
      'col_surcharge_sum': 'СУММА НАЦЕНКИ',
      'col_from': 'ОТ КОГО',
      'col_to_receiver': 'КОМУ',
      'col_to': 'КОМУ',
      'col_total_amount': 'ИТОГО',
      'col_no': '#',

      // Grid Menu
      'grid_freeze_start': 'Закрепить в начале',
      'grid_freeze_end': 'Закрепить в конце',
      'grid_unfreeze': 'Открепить',
      'grid_auto_fit': 'Авто-ширина',
      'grid_hide_column': 'Скрыть столбец',
      'grid_set_columns': 'Настройка столбцов',
      'grid_set_filter': 'Установить фильтр',
      'grid_reset_filter': 'Сбросить фильтр',

      // Database View
      'db_title': 'База Данных',
      'db_products': 'Продукты',
      'db_suppliers': 'Поставщики',
      'db_receivers': 'Получатели',
      'db_save_products': 'Сохранить список',
      'db_col_id_manual': 'ID / Штрих-код',
      'db_msg_saved': 'Данные сохранены',

      // Locations
      'loc_general_storage': 'Общий Склад',
      'loc_controlled': 'Контролируемый',
      'loc_temp_label': 'Температура',

      // Reports Specific
      'rep_select_date': 'Выбрать Дату',
      'rep_in_report': 'Отчет Прихода',
      'rep_out_report': 'Отчет Расхода',
      'col_notes': 'Примечание',
      'msg_loading': 'Загрузка...',
      'msg_no_data': 'Данных пока нет',
      'unit_currency': 'сум',
      'unit_items': 'шт',
      'label_critical': 'критично',
      'msg_not_found': 'Не найдено',
      'inventory_desc': 'Общее состояние и остатки товаров на складе.',
    },
    'tr': {
      // Sidebar
      'menu_dashboard': 'Ana Sayfa',
      'menu_inventory': 'Depo',
      'menu_location': 'Konum',
      'menu_in': 'Stok Girişi',
      'menu_out': 'Stok Çıkışı',
      'menu_reports': 'Raporlar',
      'menu_database': 'Katalog',
      'menu_backup': 'Yedekleme',
      'menu_settings': 'Ayarlar',
      'menu_logout': 'Çıkış Yap',

      // Actions
      'btn_save': 'Kaydet',
      'btn_cancel': 'İptal Et',
      'btn_add_new': 'Yeni Ekle',
      'btn_edit': 'Düzenle',
      'btn_delete': 'Sil',
      'btn_search': 'Ara',
      'btn_scan': 'Tara (Barkod)',
      'btn_confirm': 'Onayla',
      'btn_export_pdf': 'PDF İndir',
      'btn_undo': 'Geri Al',

      // Clinical
      'label_reagent': 'Reaktif',
      'label_consumable': 'Sarf Malzemesi',
      'label_expiry': 'Son Kullanma Tarihi',
      'label_batch': 'Parti / Seri No',
      'label_quantity': 'Miktar',
      'label_unit': 'Ölçü Birimi',
      'label_box': 'Kutu',
      'label_piece': 'Adet',
      'label_fridge': 'Buzdolabı',
      'label_shelf': 'Raf',

      // Alerts
      'msg_expired': 'Süresi Doldu!',
      'msg_expiring_soon': 'Süresi Dolmak Üzere',
      'msg_low_stock': 'Stok Azaldı',
      'msg_saved': 'Başarıyla Kaydedildi',
      'msg_error': 'Hata Oluştu',
      'msg_backup_ok': 'Yedekleme Tamamlandı',
      'msg_enter_pass': 'Gizli Anahtarı Girin',

      // Other
      'system_active': 'Sistem Aktif. Şifrelendi.',
      'title_app': 'Depo\nYönetim Sistemi',
      
      // Headers & Titles
      'header_inventory': 'Depo İçeriği',
      'header_locations': 'Konum Yönetimi',
      'header_check_in': 'Giriş / Kabul',
      'header_check_out': 'Çıkış / Dağıtım',
      'header_reports': 'Rapor Merkezi',

      // Table Columns
      'col_name': 'İsim',
      'col_category': 'Kategori',
      'col_stock': 'Stok',
      'col_expiry': 'S.K.T',
      'col_status': 'Durum',

      // Statuses
      'status_healthy': 'İyi',
      'status_low': 'Az',
      'status_critical': 'Kritik',

      // Other
      'text_welcome': 'Hoşgeldiniz',
      'msg_login_error': 'Geçersiz kullanıcı adı veya şifre!',
      'text_backup_desc': 'Yedekleme konumunu seçin',
      'btn_select_folder': 'Klasör Seç',
      
      // Dashboard
      'dash_total_value': 'Toplam Değer',
      'dash_low_stock': 'Stok Az',
      'dash_expiring': 'Süresi Bitiyor',
      'dash_list_title': 'Süresi Bitenler',
      'dash_quick_actions': 'Hızlı İşlemler',

      // Locations
      'loc_title': 'Konum Yönetimi',
      'loc_new_shelf': 'Yeni Raf',
      'loc_new_fridge': 'Yeni Dolap',
      'loc_new_safe': 'Yeni Kasa',
      'loc_fridge': 'Buzdolabı',
      'loc_shelf': 'Raf',
      'loc_safe': 'Kasa',
      'loc_temp': 'Sıcaklık',
      'loc_items': 'Ürün',
      'set_auth': 'Giriş Bilgileri',
      'login': 'Kullanıcı Adı',
      'password': 'Şifre',

      // Reports
      'rep_title': 'Rapor Merkezi',
      'rep_filter_today': 'Bugün',
      'rep_filter_week': 'Bu Hafta',
      'rep_filter_month': 'Bu Ay',
      'rep_daily_activity': 'Günlük Aktivite',
      'rep_usage_stats': 'Kullanım İstatistikleri',
      'btn_export_excel': 'Excel İndir',

      // Settings
      'set_profile': 'Profil',
      'set_general': 'Genel',
      'set_theme': 'Karanlık Mod',
      'set_security': 'Güvenlik',
      'set_change_pass': 'Şifre Değiştir',
      'set_logout': 'Çıkış Yap',
      'set_manager': 'Yönetici',
      
      // Input View
      'inp_title': 'Giriş / Kabul',
      'inp_desc': 'Ürün kabulü için barkodu tarayın veya bilgileri girin.',
      'btn_start_receive': 'Kabulü Başlat',

      // Output View
      'out_title': 'Çıkış / Dağıtım',
      'out_desc': 'Bölümlere dağıtılacak ürünleri seçin.',
      'btn_create_out': 'Çıkış Fişi Oluştur',
      'msg_items_dist': 'Ürünler dağıtıldı.',

      // Dialogs
      'dlg_backup_title': 'Veri Yedekleme',
      'dlg_backup_content': 'Veritabanını kaydetmek için bir konum seçin (örn. USB Bellek).',

      // Grid Columns (Detailed)
      'col_date': 'TARIH',
      'col_id': 'ID',
      'col_product': 'ÜRÜN',
      'col_price': 'FIYAT',
      'col_unit': 'BIRIM',
      'col_qty': 'MIKTAR',
      'col_tax_percent': 'KDV %',
      'col_tax_sum': 'KDV TUTAR',
      'col_surcharge_percent': 'EK ÜCRET %',
      'col_surcharge_sum': 'EK ÜCRET TUTAR',
      'col_from': 'KIMDEN',
      'col_to_receiver': 'KIME',
      'col_to': 'KIME',
      'col_total_amount': 'TOPLAM TUTAR',
      'col_no': '#',

      // Grid Menu
      'grid_freeze_start': 'Başa sabitle',
      'grid_freeze_end': 'Sona sabitle',
      'grid_unfreeze': 'Sabitlemeyi kaldır',
      'grid_auto_fit': 'Otomatik genişlik',
      'grid_hide_column': 'Sütunu gizle',
      'grid_set_columns': 'Sütunları ayarla',
      'grid_set_filter': 'Filtrele',
      'grid_reset_filter': 'Filtreyi sıfırla',

      // Database View
      'db_title': 'Veri Tabanı',
      'db_products': 'Ürünler',
      'db_suppliers': 'Tedarikçiler',
      'db_receivers': 'Alıcılar',
      'db_save_products': 'Listeyi Kaydet',
      'db_col_id_manual': 'ID / Barkod',
      'db_msg_saved': 'Veriler kaydedildi',

      // Locations
      'loc_general_storage': 'Genel Depo',
      'loc_controlled': 'Kontrollü',
      'loc_temp_label': 'Sıcaklık',

      // Reports Specific
      'rep_select_date': 'Tarih Seç',
      'rep_in_report': 'Giriş Raporu',
      'rep_out_report': 'Çıkış Raporu',
      'col_notes': 'Açıklama',
      'msg_loading': 'Yükleniyor...',
      'msg_no_data': 'Henüz veri yok',
      'unit_currency': 'TL',
      'unit_items': 'adet',
      'label_critical': 'kritik',
      'msg_not_found': 'Bulunamadı',
      'inventory_desc': 'Depodaki ürünlerin genel durumu ve bakiyesi.',
    },
  };
}
