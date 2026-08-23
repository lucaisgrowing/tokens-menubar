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

        "tooltip.localFailed": ("tokens CLI not found, or the local scan failed",
                                "找不到 tokens CLI 或本地扫描失败"),
        "tooltip.todayAll": ("%@ tokens today, all devices", "今日 %@ tokens（全部设备）"),
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
