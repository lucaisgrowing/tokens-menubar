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
        "action.readToken": ("Private account read token…", "私密账号读取令牌…"),
        "api.configuration": ("Set a username and a valid HTTPS API address first.", "请先配置用户名和有效的 HTTPS API 地址。"),
        "api.notFound": ("Account unreadable: check username, or add a read token for a private account.", "账号不可读取：请检查用户名；私密账号可添加读取令牌。"),
        "api.unauthorized": ("Read token rejected. Update it in Actions & Settings.", "读取令牌无效或无权限，请在操作与设置里更新。"),
        "api.rateLimited": ("Too many requests. Please wait before refreshing.", "请求过于频繁，请稍后再刷新。"),
        "api.network": ("Could not connect. Check the network and retry.", "连接失败，请检查网络后重试。"),
        "api.invalidResponse": ("Unexpected server data. Last good values are kept.", "服务端数据格式异常，已保留上次有效数据。"),
        "api.http": ("Server returned HTTP %d. Please retry later.", "服务端返回 HTTP %d，请稍后重试。"),
        "stamp.fetched": ("Read %@", "获取 %@"),
        "stamp.attempted": ("Last attempt %@", "上次尝试 %@"),
        "stamp.submitted": ("Server submission %@", "服务端提交 %@"),
        "panel.noModels": ("No submitted model breakdown today", "今日暂无已提交的模型明细"),
        "panel.loading": ("Loading all-device usage…", "正在获取全部设备用量…"),
        "panel.localLoading": ("Scanning this Mac…", "正在扫描本机…"),
        "panel.localFallback": ("Showing this Mac only · server unavailable", "仅显示本机 · 尚无服务端数据"),
        "panel.refreshing": ("Refreshing · keeping the current numbers", "刷新中 · 保留当前数据"),
        "panel.refreshingShort": ("refreshing…", "刷新中…"),
        "panel.keptData": ("not updated", "未更新"),
        "panel.estimated": ("costs estimated", "费用为估算"),
        "panel.rankProgress": ("rank progress", "追赶进度"),
        "panel.rankDetail": ("Your tokens ÷ the next person’s tokens. Not a usage quota.", "进度为你的用量 ÷ 上一名用量，不是额度消耗。"),
        "panel.avgDetail": ("Same all-device scope. Middle tick = 7-day average; full track = 2×.", "比较全部设备用量。中线为前 7 日均值，满条为均值的 2 倍。"),
        "panel.avgUnavailable": ("Waiting for a comparable all-device baseline", "暂无可比的全部设备基线"),
        "panel.rankGapUnknown": ("Next-rank gap unavailable", "暂未获取与上一名的差距"),
        "panel.rankUnknown": ("Rank unavailable · not the same as unranked", "暂未获取排名，不代表未上榜"),
        "panel.waitingServer": ("Waiting for server data", "等待服务端数据"),
        "panel.weekLocal": ("This week · Mac", "本周 · 本机"),
        "panel.last7UTC": ("Last 7 days · UTC", "近 7 天 · UTC"),
        "panel.emptyWeek": ("No submitted usage in this period", "这段时间暂无已提交用量"),
        "panel.sourceDetail": ("Main figure: submitted usage across all devices (UTC day). This Mac: live local scan; scopes differ. All costs are estimates, not a bill.", "主数字为全部设备已提交用量（UTC 日界）；本机为实时扫描，两者范围不同。所有费用均为估算，不是账单。"),
        "token.explain": ("Optional for @%1$@ on %2$@. Create a read token in tokens.ci Settings. Stored in macOS Keychain for this account and HTTPS origin; never in config.json. Leave blank to cancel, or choose Remove to use public access.", "用于 %2$@ 的 @%1$@（可选）。在 tokens.ci 设置中创建读取令牌，仅存入此账号及 HTTPS 地址对应的 macOS 钥匙串，不写入配置文件。空白不覆盖已有令牌；移除后使用公开访问。"),
        "token.placeholder": ("tkr_… (new token; existing value stays hidden)", "tkr_…（新令牌；不显示已有内容）"),
        "token.save": ("Save", "保存"),
        "token.cancel": ("Cancel", "取消"),
        "token.remove": ("Remove", "移除"),
        "token.invalid": ("Enter a read token without spaces, or cancel.", "请输入不含空格的读取令牌，或取消。"),
        "token.failed": ("Could not update Keychain. The existing token was not replaced.", "无法更新钥匙串，未替换已有令牌。"),
        "token.hint": ("Add, replace or remove the optional Keychain read token", "添加、替换或移除钥匙串中的可选读取令牌"),

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
        "row.month": ("This month", "本月"),
        "month.projected": ("↳ ~%@ projected at today's pace", "↳ 按当前节奏预计 ~%@"),
        "panel.activeDays": ("Active days  %d", "活跃天数  %d 天"),
        "budget.over": ("⚠ today %1$@ · over the %2$@ budget", "⚠ 今日 %1$@ · 超出预算 %2$@"),

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

        // Rank-move banners. Playful on the way up, encouraging on the way down.
        "move.up": ("🚀 Up to %1$@  ·  +%2$d", "🚀 冲上 %1$@ · 一口气 +%2$d"),
        "move.passed": ("🎉 Passed @%1$@ — now %2$@ (+%3$d)",
                        "🎉 反超 @%1$@，冲上 %2$@（+%3$d）"),
        "move.down": ("Slipped to %1$@ (−%2$d) — claw it back 💪",
                      "被挤到 %1$@（−%2$d），追回来 💪"),
        "move.firstAll": ("👑 You're #1 all-time!", "👑 总榜第 1 名，封神！"),
        "move.firstToday": ("👑 #1 today — top of the board!", "👑 今日榜第 1 名，屠榜了！"),

        "marker.menuBar": ("· menu bar", "· 菜单栏"),
        "stamp.local": ("local %@", "本地 %@"),
        "stamp.server": ("server %@", "服务端 %@"),
        "stamp.stale": ("⚠ server data is stale", "⚠ 服务端数据偏旧"),

        "action.submit": ("Submit Now (tokens submit)", "立即提交 (tokens submit)"),
        "action.submitting": ("Submitting…", "提交中…"),
        // No tick or cross in the text: the panel's badge draws a glyph of its own,
        // and two ticks in a row read as a typo. The plain menu still says which
        // outcome it was in words.
        "action.submitted": ("Submitted %@", "已提交 %@"),
        "action.submitFailed": ("Submit failed %@", "提交失败 %@"),
        "action.refresh": ("Refresh", "刷新"),
        "action.rankMode": ("Rank Shown in Menu Bar", "菜单栏显示排名"),
        "action.openProfile": ("Open tokens.ci Profile", "打开 tokens.ci 主页"),
        "action.shareCard": ("Stats Card", "战绩卡"),
        "card.embedMarkdown": ("Copy Embed Markdown (README)", "复制 Embed Markdown（README）"),
        "card.embedURL": ("Copy Embed Image URL", "复制 Embed 图片 URL"),
        "card.image": ("Copy Card Image", "复制战绩卡图片"),
        "card.pill.md": ("Markdown", "Markdown"),
        "card.pill.url": ("URL", "URL"),
        "card.pill.img": ("Image", "图片"),
        "hint.card": ("Copy the stats card: README markdown, image URL, or an image",
                      "复制战绩卡：README markdown、图片 URL、或一张图"),
        "action.launchAtLogin": ("Launch at Login", "开机启动"),
        "action.checkUpdates": ("Check for Updates…", "检查更新"),
        "action.support": ("Buy Me a Coffee…", "请我喝杯咖啡…"),
        "action.language": ("Language", "语言"),
        "action.quit": ("Quit TokensBar", "退出 TokensBar"),

        "update.checking": ("Checking for updates…", "检查更新中…"),
        "update.upToDate": ("Up to date (v%@)", "已是最新版本（v%@）"),
        "update.available": ("Update available: %1$@ (you have v%2$@)",
                             "有新版本：%1$@（当前 v%2$@）"),
        "update.openPage": ("Update available: %@ — click to install",
                            "有新版本：%@ —— 点击安装"),
        "update.failed": ("Update check failed", "检查更新失败"),
        "update.confirmTitle": ("Install %@?", "安装 %@？"),
        "update.confirmBody": ("TokensBar will download it, replace %@ and restart.",
                               "TokensBar 会下载它，替换 %@ 并重启。"),
        "update.confirmGo": ("Install and Restart", "安装并重启"),
        "update.cancel": ("Cancel", "取消"),
        "update.downloading": ("Downloading %@…", "正在下载 %@…"),
        "update.installing": ("Installing %@ — restarting…", "正在安装 %@ —— 即将重启…"),
        "update.installFailed": ("Update failed — %@", "更新失败 —— %@"),

        "install.readOnly": ("cannot write to %@", "无法写入 %@"),
        "install.download": ("download failed", "下载失败"),
        "install.unpack": ("could not unpack the download", "无法解压下载的文件"),
        "install.setup": ("could not prepare the install", "无法准备安装"),
        "install.contents": ("the download had no app in it", "下载的文件里没有 app"),
        "install.version": ("the download says v%@", "下载到的是 v%@"),

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
        "panel.thisMac": ("this Mac, live  %1$@ · ≈%2$@", "本机实时  %1$@ · ≈%2$@"),
        "panel.localFailed": ("local scan unavailable", "本地扫描不可用"),
        "panel.awaitingSubmit": ("no submission today yet — showing this Mac",
                                 "今天还没提交过 —— 显示的是本机数据"),
        "panel.serverFailedShort": ("server read failed", "服务端读取失败"),
        "panel.toNext": ("%1$@ to #%2$d @%3$@", "距 #%2$d @%3$@ 还差 %1$@"),
        "panel.atTop": ("top of the board", "已经是第 1 名"),
        "panel.notSubmitted": ("nothing submitted today", "今天还没有提交"),
        "panel.vsAvg": ("today / 7-day avg", "今日 / 7 日均值"),
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
        "panel.hint": ("Click a block for detail · right-click the icon for the menu",
                       "点任意区块看详情 · 右键图标打开菜单"),
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
        "hint.quit": ("Quit TokensBar", "退出 TokensBar"),

        "tooltip.localFailed": ("tokens CLI not found, or the local scan failed",
                                "找不到 tokens CLI 或本地扫描失败"),        "tooltip.todayAll": ("%@ tokens today, all devices", "今日 %@ tokens（全部设备）"),
        "tooltip.todayLocal": ("%@ tokens on this Mac, live", "本机实时 %@ tokens"),
        "tooltip.rankAllTime": ("All-time board: #%1$d of %2$d", "累计榜 第 %1$d / %2$d 名"),
        "tooltip.rankToday": ("Today's board: #%1$d of %2$d", "今日榜 第 %1$d / %2$d 名"),
        "tooltip.rankTodayNone": ("Today's board: unranked", "今日榜 未上榜"),
        "tooltip.month": ("This month  %@", "本月  %@"),
        "tooltip.projected": ("Projected  ~%@", "预计  ~%@"),
        "tooltip.overBudget": ("⚠ over today's %@ budget", "⚠ 超出今日预算 %@"),

        "card.copiedMarkdown": ("📋 Embed markdown copied — paste into a README",
                                "📋 Embed markdown 已复制，粘到 README 里"),
        "card.copiedURL": ("📋 Embed image URL copied", "📋 Embed 图片 URL 已复制"),
        "card.copiedImage": ("📋 Card image copied — paste to share", "📋 战绩卡图片已复制，粘贴即可分享"),
        "card.failed": ("Could not render the stats card", "战绩卡生成失败"),
    ]
}

/// Shorthand used throughout the UI code.
func t(_ key: String) -> String { L10n.string(key) }
func t(_ key: String, _ args: CVarArg...) -> String {
    String(format: L10n.string(key), arguments: args)
}
