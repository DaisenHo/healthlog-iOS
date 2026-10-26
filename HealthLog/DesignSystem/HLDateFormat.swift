import Foundation

/// **A360-1 H1 / A360-4 QoL-3 — date-format preference (auto / DMY / MDY / YMD).**
///
/// Mirrors the server's `User.dateFormat` Prisma enum
/// (`src/lib/format-locale.ts` `DateFormatPreference`): `AUTO` defers to the
/// device locale's own field order (en-US → MM/dd/yyyy, de-DE → dd.MM.yyyy),
/// `DMY` pins day-month-year, `MDY` pins month-day-year, `YMD` pins ISO
/// yyyy-MM-dd. The server is authoritative — the value is fetched from
/// `GET /api/user/profile` and pushed back via `PATCH` — but every *rendered*
/// date in the app reads it through this ONE helper so the preference applies
/// everywhere identically.
///
/// This is the date sibling of ``HLTimeFormat`` and follows the same
/// UserDefaults-mirror pattern: most date-rendering helpers on the labs /
/// illness / share-link surfaces are pure formatters (the contract tests
/// exercise them off the MainActor), so threading the live `SettingsStore`
/// through every one would invert the dependency direction. Instead
/// `SettingsStore` mirrors the server-resolved value into a single UserDefaults
/// key whenever the profile loads, and the formatters read it synchronously
/// here. UserDefaults usage is inside the "UI-prefs" allowlist per PROJECT_GUIDE.md
/// (no Health-data, no tokens — purely a display preference).
///
/// **Field-order via a pinned locale.** The numeric field order is a property
/// of the BCP-47 locale, not a `Date.FormatStyle` option, so the non-AUTO
/// cases pin a canonical locale whose default numeric date order matches the
/// requested preference — exactly the server's `dateOrderLocale` mapping
/// (DMY → de-DE `dd.MM.yyyy`, MDY → en-US `MM/dd/yyyy`, YMD → en-CA/ISO
/// `yyyy-MM-dd`). AUTO keeps the device's own locale.
public enum HLDateFormat: String, CaseIterable, Sendable {
    /// Follow the device locale's own field order.
    case auto = "AUTO"
    /// Pin day-month-year (dd.MM.yyyy).
    case dayMonthYear = "DMY"
    /// Pin month-day-year (MM/dd/yyyy).
    case monthDayYear = "MDY"
    /// Pin ISO year-month-day (yyyy-MM-dd).
    case yearMonthDay = "YMD"

    /// UserDefaults key the `SettingsStore` mirror writes and the pure
    /// formatters read. Namespaced like the other `hl.settings.*` UI-prefs.
    public static let defaultsKey = "hl.settings.dateFormat"

    /// The currently effective preference, read from the UserDefaults mirror.
    /// Defaults to `.auto` when unset (fresh install / pre-mirror) so the
    /// device locale governs until the server profile lands.
    public static func current(defaults: UserDefaults = .standard) -> HLDateFormat {
        HLDateFormat(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .auto
    }

    /// Localised label for the Settings picker.
    public var label: String {
        switch self {
        case .auto: AppLocale.string("settings.date_format.auto")
        case .dayMonthYear: AppLocale.string("settings.date_format.dmy")
        case .monthDayYear: AppLocale.string("settings.date_format.mdy")
        case .yearMonthDay: AppLocale.string("settings.date_format.ymd")
        }
    }

    /// The `Locale` to hand a `Date.FormatStyle` so the numeric field order
    /// honours the preference. `AUTO` returns `.current` (the device locale
    /// governs); the pinned cases return the canonical locale whose default
    /// numeric date order matches the requested preference — identical to the
    /// server's `dateOrderLocale`.
    public var formattingLocale: Locale {
        switch self {
        case .auto: AppLocale.shared.current
        case .dayMonthYear: Locale(identifier: "de_DE")
        case .monthDayYear: Locale(identifier: "en_US")
        case .yearMonthDay: Locale(identifier: "en_CA")
        }
    }

    /// A `Date.FormatStyle` style for date display. The canonical app default is
    /// `.abbreviated` (e.g. "17 Jun 2026") — the most common existing style.
    public enum Style: Sendable {
        /// Numeric date in the preference's field order (e.g. 17.06.2026 /
        /// 06/17/2026 / 2026-06-17). Routes through `.numeric` so the pinned
        /// locale governs the field order; for non-AUTO this is the user's
        /// explicit pick rendered numerically.
        case numeric
        /// Abbreviated month (e.g. "17 Jun 2026" / "Jun 17, 2026"). The
        /// preference still governs the field order via the pinned locale.
        case abbreviated
        /// Long month (e.g. "17 June 2026" / "June 17, 2026").
        case long
        /// Full date incl. weekday (e.g. "Wed, 17 Jun 2026").
        case complete
    }

    /// Format `date` honouring the preference + the requested style. Routes
    /// through `Date.FormatStyle` with the resolved ``formattingLocale`` so the
    /// field order follows the server pick while the device timezone governs
    /// the calendar day.
    ///
    /// 账户语言为中文且日期顺序不是自动时，纯数字日期仍用原来的顺序。
    /// 带月份或星期的样式用固定中文格式，避免月份和星期变成德文或英文。
    public func formatDate(_ date: Date, style: Style = .abbreviated) -> String {
        if let patterned = Self.chineseNamedDate(date, order: self, style: style) {
            return patterned
        }
        return date.formatted(Self.formatStyle(for: style).locale(formattingLocale))
    }

    /// Format `date` honouring BOTH the date-order preference AND the
    /// 12h/24h time preference (``HLTimeFormat``).
    ///
    /// **BH-final-diff M6.** The date-order pref pins a canonical locale
    /// (`formattingLocale`) whose DEFAULT hour cycle would otherwise silently
    /// govern the time component (MDY → `en_US` → 12h regardless of an H24 pref;
    /// DMY → `de_DE` → 24h regardless of an H12 pref). The two prefs are
    /// orthogonal, so we compose: take the date-order locale for the
    /// day/month/separator layout, then force its hour cycle from the live
    /// ``HLTimeFormat`` so an explicit AM/PM-vs-24h pick is honoured here too.
    public func formatDateTime(
        _ date: Date,
        style: Style = .abbreviated,
        defaults: UserDefaults = .standard
    ) -> String {
        let timeFormat = HLTimeFormat.current(defaults: defaults)
        if Self.pinsChineseWording(order: self) {
            let day = formatDate(date, style: style)
            let clock = Self.chineseTime(date, timeFormat: timeFormat)
            return "\(day) \(clock)"
        }
        let locale = Self.dateTimeLocale(
            dateOrder: formattingLocale,
            timeFormat: timeFormat
        )
        return date.formatted(
            Self.formatStyle(for: style, includeTime: true).locale(locale)
        )
    }

    /// 显式日期顺序下仍使用中文月份和星期。纯数字样式继续走原来的顺序语言。
    private static func pinsChineseWording(order: HLDateFormat) -> Bool {
        guard order != .auto else { return false }
        return AppLocale.shared.current.language.languageCode?.identifier == "zh"
    }

    private static let chineseLocale = Locale(identifier: "zh-Hans")

    private static let chineseDatePatterns: [HLDateFormat: [Style: String]] = [
        .dayMonthYear: [
            .abbreviated: "d MMM y",
            .long: "d MMMM y",
            .complete: "EEE, d MMM y",
        ],
        .monthDayYear: [
            .abbreviated: "MMM d, y",
            .long: "MMMM d, y",
            .complete: "EEE, MMM d, y",
        ],
        .yearMonthDay: [
            .abbreviated: "y年M月d日",
            .long: "y年MMMMd日",
            .complete: "y年M月d日EEE",
        ],
    ]

    private static func chineseNamedDate(_ date: Date, order: HLDateFormat, style: Style) -> String? {
        guard pinsChineseWording(order: order), let pattern = chineseDatePatterns[order]?[style] else { return nil }
        let formatter = DateFormatter()
        formatter.locale = chineseLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// 中文时间。自动沿用中文区域的小时制；12 小时或 24 小时只固定小时制，上午和下午仍是中文。
    private static func chineseTime(_ date: Date, timeFormat: HLTimeFormat) -> String {
        var components = Locale.Components(locale: chineseLocale)
        switch timeFormat {
        case .auto:
            break
        case .twelveHour:
            components.hourCycle = .oneToTwelve
        case .twentyFourHour:
            components.hourCycle = .zeroToTwentyThree
        }
        return date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(components: components))
        )
    }

    /// `AUTO` keeps the date-order locale's hour cycle. H12/H24 pin the cycle
    /// and leave the day and month order untouched.
    private static func dateTimeLocale(dateOrder: Locale, timeFormat: HLTimeFormat) -> Locale {
        let cycle: Locale.HourCycle? = switch timeFormat {
        case .auto: nil
        case .twelveHour: .oneToTwelve
        case .twentyFourHour: .zeroToTwentyThree
        }
        guard let cycle else { return dateOrder }
        var components = Locale.Components(locale: dateOrder)
        components.hourCycle = cycle
        return Locale(components: components)
    }

    private static func formatStyle(for style: Style, includeTime: Bool = false) -> Date.FormatStyle {
        let time: Date.FormatStyle.TimeStyle = includeTime ? .shortened : .omitted
        return switch style {
        case .numeric: Date.FormatStyle(date: .numeric, time: time)
        case .abbreviated: Date.FormatStyle(date: .abbreviated, time: time)
        case .long: Date.FormatStyle(date: .long, time: time)
        case .complete: Date.FormatStyle(date: .complete, time: time)
        }
    }

    // MARK: - Static conveniences (UserDefaults-mirror)

    /// Format `date` with the *currently effective* preference (UserDefaults
    /// mirror). The pure labs / illness / share-link formatters call this so
    /// they need no store dependency.
    public static func date(
        _ date: Date,
        style: Style = .abbreviated,
        defaults: UserDefaults = .standard
    ) -> String {
        current(defaults: defaults).formatDate(date, style: style)
    }

    /// Format `date` (with a short time) using the currently effective
    /// preference (UserDefaults mirror).
    public static func dateTime(
        _ date: Date,
        style: Style = .abbreviated,
        defaults: UserDefaults = .standard
    ) -> String {
        current(defaults: defaults).formatDateTime(date, style: style, defaults: defaults)
    }

    // MARK: - Compact day+month with conditional year (b215)

    /// Compact **day + month** for historical list rows, appending the **year**
    /// only when `date` falls outside `now`'s calendar year. Same-year dates keep
    /// the tight "14. Juni" / "Jun 14" form; a prior- (or future-) year date reads
    /// "14. Juni 2024" / "Jun 14, 2024" so a historical row is never ambiguous
    /// about which year it belongs to.
    ///
    /// Field order, month styling and separators come from `locale` — Foundation
    /// orders day / month / year per the BCP-47 locale, so localisation is
    /// automatic (no hardcoded month names). Month width matches the app's
    /// existing bare `.day().month()` call-sites (`.abbreviated`). `now` and
    /// `calendar` are injected (defaulting to `Date()` / `.current`) so unit
    /// tests can pin them deterministically across time zones.
    public static func dayMonth(
        _ date: Date,
        relativeTo now: Date = Date(),
        locale: Locale = AppLocale.shared.current,
        calendar: Calendar = .current
    ) -> String {
        appendingYearIfNeeded(
            date,
            base: Date.FormatStyle().day().month().locale(locale),
            relativeTo: now,
            calendar: calendar
        )
    }

    /// Append the **year** to an arbitrary day/month `base` style, but only when
    /// `date` isn't in `now`'s calendar year. Lets sites that carry extra
    /// components (a weekday prefix, an `hour().minute()` suffix) share the exact
    /// same "year only when not the current year" decision as
    /// ``dayMonth(_:relativeTo:locale:calendar:)`` instead of duplicating the
    /// `Calendar` year comparison. Foundation slots the appended year into the
    /// locale-correct position, so the rest of the template is untouched.
    public static func appendingYearIfNeeded(
        _ date: Date,
        base: Date.FormatStyle,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let sameYear = calendar.component(.year, from: date)
            == calendar.component(.year, from: now)
        return date.formatted(sameYear ? base : base.year())
    }
}
