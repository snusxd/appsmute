import Foundation

final class LanguageManager {
    static let shared = LanguageManager()
    static let didChangeNotification = Notification.Name("LanguageManager.didChange")

    private let fallbackCode = "en"
    private var languages: [String: [String: String]] = [:]
    private var languageNames: [String: String] = [:]

    private(set) var currentCode: String = "en"

    private init() {
        loadLanguages()

        let saved = LanguagePrefs.code
        if let saved, languages[saved] != nil {
            currentCode = saved
        } else if let system = pickSystemLanguage() {
            currentCode = system
            LanguagePrefs.code = system
        } else if languages[fallbackCode] != nil {
            currentCode = fallbackCode
        } else if let first = languages.keys.sorted().first {
            currentCode = first
        } else {
            currentCode = fallbackCode
            languages = defaultLanguageData()
            languageNames = defaultLanguageNames(from: languages)
        }
    }

    func availableLanguages() -> [(code: String, name: String)] {
        let items = languages.keys.map { code in
            (code: code, name: languageNames[code] ?? code)
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func setCurrent(code: String) {
        guard languages[code] != nil else { return }
        guard currentCode != code else { return }
        currentCode = code
        LanguagePrefs.code = code
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func t(_ key: String) -> String {
        if let value = languages[currentCode]?[key], !value.isEmpty { return value }
        if let value = languages[fallbackCode]?[key], !value.isEmpty { return value }
        return key
    }

    func reload() {
        let oldCode = currentCode
        loadLanguages()
        if languages[currentCode] == nil {
            if languages[fallbackCode] != nil {
                currentCode = fallbackCode
            } else if let first = languages.keys.sorted().first {
                currentCode = first
            }
        }

        if currentCode != oldCode {
            LanguagePrefs.code = currentCode
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    private func loadLanguages() {
        languages.removeAll()
        languageNames.removeAll()

        for url in languageJSONURLs() {
            let code = url.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) else { continue }
            guard let dict = obj as? [String: Any] else { continue }

            var strings: [String: String] = [:]
            for (k, v) in dict {
                if let s = v as? String { strings[k] = s }
            }

            if strings.isEmpty { continue }
            languages[code] = strings
            languageNames[code] = strings["language_name"] ?? code
        }

        if languages.isEmpty {
            languages = defaultLanguageData()
            languageNames = defaultLanguageNames(from: languages)
        }
    }

    private func languageJSONURLs() -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        var seen: Set<String> = []

        func add(_ url: URL) {
            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else { return }
            seen.insert(key)
            result.append(url)
        }

        if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "langs") {
            urls.forEach(add)
        }

        if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) {
            urls.forEach(add)
        }

        if let resourceURL = Bundle.main.resourceURL {
            let langsDir = resourceURL.appendingPathComponent("langs")
            if let urls = try? fm.contentsOfDirectory(at: langsDir, includingPropertiesForKeys: nil) {
                urls.filter { $0.pathExtension.lowercased() == "json" }.forEach(add)
            }

            let assetsLangsDir = resourceURL.appendingPathComponent("assets/langs")
            if let urls = try? fm.contentsOfDirectory(at: assetsLangsDir, includingPropertiesForKeys: nil) {
                urls.filter { $0.pathExtension.lowercased() == "json" }.forEach(add)
            }
        }

        let cwdLangs = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("langs")
        if let urls = try? fm.contentsOfDirectory(at: cwdLangs, includingPropertiesForKeys: nil) {
            urls.filter { $0.pathExtension.lowercased() == "json" }.forEach(add)
        }

        let cwdAssetsLangs = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("assets/langs")
        if let urls = try? fm.contentsOfDirectory(at: cwdAssetsLangs, includingPropertiesForKeys: nil) {
            urls.filter { $0.pathExtension.lowercased() == "json" }.forEach(add)
        }

        return result.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func pickSystemLanguage() -> String? {
        for id in Locale.preferredLanguages {
            if languages[id] != nil { return id }
            if let base = id.split(separator: "-").first.map(String.init), languages[base] != nil {
                return base
            }
            if let base = id.split(separator: "_").first.map(String.init), languages[base] != nil {
                return base
            }
        }
        return nil
    }

    private func defaultLanguageNames(from data: [String: [String: String]]) -> [String: String] {
        var out: [String: String] = [:]
        for (code, strings) in data {
            out[code] = strings["language_name"] ?? code
        }
        return out
    }

    private func defaultLanguageData() -> [String: [String: String]] {
        [
            "en": [
                "language_name": "English",
                "menu_enable_sound": "Enable Sound",
                "menu_disable_sound": "Disable Sound",
                "menu_shortcuts": "Hotkeys",
                "menu_add_shortcut": "+ Add Shortcut...",
                "menu_no_shortcuts": "No shortcuts",
                "menu_sounds": "Sounds",
                "menu_sounds_enabled": "Status sounds",
                "menu_language": "Language",
                "menu_open_window": "Menu",
                "menu_quit": "Quit",
                "tooltip_sound_on": "Sound: On",
                "tooltip_sound_off": "Sound: Off",
                "content_title": "appsmute",
                "content_subtitle": "Mute only selected apps on modern macOS",
                "content_enable": "Enable/Disable",
                "content_search": "Search running apps",
                "content_refresh": "Refresh",
                "content_no_apps": "No running apps found",
                "content_selected": "Selected",
                "content_running_muted": "Running & muted",
                "status_disabled": "appsmute is disabled",
                "status_enabled": "appsmute is enabled",
                "status_choose_apps": "Choose apps to mute and keep them running.",
                "status_active_prefix": "Muted now",
                "status_active_fallback": "Selective mute is active.",
                "status_coreaudio_error": "CoreAudio error",
                "shortcut_change_title": "Change Shortcut",
                "shortcut_info": "Click Record, then press a new shortcut",
                "shortcut_current_prefix": "Current: ",
                "shortcut_record": "Record",
                "shortcut_press_keys": "Press keys...",
                "label_volume": "Volume",
                "indicator_on": "ON",
                "indicator_off": "OFF",
                "key_space": "Space",
                "key_return": "↩",
                "key_tab": "⇥"
            ],
            "ru": [
                "language_name": "Русский",
                "menu_enable_sound": "Включить звук",
                "menu_disable_sound": "Выключить звук",
                "menu_shortcuts": "Горячие клавиши",
                "menu_add_shortcut": "+ Добавить сочетание...",
                "menu_no_shortcuts": "Нет сочетаний",
                "menu_sounds": "Звуки",
                "menu_sounds_enabled": "Звуки статуса",
                "menu_language": "Язык",
                "menu_open_window": "Меню",
                "menu_quit": "Выйти",
                "tooltip_sound_on": "Звук: включён",
                "tooltip_sound_off": "Звук: выключен",
                "content_title": "appsmute",
                "content_subtitle": "Мьют только выбранных приложений на новых macOS",
                "content_enable": "Enable/Disable",
                "content_search": "Поиск запущенных приложений",
                "content_refresh": "Обновить",
                "content_no_apps": "Запущенные приложения не найдены",
                "content_selected": "Выбрано",
                "content_running_muted": "Запущено и замьючено",
                "status_disabled": "appsmute is disabled",
                "status_enabled": "appsmute is enabled",
                "status_choose_apps": "Выбери приложения для мьюта и держи их запущенными.",
                "status_active_prefix": "Сейчас замьючены",
                "status_active_fallback": "Выборочный мьют активен.",
                "status_coreaudio_error": "Ошибка CoreAudio",
                "shortcut_change_title": "Изменить сочетание",
                "shortcut_info": "Нажмите «Запись», затем введите новое сочетание",
                "shortcut_current_prefix": "Текущее: ",
                "shortcut_record": "Запись",
                "shortcut_press_keys": "Нажмите клавиши...",
                "label_volume": "Громкость",
                "indicator_on": "ВКЛ",
                "indicator_off": "ВЫКЛ",
                "key_space": "Пробел",
                "key_return": "↩",
                "key_tab": "⇥"
            ]
        ]
    }
}
