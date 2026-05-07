import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case zh
    case en
    case ja
    case ko
    case de
    case fr
    case ru

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .ru: return "Русский"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .zh: return "zh_Hans"
        case .en: return "en"
        case .ja: return "ja"
        case .ko: return "ko"
        case .de: return "de"
        case .fr: return "fr"
        case .ru: return "ru"
        }
    }

    static var preferred: AppLanguage {
        let codes = Locale.preferredLanguages.map { Locale(identifier: $0).language.languageCode?.identifier ?? $0 }
        for code in codes {
            if code.hasPrefix("zh") { return .zh }
            if code.hasPrefix("en") { return .en }
            if code.hasPrefix("ja") { return .ja }
            if code.hasPrefix("ko") { return .ko }
            if code.hasPrefix("de") { return .de }
            if code.hasPrefix("fr") { return .fr }
            if code.hasPrefix("ru") { return .ru }
        }
        return .zh
    }
}

@MainActor
final class Localization: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "AppLanguage"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let saved = AppLanguage(rawValue: raw) {
            self.language = saved
        } else {
            self.language = .preferred
        }
    }

    var locale: Locale {
        Locale(identifier: language.localeIdentifier)
    }

    func t(_ key: String) -> String {
        Self.translations[language]?[key] ?? Self.translations[.en]?[key] ?? key
    }

    func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: args)
    }

    private static let translations: [AppLanguage: [String: String]] = [
        .zh: [
            "app.name": "浏览器多开",
            "common.cancel": "取消",
            "common.confirm": "确定",
            "common.delete": "删除",
            "common.close": "关闭",
            "common.start": "启动",
            "common.later": "稍后",
            "language": "语言",
            "profile.default_name": "环境%d",
            "profile.display_name": "环境%d - %@",
            "empty.title": "还没有环境",
            "empty.subtitle": "点击工具栏 + 添加一个",
            "toolbar.add": "添加环境",
            "toolbar.stop_all": "全部关闭",
            "context.rename": "重命名",
            "context.delete": "删除",
            "delete.title": "确认删除",
            "delete.message": "将删除「%@」的所有数据",
            "status.starting": "启动中",
            "status.running": "运行中",
            "status.stopped": "未启动",
            "meta.port": "端口 %d",
            "date.today": "今天",
            "date.yesterday": "昨天",
            "date.days_ago": "%d天前",
            "date.month_day": "%d月%d日",
            "rename.title": "重命名",
            "rename.hint": "自定义名称，方便识别",
            "rename.placeholder": "为此环境命名",
            "menu.open_panel": "打开管理面板",
            "menu.check_updates": "检查更新",
            "menu.quit": "退出",
            "update.title": "检查更新",
            "update.up_to_date": "当前已是最新版本",
            "update.available_title": "发现新版本",
            "update.available_message": "最新版本: %@\n当前版本: %@",
            "update.download": "前往下载",
            "update.failed": "无法连接服务器，请检查网络后重试",
            "quit.title": "确认退出",
            "quit.confirm": "关闭并退出",
            "quit.message": "还有 %d 个环境正在运行，退出将自动关闭所有环境。",
            "download.title": "首次使用，正在下载浏览器",
            "download.preparing": "准备中...",
            "download.progress": "下载中...（约 237MB）",
            "download.installing": "正在安装...",
            "download.failed": "下载失败",
            "download.manual_title": "你也可以手动安装浏览器：",
            "download.manual_steps": "1. 下载 Chrome：https://www.google.com/chrome/\n2. 双击 dmg，将「Google Chrome.app」\n   拖入下方目标文件夹",
            "download.open_folder": "打开目标文件夹",
            "download.retry": "重试下载"
        ],
        .en: [
            "app.name": "Browser Isolator",
            "common.cancel": "Cancel",
            "common.confirm": "OK",
            "common.delete": "Delete",
            "common.close": "Close",
            "common.start": "Start",
            "common.later": "Later",
            "language": "Language",
            "profile.default_name": "Environment %d",
            "profile.display_name": "Environment %d - %@",
            "empty.title": "No environments yet",
            "empty.subtitle": "Click + in the toolbar to add one",
            "toolbar.add": "Add Environment",
            "toolbar.stop_all": "Close All",
            "context.rename": "Rename",
            "context.delete": "Delete",
            "delete.title": "Confirm Delete",
            "delete.message": "Delete all data for \"%@\"",
            "status.starting": "Starting",
            "status.running": "Running",
            "status.stopped": "Stopped",
            "meta.port": "Port %d",
            "date.today": "Today",
            "date.yesterday": "Yesterday",
            "date.days_ago": "%d days ago",
            "date.month_day": "%d/%d",
            "rename.title": "Rename",
            "rename.hint": "Add a custom name for recognition",
            "rename.placeholder": "Name this environment",
            "menu.open_panel": "Open Panel",
            "menu.check_updates": "Check for Updates",
            "menu.quit": "Quit",
            "update.title": "Check for Updates",
            "update.up_to_date": "You are already on the latest version",
            "update.available_title": "New Version Available",
            "update.available_message": "Latest: %@\nCurrent: %@",
            "update.download": "Download",
            "update.failed": "Could not connect to the server. Check your network and try again.",
            "quit.title": "Confirm Quit",
            "quit.confirm": "Close and Quit",
            "quit.message": "%d environments are still running. Quitting will close them all.",
            "download.title": "Downloading browser for first use",
            "download.preparing": "Preparing...",
            "download.progress": "Downloading... (about 237 MB)",
            "download.installing": "Installing...",
            "download.failed": "Download failed",
            "download.manual_title": "You can also install the browser manually:",
            "download.manual_steps": "1. Download Chrome: https://www.google.com/chrome/\n2. Open the DMG and move \"Google Chrome.app\"\n   into the target folder below",
            "download.open_folder": "Open Target Folder",
            "download.retry": "Retry Download"
        ],
        .ja: [
            "app.name": "ブラウザ分離",
            "common.cancel": "キャンセル",
            "common.confirm": "OK",
            "common.delete": "削除",
            "common.close": "閉じる",
            "common.start": "起動",
            "common.later": "後で",
            "language": "言語",
            "profile.default_name": "環境%d",
            "profile.display_name": "環境%d - %@",
            "empty.title": "環境はまだありません",
            "empty.subtitle": "ツールバーの + で追加",
            "toolbar.add": "環境を追加",
            "toolbar.stop_all": "すべて閉じる",
            "context.rename": "名前を変更",
            "context.delete": "削除",
            "delete.title": "削除の確認",
            "delete.message": "「%@」のすべてのデータを削除します",
            "status.starting": "起動中",
            "status.running": "実行中",
            "status.stopped": "停止中",
            "meta.port": "ポート %d",
            "date.today": "今日",
            "date.yesterday": "昨日",
            "date.days_ago": "%d日前",
            "date.month_day": "%d月%d日",
            "rename.title": "名前を変更",
            "rename.hint": "識別しやすい名前を付けます",
            "rename.placeholder": "この環境の名前",
            "menu.open_panel": "管理パネルを開く",
            "menu.check_updates": "アップデートを確認",
            "menu.quit": "終了",
            "update.title": "アップデート確認",
            "update.up_to_date": "現在のバージョンは最新です",
            "update.available_title": "新しいバージョンがあります",
            "update.available_message": "最新: %@\n現在: %@",
            "update.download": "ダウンロード",
            "update.failed": "サーバーに接続できません。ネットワークを確認してください。",
            "quit.title": "終了の確認",
            "quit.confirm": "閉じて終了",
            "quit.message": "%d 個の環境が実行中です。終了するとすべて閉じます。",
            "download.title": "初回使用のためブラウザをダウンロード中",
            "download.preparing": "準備中...",
            "download.progress": "ダウンロード中...（約 237 MB）",
            "download.installing": "インストール中...",
            "download.failed": "ダウンロード失敗",
            "download.manual_title": "手動でブラウザをインストールすることもできます：",
            "download.manual_steps": "1. Chrome をダウンロード：https://www.google.com/chrome/\n2. DMG を開き、「Google Chrome.app」を\n   下の対象フォルダへ移動",
            "download.open_folder": "対象フォルダを開く",
            "download.retry": "再試行"
        ],
        .ko: [
            "app.name": "브라우저 분리",
            "common.cancel": "취소",
            "common.confirm": "확인",
            "common.delete": "삭제",
            "common.close": "닫기",
            "common.start": "시작",
            "common.later": "나중에",
            "language": "언어",
            "profile.default_name": "환경 %d",
            "profile.display_name": "환경 %d - %@",
            "empty.title": "아직 환경이 없습니다",
            "empty.subtitle": "툴바의 + 버튼으로 추가하세요",
            "toolbar.add": "환경 추가",
            "toolbar.stop_all": "모두 닫기",
            "context.rename": "이름 변경",
            "context.delete": "삭제",
            "delete.title": "삭제 확인",
            "delete.message": "\"%@\"의 모든 데이터를 삭제합니다",
            "status.starting": "시작 중",
            "status.running": "실행 중",
            "status.stopped": "중지됨",
            "meta.port": "포트 %d",
            "date.today": "오늘",
            "date.yesterday": "어제",
            "date.days_ago": "%d일 전",
            "date.month_day": "%d월 %d일",
            "rename.title": "이름 변경",
            "rename.hint": "구분하기 쉬운 이름을 추가하세요",
            "rename.placeholder": "이 환경 이름",
            "menu.open_panel": "관리 패널 열기",
            "menu.check_updates": "업데이트 확인",
            "menu.quit": "종료",
            "update.title": "업데이트 확인",
            "update.up_to_date": "이미 최신 버전입니다",
            "update.available_title": "새 버전 발견",
            "update.available_message": "최신: %@\n현재: %@",
            "update.download": "다운로드",
            "update.failed": "서버에 연결할 수 없습니다. 네트워크를 확인하세요.",
            "quit.title": "종료 확인",
            "quit.confirm": "닫고 종료",
            "quit.message": "%d개의 환경이 실행 중입니다. 종료하면 모두 닫힙니다.",
            "download.title": "처음 사용을 위해 브라우저 다운로드 중",
            "download.preparing": "준비 중...",
            "download.progress": "다운로드 중... (약 237 MB)",
            "download.installing": "설치 중...",
            "download.failed": "다운로드 실패",
            "download.manual_title": "브라우저를 수동으로 설치할 수도 있습니다:",
            "download.manual_steps": "1. Chrome 다운로드: https://www.google.com/chrome/\n2. DMG를 열고 \"Google Chrome.app\"을\n   아래 대상 폴더로 이동",
            "download.open_folder": "대상 폴더 열기",
            "download.retry": "다시 다운로드"
        ],
        .de: [
            "app.name": "Browser-Isolator",
            "common.cancel": "Abbrechen",
            "common.confirm": "OK",
            "common.delete": "Löschen",
            "common.close": "Schließen",
            "common.start": "Starten",
            "common.later": "Später",
            "language": "Sprache",
            "profile.default_name": "Umgebung %d",
            "profile.display_name": "Umgebung %d - %@",
            "empty.title": "Noch keine Umgebungen",
            "empty.subtitle": "Klicke auf + in der Symbolleiste",
            "toolbar.add": "Umgebung hinzufügen",
            "toolbar.stop_all": "Alle schließen",
            "context.rename": "Umbenennen",
            "context.delete": "Löschen",
            "delete.title": "Löschen bestätigen",
            "delete.message": "Alle Daten für „%@“ löschen",
            "status.starting": "Startet",
            "status.running": "Läuft",
            "status.stopped": "Gestoppt",
            "meta.port": "Port %d",
            "date.today": "Heute",
            "date.yesterday": "Gestern",
            "date.days_ago": "vor %d Tagen",
            "date.month_day": "%d.%d.",
            "rename.title": "Umbenennen",
            "rename.hint": "Eigener Name zur besseren Erkennung",
            "rename.placeholder": "Diese Umgebung benennen",
            "menu.open_panel": "Panel öffnen",
            "menu.check_updates": "Nach Updates suchen",
            "menu.quit": "Beenden",
            "update.title": "Nach Updates suchen",
            "update.up_to_date": "Du verwendest bereits die neueste Version",
            "update.available_title": "Neue Version verfügbar",
            "update.available_message": "Neueste: %@\nAktuell: %@",
            "update.download": "Herunterladen",
            "update.failed": "Keine Verbindung zum Server. Bitte Netzwerk prüfen.",
            "quit.title": "Beenden bestätigen",
            "quit.confirm": "Schließen und beenden",
            "quit.message": "%d Umgebungen laufen noch. Beim Beenden werden alle geschlossen.",
            "download.title": "Browser wird für die erste Nutzung geladen",
            "download.preparing": "Vorbereitung...",
            "download.progress": "Download läuft... (ca. 237 MB)",
            "download.installing": "Installation läuft...",
            "download.failed": "Download fehlgeschlagen",
            "download.manual_title": "Du kannst den Browser auch manuell installieren:",
            "download.manual_steps": "1. Chrome herunterladen: https://www.google.com/chrome/\n2. DMG öffnen und „Google Chrome.app“\n   in den Zielordner unten verschieben",
            "download.open_folder": "Zielordner öffnen",
            "download.retry": "Erneut versuchen"
        ],
        .fr: [
            "app.name": "Isolateur de navigateur",
            "common.cancel": "Annuler",
            "common.confirm": "OK",
            "common.delete": "Supprimer",
            "common.close": "Fermer",
            "common.start": "Démarrer",
            "common.later": "Plus tard",
            "language": "Langue",
            "profile.default_name": "Environnement %d",
            "profile.display_name": "Environnement %d - %@",
            "empty.title": "Aucun environnement",
            "empty.subtitle": "Cliquez sur + dans la barre d'outils",
            "toolbar.add": "Ajouter un environnement",
            "toolbar.stop_all": "Tout fermer",
            "context.rename": "Renommer",
            "context.delete": "Supprimer",
            "delete.title": "Confirmer la suppression",
            "delete.message": "Supprimer toutes les données de « %@ »",
            "status.starting": "Démarrage",
            "status.running": "En cours",
            "status.stopped": "Arrêté",
            "meta.port": "Port %d",
            "date.today": "Aujourd'hui",
            "date.yesterday": "Hier",
            "date.days_ago": "il y a %d jours",
            "date.month_day": "%d/%d",
            "rename.title": "Renommer",
            "rename.hint": "Ajoutez un nom pour mieux l'identifier",
            "rename.placeholder": "Nom de cet environnement",
            "menu.open_panel": "Ouvrir le panneau",
            "menu.check_updates": "Rechercher des mises à jour",
            "menu.quit": "Quitter",
            "update.title": "Rechercher des mises à jour",
            "update.up_to_date": "Vous utilisez déjà la dernière version",
            "update.available_title": "Nouvelle version disponible",
            "update.available_message": "Dernière: %@\nActuelle: %@",
            "update.download": "Télécharger",
            "update.failed": "Impossible de se connecter au serveur. Vérifiez le réseau.",
            "quit.title": "Confirmer la fermeture",
            "quit.confirm": "Fermer et quitter",
            "quit.message": "%d environnements sont encore en cours. Quitter les fermera tous.",
            "download.title": "Téléchargement du navigateur pour la première utilisation",
            "download.preparing": "Préparation...",
            "download.progress": "Téléchargement... (environ 237 Mo)",
            "download.installing": "Installation...",
            "download.failed": "Échec du téléchargement",
            "download.manual_title": "Vous pouvez aussi installer le navigateur manuellement :",
            "download.manual_steps": "1. Téléchargez Chrome : https://www.google.com/chrome/\n2. Ouvrez le DMG et déplacez « Google Chrome.app »\n   dans le dossier cible ci-dessous",
            "download.open_folder": "Ouvrir le dossier cible",
            "download.retry": "Réessayer"
        ],
        .ru: [
            "app.name": "Изолятор браузера",
            "common.cancel": "Отмена",
            "common.confirm": "OK",
            "common.delete": "Удалить",
            "common.close": "Закрыть",
            "common.start": "Запустить",
            "common.later": "Позже",
            "language": "Язык",
            "profile.default_name": "Среда %d",
            "profile.display_name": "Среда %d - %@",
            "empty.title": "Сред пока нет",
            "empty.subtitle": "Нажмите + на панели инструментов",
            "toolbar.add": "Добавить среду",
            "toolbar.stop_all": "Закрыть все",
            "context.rename": "Переименовать",
            "context.delete": "Удалить",
            "delete.title": "Подтвердите удаление",
            "delete.message": "Удалить все данные для «%@»",
            "status.starting": "Запуск",
            "status.running": "Работает",
            "status.stopped": "Остановлена",
            "meta.port": "Порт %d",
            "date.today": "Сегодня",
            "date.yesterday": "Вчера",
            "date.days_ago": "%d дн. назад",
            "date.month_day": "%d.%d",
            "rename.title": "Переименовать",
            "rename.hint": "Добавьте имя для удобного распознавания",
            "rename.placeholder": "Имя этой среды",
            "menu.open_panel": "Открыть панель",
            "menu.check_updates": "Проверить обновления",
            "menu.quit": "Выйти",
            "update.title": "Проверить обновления",
            "update.up_to_date": "У вас уже последняя версия",
            "update.available_title": "Доступна новая версия",
            "update.available_message": "Последняя: %@\nТекущая: %@",
            "update.download": "Скачать",
            "update.failed": "Не удалось подключиться к серверу. Проверьте сеть.",
            "quit.title": "Подтвердите выход",
            "quit.confirm": "Закрыть и выйти",
            "quit.message": "Еще работает сред: %d. При выходе все они будут закрыты.",
            "download.title": "Загрузка браузера для первого запуска",
            "download.preparing": "Подготовка...",
            "download.progress": "Загрузка... (около 237 МБ)",
            "download.installing": "Установка...",
            "download.failed": "Ошибка загрузки",
            "download.manual_title": "Браузер также можно установить вручную:",
            "download.manual_steps": "1. Скачайте Chrome: https://www.google.com/chrome/\n2. Откройте DMG и переместите «Google Chrome.app»\n   в целевую папку ниже",
            "download.open_folder": "Открыть целевую папку",
            "download.retry": "Повторить загрузку"
        ]
    ]
}
