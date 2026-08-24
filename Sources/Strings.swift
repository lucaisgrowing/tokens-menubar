// Localisation. English is the default; the menu offers a switch and the choice
// persists in UserDefaults. Config key `language` sets the initial value.

import Foundation

enum Lang: String, CaseIterable {
    case en
    case zh

    var displayName: String {
        switch self {
        case .en: return "English"
        case .zh: return "简体中文"
        }
    }
}

enum L10n {
    static var current: Lang = .en

    static func string(_ key: String) -> String {
        guard let entry = table[key] else { return key }
        return current == .zh ? entry.zh : entry.en
    }

    /// Formats with positional specifiers (%1$@ …) so translations can reorder.
    static func string(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), arguments: args)
    }

    static let table: [String: (en: String, zh: String)] = [
        "board.allTime": ("All-time", "累计榜"),
        "board.today": ("Today", "今日榜"),
        "board.notRanked": ("unranked", "未上榜"),
        "board.hint": ("#rank / people on the board; today counts only today's submitters",
                       "#名次 / 榜上总人数；今日榜只算当天提交过的人"),
        "board.explainAllTime": ("All-time = ranked by lifetime tokens",
                                 "累计榜 = 历史总量排名"),
        "board.explainToday": ("Today = ranked by today's submissions only",
                               "今日榜 = 只算当天提交量的排名"),

        "row.lifetime": ("Lifetime", "累计"),
        "row.today": ("Today", "今日"),
        // Sits under the Today row: that row is every device as of the last
        // submission, this one is this machine right now.
        "row.todayLocal": ("↑ all devices · this Mac, live: %1$@  %2$@",
                           "↑ 全部设备累计 · 本机实时 %1$@  %2$@"),
        "row.week": ("This week", "本周"),

        "state.notLoggedIn": ("Not signed in", "未登录"),
        "state.serverFailed": ("Lifetime   server read failed (proxy? tokens.ci unreachable?)",
                               "累计   服务端读取失败（检查代理 / tokens.ci 可达性）"),
        "state.loading": ("Lifetime   loading…", "累计   载入中…"),
        "state.localFailed": ("This Mac   local scan failed (tokens CLI not found?)",
                              "本机   本地扫描失败（找不到 tokens CLI？）"),

        "gap.behind": ("%1$@ · %2$@ behind #%3$d @%4$@", "%1$@ 距 #%3$d @%4$@ 还差 %2$@"),
        "gap.first": ("%@ · you are #1", "%@ 已经是第 1 名"),
        "gap.unranked": ("%@ · unranked — nothing submitted today",
                         "%@ 未上榜 —— 今天还没有提交记录"),

        "marker.menuBar": ("· menu bar", "· 菜单栏"),
        "stamp.local": ("local %@", "本地 %@"),
        "stamp.server": ("server %@", "服务端 %@"),
        "stamp.stale": ("⚠ server data is stale", "⚠ 服务端数据偏旧"),

        "action.submit": ("Submit Now (tokens submit)", "立即提交 (tokens submit)"),
        "action.submitting": ("Submitting…", "提交中…"),
        "action.submitted": ("Submitted ✓ %@", "已提交 ✓ %@"),
        "action.submitFailed": ("Submit failed ✗ %@", "提交失败 ✗ %@"),
        "action.refresh": ("Refresh", "刷新"),
        "action.rankMode": ("Rank Shown in Menu Bar", "菜单栏显示排名"),
        "action.openProfile": ("Open tokens.ci Profile", "打开 tokens.ci 主页"),
        "action.launchAtLogin": ("Launch at Login", "开机启动"),
        "action.checkUpdates": ("Check for Updates…", "检查更新"),
        "action.support": ("Buy Me a Coffee…", "请我喝杯咖啡…"),
        "action.language": ("Language", "语言"),
        "action.numbers": ("All Numbers as Text", "全部数据（文本）"),
        "action.quit": ("Quit TokensBar", "退出 TokensBar"),

        "update.checking": ("Checking for updates…", "检查更新中…"),
        "update.upToDate": ("Up to date (v%@)", "已是最新版本（v%@）"),
        "update.available": ("Update available: %1$@ (you have v%2$@)",
                             "有新版本：%1$@（当前 v%2$@）"),
        "update.openPage": ("Update available: %@ — click to download",
                            "有新版本：%@ —— 点击下载"),
        "update.failed": ("Update check failed", "检查更新失败"),

        "chart.titleToday": ("Today · Model Distribution", "今日 · 模型分布"),
        "chart.titleLifetime": ("Lifetime · Model Distribution", "累计 · 模型分布"),
        "chart.tokens": ("Tokens", "Token"),
        "chart.cost": ("Cost", "费用"),
        "chart.others": ("Others", "其他"),
        "chart.total": ("Total", "合计"),
        "chart.estimated": ("Estimated", "预估"),
        "chart.noData": ("No data", "暂无数据"),
        "chart.hint": ("Click a row above for the model breakdown",
                       "点上面任意一行看模型分布"),

        "heat.title": ("Contributions · daily token activity", "贡献图 · 每日 token 活动"),
        "heat.row": ("Active days", "活跃天数"),
        "heat.activeDays": ("%d active days", "%d 个活跃日"),
        "heat.tokens": ("tokens", "tokens"),
        "heat.messages": ("%@ messages", "%@ 条消息"),
        "heat.models": ("Models", "模型"),
        "heat.clients": ("Clients", "客户端"),
        "heat.cost": ("Cost", "金额"),
        "heat.low": ("Low", "少"),
        "heat.high": ("High", "多"),

        // The drawn dropdown. Captions are uppercased in English at draw time,
        // so they are stored in normal case here.
        "panel.todayAll": ("tokens today · all devices", "今日 tokens · 全部设备"),
        "panel.todayLocalOnly": ("tokens today · this Mac", "今日 tokens · 本机"),
        "panel.thisMac": ("this Mac, live  %1$@ · %2$@", "本机实时  %1$@ · %2$@"),
        "panel.localFailed": ("local scan unavailable", "本地扫描不可用"),
        "panel.awaitingSubmit": ("no submission today yet — showing this Mac",
                                 "今天还没提交过 —— 显示的是本机数据"),
        "panel.serverFailedShort": ("server read failed", "服务端读取失败"),
        "panel.toNext": ("%1$@ to #%2$d @%3$@", "距 #%2$d @%3$@ 还差 %1$@"),
        "panel.atTop": ("top of the board", "已经是第 1 名"),
        "panel.notSubmitted": ("nothing submitted today", "今天还没有提交"),
        "panel.vsAvg": ("today vs 7-day avg", "今日 vs 7 日均值"),
        "panel.avgMultiple": ("%@× avg", "均值的 %@ 倍"),
        "panel.avgPercent": ("%d%% of avg", "均值的 %d%%"),
        "panel.avgBest": ("avg %1$@ · best day %2$@", "均值 %1$@ · 最高 %2$@"),
        "panel.last7": ("last 7 days", "近 7 天"),
        "panel.modelsToday": ("today's models", "今日模型"),
        "panel.allDevices": ("all devices", "全部设备"),
        "panel.thisMacOnly": ("this Mac", "本机"),
        "panel.submit": ("Submit", "提交"),
        "panel.submitting": ("Submitting…", "提交中…"),

        // The footer line: what the pointer is over does, or how the panel works
        // when it is over nothing.
        "panel.hint": ("Click a block for its detail view · right-click for the menu",
                       "点任意区块看详情 · 右键打开菜单"),
        "hint.profile": ("Open your tokens.ci profile in the browser",
                         "在浏览器里打开 tokens.ci 主页"),
        "hint.menu": ("Actions and settings, on a page of this panel",
                      "操作和设置，就在这个面板里翻页"),
        "hint.contrib": ("Open a year of daily activity as a heat grid",
                         "打开一年的每日活动热力图"),
        "hint.chartToday": ("Open today's model distribution", "打开今日模型分布"),
        "hint.chartLifetime": ("Open the lifetime model distribution", "打开累计模型分布"),
        "hint.submit": ("Run tokens submit and refresh", "运行 tokens submit 并刷新"),

        // The actions page inside the panel — the same verbs the right-click menu
        // carries, drawn as a second page rather than a menu on top.
        "menu.title": ("Actions & Settings", "操作与设置"),
        "menu.back": ("Back to the numbers", "返回数据"),
        "menu.version": ("TokensBar v%@", "TokensBar v%@"),
        "hint.back": ("Back to the numbers", "返回数据面板"),
        "hint.refresh": ("Re-read the API and the local CLI now", "立刻重读接口和本地 CLI"),
        "hint.rank": ("Which board the menu bar shows next to the token count",
                      "菜单栏 token 数旁边显示哪个榜"),
        "hint.language": ("Interface language", "界面语言"),
        "hint.login": ("Start TokensBar when you log in", "登录时自动启动 TokensBar"),
        "hint.updates": ("Compare this build against the latest release",
                         "拿当前版本和最新 release 比一下"),
        "hint.support": ("USDT tip addresses, on either chain", "USDT 打赏地址，两条链都行"),
        "hint.numbers": ("The plain text menu, for the keyboard and VoiceOver",
                         "纯文字菜单，给键盘和 VoiceOver 用"),
        "hint.quit": ("Quit TokensBar", "退出 TokensBar"),

        "tooltip.localFailed": ("tokens CLI not found, or the local scan failed",
                                "找不到 tokens CLI 或本地扫描失败"),        "tooltip.todayAll": ("%@ tokens today, all devices", "今日 %@ tokens（全部设备）"),
        "tooltip.todayLocal": ("%@ tokens on this Mac, live", "本机实时 %@ tokens"),
        "tooltip.rankAllTime": ("All-time board: #%1$d of %2$d", "累计榜 第 %1$d / %2$d 名"),
        "tooltip.rankToday": ("Today's board: #%1$d of %2$d", "今日榜 第 %1$d / %2$d 名"),
        "tooltip.rankTodayNone": ("Today's board: unranked", "今日榜 未上榜"),
    ]
}

/// Shorthand used throughout the UI code.
func t(_ key: String) -> String { L10n.string(key) }
func t(_ key: String, _ args: CVarArg...) -> String {
    String(format: L10n.string(key), arguments: args)
}
