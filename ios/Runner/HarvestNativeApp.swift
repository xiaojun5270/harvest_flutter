import Combine
import Foundation
import SwiftUI
import UIKit

// MARK: - Root

struct HarvestRootView: View {
  @EnvironmentObject private var store: HarvestNativeAppStore

  var body: some View {
    Group {
      if store.session == nil {
        HarvestLoginView()
      } else {
        HarvestShellView()
      }
    }
    .accentColor(HarvestPalette.primary)
    .onAppear {
      store.bootstrapIfNeeded()
    }
    .alert(item: $store.toast) { toast in
      Alert(
        title: Text(toast.title),
        message: Text(toast.message),
        dismissButton: .default(Text("确定"))
      )
    }
  }
}

// MARK: - App Store

@MainActor
final class HarvestNativeAppStore: ObservableObject {
  @Published var session: HarvestSession?
  @Published var selectedTab: HarvestTab = .dashboard
  @Published var lastPrimaryTab: HarvestTab = .dashboard
  @Published var isBootstrapping = false
  @Published var isLoading = false
  @Published var isSearching = false
  @Published var toast: HarvestToast?
  @Published var showDrawer = false
  @Published var showAccountMenu = false
  @Published var privacyMode = false

  @Published var dashboard: HarvestDashboardSnapshot?
  @Published var sites: [HarvestSiteInfo] = []
  @Published var downloaders: [HarvestDownloader] = []
  @Published var schedules: [HarvestSchedule] = []
  @Published var notices: [HarvestNotice] = []
  @Published var tmdbSections: [HarvestMediaSection] = []
  @Published var doubanSections: [HarvestMediaSection] = []
  @Published var searchResults: [HarvestSearchResult] = []

  @Published var savedServer: String = HarvestDefaults.server
  @Published var loginHistory: [HarvestLoginRecord] = HarvestDefaults.loginHistory

  private var didBootstrap = false

  var unreadNotices: [HarvestNotice] {
    notices.filter { !$0.isRead }
  }

  var unreadCount: Int {
    unreadNotices.count
  }

  var currentUserInitial: String {
    guard let name = session?.user.username, let first = name.first else { return "?" }
    return String(first).uppercased()
  }

  func bootstrapIfNeeded() {
    guard !didBootstrap else { return }
    didBootstrap = true
    savedServer = HarvestDefaults.server
    loginHistory = HarvestDefaults.loginHistory
    session = HarvestDefaults.session
    guard session != nil else { return }
    refreshAll(showSpinner: false)
  }

  func login(baseURL: String, username: String, password: String) {
    let normalizedBaseURL = HarvestAPIClient.normalizeBaseURL(baseURL)
    guard !normalizedBaseURL.isEmpty else {
      showError("服务器地址不能为空")
      return
    }
    guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      showError("账号不能为空")
      return
    }

    isLoading = true
    Task {
      do {
        let client = HarvestAPIClient(baseURL: normalizedBaseURL)
        let payload = try await client.request(
          path: HarvestAPI.tokenPair,
          method: "POST",
          body: ["username": username, "password": password],
          authenticated: false
        )
        guard let token = payload as? [String: Any],
              let access = token.string("access").nilIfEmpty else {
          throw HarvestAPIError.message("登录接口没有返回 token")
        }

        let refresh = token.string("refresh").nilIfEmpty
        var user = HarvestUser(id: 0, username: username)
        let draftSession = HarvestSession(
          baseURL: normalizedBaseURL,
          accessToken: access,
          refreshToken: refresh,
          user: user
        )
        session = draftSession
        HarvestDefaults.session = draftSession
        HarvestDefaults.server = normalizedBaseURL
        savedServer = normalizedBaseURL
        HarvestDefaults.addLoginRecord(
          HarvestLoginRecord(server: normalizedBaseURL, username: username, password: password)
        )
        loginHistory = HarvestDefaults.loginHistory

        if let userPayload = try? await authenticatedRequest(path: HarvestAPI.userInfo),
           let userInfo = userPayload as? [String: Any] {
          user = HarvestUser(json: userInfo, fallbackName: username)
          if var updatedSession = session {
            updatedSession.user = user
            session = updatedSession
            HarvestDefaults.session = updatedSession
          }
        }

        selectedTab = .dashboard
        lastPrimaryTab = .dashboard
        await loadAll()
      } catch {
        showError(error.harvestMessage)
      }
      isLoading = false
    }
  }

  func logout(clearHistory: Bool = false) {
    HarvestDefaults.session = nil
    if clearHistory {
      HarvestDefaults.loginHistory = []
      loginHistory = []
    }
    session = nil
    dashboard = nil
    sites = []
    downloaders = []
    schedules = []
    notices = []
    tmdbSections = []
    doubanSections = []
    searchResults = []
    selectedTab = .dashboard
    showDrawer = false
    showAccountMenu = false
  }

  func clearPersistentData() {
    HarvestDefaults.clearAll()
    savedServer = ""
    loginHistory = []
    logout()
    showInfo("已清理本地登录态和历史记录")
  }

  func openSearch() {
    lastPrimaryTab = selectedTab.isPrimary ? selectedTab : lastPrimaryTab
    selectedTab = .search
  }

  func closeSearch() {
    selectedTab = lastPrimaryTab.isPrimary ? lastPrimaryTab : .dashboard
  }

  func selectTab(_ tab: HarvestTab) {
    guard tab != .search else {
      openSearch()
      return
    }
    selectedTab = tab
    lastPrimaryTab = tab
    refresh(tab: tab, showSpinner: false)
  }

  func refreshCurrentTab() {
    refresh(tab: selectedTab, showSpinner: true)
  }

  func refreshAll(showSpinner: Bool = true) {
    if showSpinner { isLoading = true }
    Task {
      await loadAll()
      if showSpinner { isLoading = false }
    }
  }

  func refresh(tab: HarvestTab, showSpinner: Bool) {
    if showSpinner { isLoading = true }
    Task {
      switch tab {
      case .news:
        await loadNews()
      case .sites:
        await loadSites()
      case .dashboard:
        await loadDashboard()
      case .downloads:
        await loadDownloaders()
      case .tasks:
        await loadSchedules()
      case .search:
        break
      }
      await loadNotices()
      if showSpinner { isLoading = false }
    }
  }

  func markNoticeRead(_ notice: HarvestNotice) {
    guard notice.id > 0 else { return }
    Task {
      do {
        _ = try await authenticatedRequest(
          path: "\(HarvestAPI.noticeHistory)/\(notice.id)/read",
          method: "PUT"
        )
        notices = notices.map { $0.id == notice.id ? $0.markedRead() : $0 }
        HarvestBadge.setBadgeCount(unreadCount)
      } catch {
        showError(error.harvestMessage)
      }
    }
  }

  func runSiteAction(_ action: HarvestSiteAction, site: HarvestSiteInfo) {
    let path: String
    let fallback: String
    switch action {
    case .refresh:
      path = "\(HarvestAPI.mySiteStatusOperate)\(site.id)"
      fallback = "刷新成功"
    case .signIn:
      path = "\(HarvestAPI.mySiteSignInOperate)\(site.id)"
      fallback = "签到任务已执行"
    case .repeatTorrent:
      path = "\(HarvestAPI.mySiteRepeatOperate)\(site.id)"
      fallback = "辅种任务已提交"
    }

    Task {
      do {
        let value = try await authenticatedRequest(path: path)
        showInfo(HarvestAPIClient.message(from: value) ?? fallback)
        await loadSites()
        await loadDashboard()
      } catch {
        showError(error.harvestMessage)
      }
    }
  }

  func toggleSchedule(_ schedule: HarvestSchedule) {
    Task {
      do {
        _ = try await authenticatedRequest(
          path: HarvestAPI.schedule,
          method: "PUT",
          body: ["id": schedule.id, "enabled": !schedule.enabled]
        )
        schedules = schedules.map { item in
          item.id == schedule.id ? item.toggled() : item
        }
      } catch {
        showError(error.harvestMessage)
      }
    }
  }

  func runSchedule(_ schedule: HarvestSchedule) {
    Task {
      do {
        _ = try await authenticatedRequest(
          path: HarvestAPI.taskExec,
          query: ["task_id": "\(schedule.id)"]
        )
        showInfo("任务已提交")
      } catch {
        showError(error.harvestMessage)
      }
    }
  }

  func search(_ query: String, source: HarvestSearchSource) {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      searchResults = []
      return
    }

    isSearching = true
    Task {
      do {
        var results: [HarvestSearchResult] = []
        if source == .all || source == .tmdb {
          let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
          let payload = try await authenticatedRequest(path: "\(HarvestAPI.tmdbSearch)/\(encoded)")
          results += HarvestSearchResult.tmdbList(from: payload)
        }
        if source == .all || source == .douban {
          let payload = try await authenticatedRequest(
            path: HarvestAPI.doubanSearch,
            query: ["q": trimmed]
          )
          results += HarvestSearchResult.doubanList(from: payload)
        }
        searchResults = results
      } catch {
        showError(error.harvestMessage)
      }
      isSearching = false
    }
  }

  private func loadAll() async {
    await loadDashboard()
    await loadSites()
    await loadDownloaders()
    await loadSchedules()
    await loadNews()
    await loadNotices()
  }

  private func loadDashboard() async {
    do {
      let payload = try await authenticatedRequest(
        path: HarvestAPI.dashboard,
        query: ["days": "30"]
      )
      if let json = payload as? [String: Any] {
        dashboard = HarvestDashboardSnapshot(json: json)
      }
    } catch {
      softFail(error)
    }
  }

  private func loadSites() async {
    do {
      let payload = try await authenticatedRequest(
        path: HarvestAPI.mySiteList,
        query: ["cached": "true"]
      )
      sites = HarvestSiteInfo.list(from: payload)
    } catch {
      softFail(error)
    }
  }

  private func loadDownloaders() async {
    do {
      let payload = try await authenticatedRequest(
        path: HarvestAPI.downloaderList,
        query: ["with_status": "true"]
      )
      downloaders = HarvestDownloader.list(from: payload)
    } catch {
      softFail(error)
    }
  }

  private func loadSchedules() async {
    do {
      let payload = try await authenticatedRequest(path: HarvestAPI.schedule)
      schedules = HarvestSchedule.list(from: payload)
    } catch {
      softFail(error)
    }
  }

  private func loadNotices() async {
    do {
      let payload = try await authenticatedRequest(path: HarvestAPI.noticeHistory)
      notices = HarvestNotice.list(from: payload)
      HarvestBadge.setBadgeCount(unreadCount)
    } catch {
      softFail(error)
    }
  }

  private func loadNews() async {
    await loadTMDB()
    await loadDouban()
  }

  private func loadTMDB() async {
    let requests: [(String, String, String)] = [
      ("正在上映", HarvestAPI.tmdbPlayingMovies, "movie"),
      ("热门电影", HarvestAPI.tmdbPopularMovies, "movie"),
      ("即将上映", HarvestAPI.tmdbUpcomingMovies, "movie"),
      ("热门剧集", HarvestAPI.tmdbPopularTV, "tv")
    ]

    var sections: [HarvestMediaSection] = []
    for request in requests {
      do {
        let payload = try await authenticatedRequest(
          path: request.1,
          query: ["page": "1"]
        )
        let items = HarvestMediaItem.tmdbList(from: payload, mediaType: request.2)
        sections.append(HarvestMediaSection(title: request.0, source: .tmdb, items: items))
      } catch {
        softFail(error)
      }
    }
    tmdbSections = sections
  }

  private func loadDouban() async {
    let requests: [(String, String, [String: String])] = [
      ("豆瓣热门电影", HarvestAPI.doubanHot, ["category": "movie", "tag": "热门", "page_start": "0", "page_limit": "20"]),
      ("豆瓣热门剧集", HarvestAPI.doubanHot, ["category": "tv", "tag": "热门", "page_start": "0", "page_limit": "20"]),
      ("豆瓣 Top250", HarvestAPI.doubanTop250, [:])
    ]

    var sections: [HarvestMediaSection] = []
    for request in requests {
      do {
        let payload = try await authenticatedRequest(path: request.1, query: request.2)
        let items = HarvestMediaItem.doubanList(from: payload)
        sections.append(HarvestMediaSection(title: request.0, source: .douban, items: items))
      } catch {
        softFail(error)
      }
    }
    doubanSections = sections
  }

  private func authenticatedRequest(
    path: String,
    method: String = "GET",
    query: [String: String] = [:],
    body: [String: Any]? = nil
  ) async throws -> Any {
    guard var current = session else { throw HarvestAPIError.unauthorized }
    do {
      return try await HarvestAPIClient(
        baseURL: current.baseURL,
        accessToken: current.accessToken
      ).request(path: path, method: method, query: query, body: body, authenticated: true)
    } catch HarvestAPIError.unauthorized {
      guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
        logout()
        throw HarvestAPIError.message("登录已过期，请重新登录")
      }
      let refreshed = try await HarvestAPIClient(baseURL: current.baseURL)
        .refreshToken(refreshToken)
      current.accessToken = refreshed.access
      if let refresh = refreshed.refresh {
        current.refreshToken = refresh
      }
      session = current
      HarvestDefaults.session = current
      return try await HarvestAPIClient(
        baseURL: current.baseURL,
        accessToken: current.accessToken
      ).request(path: path, method: method, query: query, body: body, authenticated: true)
    }
  }

  private func softFail(_ error: Error) {
    if let apiError = error as? HarvestAPIError,
       case .unauthorized = apiError {
      logout()
      return
    }
  }

  func showInfo(_ message: String) {
    toast = HarvestToast(title: "Harvest", message: message)
  }

  func showError(_ message: String) {
    toast = HarvestToast(title: "操作失败", message: message)
  }
}

// MARK: - Login

struct HarvestLoginView: View {
  @EnvironmentObject private var store: HarvestNativeAppStore
  @State private var server = HarvestDefaults.server.isEmpty ? "http://127.0.0.1:8000" : HarvestDefaults.server
  @State private var username = ""
  @State private var password = ""
  @State private var showPassword = false

  var body: some View {
    ZStack {
      HarvestAppBackground()

      ScrollView {
        VStack(spacing: 0) {
          Spacer(minLength: 64)

          VStack(spacing: 18) {
            HarvestLogoMark(size: 96)

            Text("PT 一下")
              .font(.system(size: 24, weight: .heavy))
              .foregroundColor(HarvestPalette.text)

            VStack(spacing: 12) {
              HarvestTextField(
                title: "服务器地址",
                text: $server,
                systemImage: "network"
              )

              HarvestTextField(
                title: "账号",
                text: $username,
                systemImage: "person.crop.circle"
              )

              HarvestPasswordField(
                title: "密码",
                text: $password,
                showPassword: $showPassword
              )
            }

            HStack(spacing: 10) {
              Button(action: submit) {
                HStack {
                  if store.isLoading {
                    ProgressView()
                      .progressViewStyle(CircularProgressViewStyle())
                      .accentColor(.white)
                      .scaleEffect(0.78)
                  }
                  Text(store.isLoading ? "登录中..." : "登录")
                    .font(.system(size: 15, weight: .heavy))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(HarvestPalette.primaryGradient)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(HarvestRoundedBorder(radius: 8, color: Color.white, opacity: 0.20))
              }
              .disabled(store.isLoading)

              HarvestIconButton(systemImage: "clock.arrow.2.circlepath") {
                fillLatestHistory()
              }
              .disabled(store.loginHistory.isEmpty)

              HarvestIconButton(systemImage: "waveform.path.ecg.rectangle") {
                store.showInfo("SwiftUI 原生复制版日志中心")
              }

              HarvestIconButton(systemImage: "trash") {
                store.clearPersistentData()
              }
            }

            HStack(spacing: 10) {
              HarvestSymbolBadge(systemImage: "arrow.down.circle.fill", color: HarvestPalette.primary, size: 28, iconSize: 13)
              Text("APP 升级")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(HarvestPalette.primary)
              Spacer()
              Text("Harvest iOS SwiftUI")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(HarvestPalette.secondaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(HarvestGlassBackground(radius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.30))
          }
          .padding(20)
          .frame(maxWidth: 440)
          .background(HarvestGlassBackground(radius: 8))
          .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.30))
          .shadow(color: HarvestPalette.shadow, radius: 28, x: 0, y: 18)

          Spacer(minLength: 56)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
      }
    }
  }

  private func submit() {
    store.login(baseURL: server, username: username, password: password)
  }

  private func fillLatestHistory() {
    guard let latest = store.loginHistory.first else { return }
    server = latest.server
    username = latest.username
    password = latest.password
  }
}

// MARK: - Shell

struct HarvestShellView: View {
  @EnvironmentObject private var store: HarvestNativeAppStore

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottom) {
        HarvestAppBackground()

        VStack(spacing: 0) {
          if store.selectedTab != .search {
            HarvestShellHeader()
          }
          HarvestContentView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        if store.selectedTab != .search {
          HarvestBottomControls(bottomInset: HarvestSafeArea.insets.bottom)
        }

        if store.isLoading {
          HarvestLoadingOverlay()
        }

        if store.showDrawer {
          HarvestDrawerOverlay()
        }

        if store.showAccountMenu {
          HarvestAccountMenuOverlay(topInset: HarvestSafeArea.insets.top)
        }
      }
    }
  }
}

struct HarvestContentView: View {
  @EnvironmentObject private var store: HarvestNativeAppStore

  var body: some View {
    Group {
      switch store.selectedTab {
      case .news:
        HarvestNewsPage()
      case .sites:
        HarvestSitesPage()
      case .dashboard:
        HarvestDashboardPage()
      case .downloads:
        HarvestDownloadsPage()
      case .tasks:
        HarvestTasksPage()
      case .search:
        HarvestSearchPage()
      }
    }
  }
}

struct HarvestShellHeader: View {
  @EnvironmentObject private var store: HarvestNativeAppStore

  var body: some View {
    HStack(spacing: 10) {
      HarvestHeaderIcon(systemImage: "sidebar.left") {
        withAnimation(.easeOut(duration: 0.2)) {
          store.showDrawer = true
        }
      }

      Group {
        if let notice = store.unreadNotices.first {
          HarvestNoticeTicker(notice: notice, count: store.unreadCount)
        } else {
          VStack(alignment: .leading, spacing: 2) {
            Text(store.selectedTab.title)
              .font(.system(size: 20, weight: .heavy))
              .foregroundColor(HarvestPalette.text)
              .lineLimit(1)
            Text(store.selectedTab.subtitle)
              .font(.system(size: 11, weight: .semibold))
              .foregroundColor(HarvestPalette.secondaryText)
              .lineLimit(1)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      HarvestHeaderNoticeButton()

      HarvestHeaderIcon(systemImage: "arrow.down.circle.fill") {
        store.showInfo("当前为 SwiftUI 原生复制版")
      }
      .overlay(
        Circle()
          .fill(HarvestPalette.danger)
          .frame(width: 7, height: 7)
          .offset(x: 9, y: -9),
        alignment: .topTrailing
      )

      Button(action: {
        withAnimation(.easeOut(duration: 0.18)) {
          store.showAccountMenu = true
        }
      }) {
        Text(store.currentUserInitial)
          .font(.system(size: 15, weight: .black))
          .frame(width: 34, height: 34)
          .background(HarvestPalette.primaryGradient)
          .foregroundColor(.white)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .overlay(HarvestRoundedBorder(radius: 8, color: Color.white, opacity: 0.22))
      }
      .buttonStyle(PlainButtonStyle())
    }
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .padding(.bottom, 8)
    .background(HarvestGlassBackground(radius: 0))
    .overlay(
      Rectangle()
        .fill(HarvestPalette.border.opacity(0.20))
        .frame(height: 1),
      alignment: .bottom
    )
  }
}

struct HarvestNoticeTicker: View {
  @EnvironmentObject private var store: HarvestNativeAppStore
  let notice: HarvestNotice
  let count: Int

  var body: some View {
    Button(action: {
      store.markNoticeRead(notice)
    }) {
      HStack(spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(HarvestPalette.danger)
            .frame(width: 24, height: 24)
          Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 8, weight: .black))
            .foregroundColor(.white)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(notice.title.isEmpty ? "未命名通知" : notice.title)
            .font(.system(size: 13, weight: .heavy))
            .foregroundColor(HarvestPalette.text)
            .lineLimit(1)
          Text(notice.cleanContent)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(HarvestPalette.secondaryText)
            .lineLimit(1)
        }
        Image(systemName: "checkmark")
          .font(.system(size: 13, weight: .heavy))
          .foregroundColor(HarvestPalette.secondaryText)
      }
      .padding(.horizontal, 10)
      .frame(height: 38)
      .background(HarvestGlassBackground(radius: 8))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.26))
    }
    .buttonStyle(PlainButtonStyle())
  }
}

struct HarvestHeaderNoticeButton: View {
  @EnvironmentObject private var store: HarvestNativeAppStore

  var body: some View {
    HarvestHeaderIcon(systemImage: "bell.fill") {
      if let first = store.unreadNotices.first {
        store.markNoticeRead(first)
      } else {
        store.refresh(tab: store.selectedTab, showSpinner: false)
      }
    }
    .overlay(
      Group {
        if store.unreadCount > 0 {
          Text(store.unreadCount > 99 ? "99+" : "\(store.unreadCount)")
            .font(.system(size: 8, weight: .black))
            .padding(.horizontal, 4)
            .frame(minWidth: 14, minHeight: 14)
            .background(HarvestPalette.danger)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .offset(x: 8, y: -10)
        }
      },
      alignment: .topTrailing
    )
  }
}

struct HarvestBottomControls: View {
  @EnvironmentObject private var store: HarvestNativeAppStore
  let bottomInset: CGFloat

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      HStack(spacing: 0) {
        ForEach(HarvestTab.primaryTabs) { tab in
          HarvestBottomTabButton(
            tab: tab,
            selected: store.selectedTab == tab,
            action: { store.selectTab(tab) }
          )
        }
      }
      .frame(height: 62)
      .background(HarvestGlassBackground(radius: 8))
      .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.28))

      Button(action: { store.openSearch() }) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 22, weight: .heavy))
          .foregroundColor(.white)
          .frame(width: 62, height: 62)
          .background(HarvestPalette.primaryGradient)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .overlay(HarvestRoundedBorder(radius: 8, color: Color.white, opacity: 0.22))
          .shadow(color: HarvestPalette.primary.opacity(0.30), radius: 18, x: 0, y: 10)
      }
      .buttonStyle(PlainButtonStyle())
    }
    .padding(.horizontal, 12)
    .padding(.bottom, bottomInset + 8)
  }
}

struct HarvestBottomTabButton: View {
  let tab: HarvestTab
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: selected ? tab.selectedSystemImage : tab.systemImage)
          .font(.system(size: selected ? 22 : 21, weight: .heavy))
        Text(tab.shortTitle)
          .font(.system(size: 10, weight: selected ? .heavy : .semibold))
      }
      .foregroundColor(selected ? HarvestPalette.primary : HarvestPalette.secondaryText)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        Group {
          if selected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(
                LinearGradient(
                  gradient: Gradient(colors: [
                    HarvestPalette.primary.opacity(0.16),
                    HarvestPalette.cyan.opacity(0.09)
                  ]),
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
              .padding(.vertical, 5)
              .padding(.horizontal, 4)
          }
        }
      )
      .overlay(
        Group {
          if selected {
            Capsule()
              .fill(HarvestPalette.primary)
              .frame(width: 18, height: 2)
              .offset(y: 23)
          }
        }
      )
    }
    .buttonStyle(PlainButtonStyle())
  }
}

// MARK: - Dashboard

struct HarvestDashboardPage: View {
  @EnvironmentObject private var store: HarvestNativeAppStore

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      ScrollView {
        VStack(spacing: 12) {
          if let data = store.dashboard {
            HarvestDashboardHero(data: data, privacy: store.privacyMode)
            HarvestDashboardSummaryGrid(data: data, privacy: store.privacyMode)
            HarvestDashboardQuickActions()
            HarvestDistributionCard(title: "做种体积", items: data.seedItems)
            HarvestDistributionCard(title: "今日增量", items: data.incrementItems)
          } else {
            HarvestEmptyState(
              systemImage: "chart.bar",
              title: "暂无仪表盘数据",
              subtitle: "登录后刷新即可查看站点数量、上传下载、做种体积和今日增量。"
            )
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 104)
      }

      VStack(spacing: 8) {
        HarvestFloatingButton(systemImage: store.privacyMode ? "eye.slash.fill" : "eye.fill") {
          store.privacyMode.toggle()
        }
        HarvestFloatingButton(systemImage: "arrow.clockwise.circle.fill") {
          store.refresh(tab: .dashboard, showSpinner: true)
        }
        HarvestFloatingButton(systemImage: "slider.horizontal.3") {
          store.showInfo("图表设置已在 SwiftUI 版中保留入口")
        }
      }
      .padding(.trailing, 12)
      .padding(.bottom, 104)
    }
    .onAppear {
      if store.dashboard == nil {
        store.refresh(tab: .dashboard, showSpinner: false)
      }
    }
  }
}

struct HarvestDashboardHero: View {
  let data: HarvestDashboardSnapshot
  let privacy: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        HarvestSymbolBadge(systemImage: "chart.bar.fill", color: HarvestPalette.primary, size: 44, iconSize: 20)
        VStack(alignment: .leading, spacing: 4) {
          Text("总览")
            .font(.system(size: 14, weight: .heavy))
            .foregroundColor(HarvestPalette.secondaryText)
          Text(privacy ? "***" : "\(Int(data.siteCount)) 个站点")
            .font(.system(size: 30, weight: .black))
            .foregroundColor(HarvestPalette.text)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 4) {
          Text(data.designation)
            .font(.system(size: 13, weight: .heavy))
            .foregroundColor(HarvestPalette.danger)
          Text(data.updatedText)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(HarvestPalette.secondaryText)
        }
      }

      HStack(spacing: 8) {
        HarvestHeroMetric(title: "上传", value: privacy ? "***" : data.totalUploadedText, color: HarvestPalette.success)
        HarvestHeroMetric(title: "下载", value: privacy ? "***" : data.totalDownloadedText, color: HarvestPalette.primary)
      }

      HarvestHeroActivityStrip(items: data.incrementItems)
    }
    .padding(16)
    .background(
      LinearGradient(
        gradient: Gradient(colors: [
          HarvestPalette.card,
          HarvestPalette.primary.opacity(0.12),
          HarvestPalette.mint.opacity(0.10),
          HarvestPalette.warning.opacity(0.06)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.32))
    .shadow(color: HarvestPalette.shadow, radius: 18, x: 0, y: 8)
  }
}

struct HarvestHeroActivityStrip: View {
  let items: [HarvestMetricItem]

  var body: some View {
    HStack(alignment: .bottom, spacing: 5) {
      ForEach(Array(displayItems.enumerated()), id: \.offset) { pair in
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(pair.element.color.opacity(pair.offset == 0 ? 0.95 : 0.72))
          .frame(height: 9 + CGFloat(pair.element.ratio) * 22)
          .frame(maxWidth: .infinity)
      }
    }
    .frame(height: 34)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.white.opacity(0.12))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(HarvestRoundedBorder(radius: 8, color: Color.white, opacity: 0.16))
  }

  private var displayItems: [HarvestMetricItem] {
    let source = Array(items.prefix(7))
    guard !source.isEmpty else {
      return [
        HarvestMetricItem(name: "1", value: 0, displayValue: "", ratio: 0.80, color: HarvestPalette.primary),
        HarvestMetricItem(name: "2", value: 0, displayValue: "", ratio: 0.48, color: HarvestPalette.mint),
        HarvestMetricItem(name: "3", value: 0, displayValue: "", ratio: 0.66, color: HarvestPalette.warning),
        HarvestMetricItem(name: "4", value: 0, displayValue: "", ratio: 0.36, color: HarvestPalette.cyan),
        HarvestMetricItem(name: "5", value: 0, displayValue: "", ratio: 0.58, color: HarvestPalette.indigo)
      ]
    }
    return source
  }
}

struct HarvestHeroMetric: View {
  let title: String
  let value: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(HarvestPalette.secondaryText)
      Text(value)
        .font(.system(size: 17, weight: .black))
        .foregroundColor(HarvestPalette.text)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(color.opacity(0.10))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct HarvestDashboardSummaryGrid: View {
  let data: HarvestDashboardSnapshot
  let privacy: Bool
  private let columns = [GridItem(.flexible()), GridItem(.flexible())]

  var body: some View {
    LazyVGrid(columns: columns, spacing: 10) {
      HarvestStatCard(title: "今日上传", value: privacy ? "***" : data.todayUploadText, systemImage: "arrow.up.right.circle.fill", color: HarvestPalette.success)
      HarvestStatCard(title: "今日下载", value: privacy ? "***" : data.todayDownloadText, systemImage: "arrow.down.right.circle.fill", color: HarvestPalette.primary)
      HarvestStatCard(title: "做种数", value: privacy ? "***" : "\(Int(data.totalSeeding))", systemImage: "leaf.fill", color: HarvestPalette.warning)
      HarvestStatCard(title: "总发布", value: privacy ? "***" : "\(Int(data.totalPublished))", systemImage: "doc.text.fill", color: HarvestPalette.danger)
    }
  }
}

struct HarvestDashboardQuickActions: View {
  @EnvironmentObject private var store: HarvestNativeAppStore

  var body: some View {
    HStack(spacing: 10) {
      HarvestActionTile(title: "刷新数据", systemImage: "arrow.clockwise.circle.fill", color: HarvestPalette.primary) {
        store.refresh(tab: .dashboard, showSpinner: true)
      }
      HarvestActionTile(title: "站点任务", systemImage: "bolt.circle.fill", color: HarvestPalette.warning) {
        store.showInfo("站点数据任务已保留入口")
      }
      HarvestActionTile(title: "签到", systemImage: "checkmark.seal.fill", color: HarvestPalette.success) {
        store.showInfo("站点签到任务已保留入口")
      }
    }
  }
}

struct HarvestDistributionCard: View {
  let title: String
  let items: [HarvestMetricItem]

  var body: some View {
    HarvestCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          HarvestSymbolBadge(systemImage: "chart.pie.fill", color: HarvestPalette.indigo, size: 28, iconSize: 13)
          Text(title)
            .font(.system(size: 15, weight: .heavy))
            .foregroundColor(HarvestPalette.text)
          Spacer()
        }

        if items.isEmpty {
          Text("暂无数据")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(HarvestPalette.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 48)
        } else {
          VStack(spacing: 9) {
            ForEach(items.prefix(6)) { item in
              HarvestMetricBar(item: item)
            }
          }
        }
      }
    }
  }
}

struct HarvestMetricBar: View {
  let item: HarvestMetricItem

  var body: some View {
    VStack(spacing: 5) {
      HStack {
        Text(item.name)
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(HarvestPalette.text)
          .lineLimit(1)
        Spacer()
        Text(item.displayValue)
          .font(.system(size: 12, weight: .heavy))
          .foregroundColor(HarvestPalette.secondaryText)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(HarvestPalette.field)
          Capsule()
            .fill(
              LinearGradient(
                gradient: Gradient(colors: [item.color.opacity(0.72), item.color]),
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .frame(width: max(8, proxy.size.width * CGFloat(item.ratio)))
            .shadow(color: item.color.opacity(0.22), radius: 6, x: 0, y: 2)
        }
      }
      .frame(height: 7)
    }
    .padding(9)
    .background(HarvestPalette.field.opacity(0.60))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

// MARK: - Sites

struct HarvestSitesPage: View {
  @EnvironmentObject private var store: HarvestNativeAppStore
  @State private var query = ""

  private var filteredSites: [HarvestSiteInfo] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return store.sites }
    return store.sites.filter {
      $0.displayName.localizedCaseInsensitiveContains(trimmed) ||
      $0.site.localizedCaseInsensitiveContains(trimmed)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Text("\(filteredSites.count)")
          .font(.system(size: 14, weight: .black))
          .foregroundColor(query.isEmpty ? HarvestPalette.text : HarvestPalette.primary)
        Text("/ \(store.sites.count)")
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(HarvestPalette.secondaryText)

        HarvestTextField(title: "搜索站点...", text: $query, systemImage: "magnifyingglass.circle.fill", compact: true)

        HarvestHeaderIcon(systemImage: "line.3.horizontal.decrease.circle") {
          store.showInfo("筛选面板已保留入口")
        }
        HarvestHeaderIcon(systemImage: "plus.circle.fill") {
          store.showInfo("添加站点已保留入口")
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 8)
      .background(HarvestGlassBackground(radius: 0))
      .overlay(
        Rectangle()
          .fill(HarvestPalette.border.opacity(0.18))
          .frame(height: 1),
        alignment: .bottom
      )

      ScrollView {
        if filteredSites.isEmpty {
          HarvestEmptyState(
            systemImage: query.isEmpty ? "network" : "magnifyingglass.circle.fill",
            title: query.isEmpty ? "暂无站点数据" : "没有符合筛选条件的站点",
            subtitle: query.isEmpty ? "可以从内置配置添加站点，或上传自定义 TOML 配置。" : "清空搜索条件后重新查看。"
          )
          .padding(.top, 84)
        } else {
          LazyVStack(spacing: 10) {
            ForEach(filteredSites) { site in
              HarvestSiteCard(site: site)
            }
          }
          .padding(.horizontal, 12)
          .padding(.top, 6)
          .padding(.bottom, 104)
        }
      }
    }
    .onAppear {
      if store.sites.isEmpty {
        store.refresh(tab: .sites, showSpinner: false)
      }
    }
  }
}

struct HarvestSiteCard: View {
  @EnvironmentObject private var store: HarvestNativeAppStore
  let site: HarvestSiteInfo

  var body: some View {
    HarvestCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 10) {
          HarvestSymbolBadge(
            systemImage: site.available ? "checkmark.circle.fill" : "pause.circle.fill",
            color: site.available ? HarvestPalette.success : HarvestPalette.secondaryText,
            size: 34,
            iconSize: 16
          )

          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
              Text(site.displayName)
                .font(.system(size: 16, weight: .black))
                .foregroundColor(HarvestPalette.text)
                .lineLimit(1)
              if site.signInText != nil {
                HarvestPill(text: "已签到", color: HarvestPalette.success)
              }
            }
            Text(site.site)
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(HarvestPalette.secondaryText)
              .lineLimit(1)
          }

          Spacer()
          HarvestPill(text: site.available ? "可用" : "禁用", color: site.available ? HarvestPalette.success : HarvestPalette.danger)
        }

        HStack(spacing: 8) {
          HarvestMiniMetric(title: "上传", value: site.uploadedText, systemImage: "arrow.up.right.circle.fill")
          HarvestMiniMetric(title: "下载", value: site.downloadedText, systemImage: "arrow.down.right.circle.fill")
          HarvestMiniMetric(title: "分享率", value: site.ratioText, systemImage: "percent")
        }

        HStack(spacing: 8) {
          HarvestSmallAction(title: "刷新", systemImage: "arrow.clockwise.circle.fill") {
            store.runSiteAction(.refresh, site: site)
          }
          HarvestSmallAction(title: "签到", systemImage: "checkmark.circle.fill") {
            store.runSiteAction(.signIn, site: site)
          }
          HarvestSmallAction(title: "辅种", systemImage: "bolt.circle.fill") {
            store.runSiteAction(.repeatTorrent, site: site)
          }
        }
      }
    }
  }
}

// MARK: - News

struct HarvestNewsPage: View {
  @EnvironmentObject private var store: HarvestNativeAppStore
  @State private var source: HarvestMediaSource = .tmdb

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        HarvestSegmentedPicker(
          items: HarvestMediaSource.allCases,
          selection: $source
        )
        Spacer()
        HarvestHeaderIcon(systemImage: "arrow.clockwise.circle.fill") {
          store.refresh(tab: .news, showSpinner: true)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(HarvestGlassBackground(radius: 0))
      .overlay(
        Rectangle()
          .fill(HarvestPalette.border.opacity(0.18))
          .frame(height: 1),
        alignment: .bottom
      )

      ScrollView {
        let sections = source == .tmdb ? store.tmdbSections : store.doubanSections
        if sections.flatMap({ $0.items }).isEmpty {
          HarvestEmptyState(
            systemImage: "sparkles",
            title: "暂无资讯数据",
            subtitle: "刷新后可查看 TMDB 和豆瓣的热门影视信息。"
          )
          .padding(.top, 84)
        } else {
          LazyVStack(spacing: 16) {
            ForEach(sections) { section in
              HarvestMediaSectionView(section: section)
            }
          }
          .padding(.top, 6)
          .padding(.bottom, 104)
        }
      }
    }
    .onAppear {
      if store.tmdbSections.isEmpty && store.doubanSections.isEmpty {
        store.refresh(tab: .news, showSpinner: false)
      }
    }
  }
}

struct HarvestMediaSectionView: View {
  let section: HarvestMediaSection

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        HarvestSymbolBadge(systemImage: section.source.systemImage, color: section.source.color, size: 28, iconSize: 13)
        Text(section.title)
          .font(.system(size: 16, weight: .black))
          .foregroundColor(HarvestPalette.text)
        Spacer()
      }
      .padding(.horizontal, 12)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(section.items.prefix(20)) { item in
            HarvestMediaCard(item: item)
          }
        }
        .padding(.horizontal, 12)
      }
    }
  }
}

struct HarvestMediaCard: View {
  let item: HarvestMediaItem

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      RemoteImageView(urlString: item.posterURL)
        .frame(width: 122, height: 180)
        .background(HarvestPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.20))
        .shadow(color: HarvestPalette.shadow, radius: 14, x: 0, y: 7)

      Text(item.title)
        .font(.system(size: 13, weight: .heavy))
        .foregroundColor(HarvestPalette.text)
        .lineLimit(2)
        .frame(width: 122, alignment: .leading)

      HStack(spacing: 4) {
        Image(systemName: "star.fill")
          .font(.system(size: 10, weight: .heavy))
          .foregroundColor(HarvestPalette.warning)
        Text(item.ratingText)
          .font(.system(size: 11, weight: .heavy))
          .foregroundColor(HarvestPalette.secondaryText)
        Spacer()
      }
      .padding(.horizontal, 7)
      .frame(height: 22)
      .background(HarvestPalette.warning.opacity(0.10))
      .clipShape(Capsule())
      .frame(width: 122)
    }
    .padding(7)
    .background(HarvestGlassBackground(radius: 8))
    .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.24))
    .shadow(color: HarvestPalette.shadow, radius: 12, x: 0, y: 6)
  }
}

// MARK: - Downloads

struct HarvestDownloadsPage: View {
  @EnvironmentObject private var store: HarvestNativeAppStore

  var body: some View {
    ScrollView {
      VStack(spacing: 10) {
        if store.downloaders.isEmpty {
          HarvestEmptyState(
            systemImage: "tray.and.arrow.down",
            title: "暂无下载器",
            subtitle: "配置 qBittorrent 或 Transmission 后可在这里查看状态。"
          )
          .padding(.top, 84)
        } else {
          ForEach(store.downloaders) { downloader in
            HarvestDownloaderCard(downloader: downloader)
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .padding(.bottom, 104)
    }
    .onAppear {
      if store.downloaders.isEmpty {
        store.refresh(tab: .downloads, showSpinner: false)
      }
    }
  }
}

struct HarvestDownloaderCard: View {
  let downloader: HarvestDownloader

  var body: some View {
    HarvestCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          HarvestAssetBadge(
            imageName: downloader.isTransmission ? "HarvestTR" : "HarvestQB",
            color: downloader.isTransmission ? HarvestPalette.indigo : HarvestPalette.primary,
            size: 46
          )

          VStack(alignment: .leading, spacing: 3) {
            Text(downloader.name)
              .font(.system(size: 17, weight: .black))
              .foregroundColor(HarvestPalette.text)
              .lineLimit(1)
            Text(downloader.endpoint)
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(HarvestPalette.secondaryText)
              .lineLimit(1)
          }

          Spacer()
          HarvestPill(text: downloader.isActive ? "在线" : "停用", color: downloader.isActive ? HarvestPalette.success : HarvestPalette.danger)
        }

        HStack(spacing: 8) {
          HarvestMiniMetric(title: "下载", value: downloader.downloadSpeedText, systemImage: "arrow.down.right.circle.fill")
          HarvestMiniMetric(title: "上传", value: downloader.uploadSpeedText, systemImage: "arrow.up.right.circle.fill")
          HarvestMiniMetric(title: "剩余", value: downloader.freeSpaceText, systemImage: "internaldrive.fill")
        }
      }
    }
  }
}

// MARK: - Tasks

struct HarvestTasksPage: View {
  @EnvironmentObject private var store: HarvestNativeAppStore

  var body: some View {
    ScrollView {
      VStack(spacing: 10) {
        if store.schedules.isEmpty {
          HarvestEmptyState(
            systemImage: "calendar",
            title: "暂无任务",
            subtitle: "计划任务会显示执行规则、启用状态和快捷操作。"
          )
          .padding(.top, 84)
        } else {
          ForEach(store.schedules) { schedule in
            HarvestScheduleCard(schedule: schedule)
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .padding(.bottom, 104)
    }
    .onAppear {
      if store.schedules.isEmpty {
        store.refresh(tab: .tasks, showSpinner: false)
      }
    }
  }
}

struct HarvestScheduleCard: View {
  @EnvironmentObject private var store: HarvestNativeAppStore
  let schedule: HarvestSchedule

  var body: some View {
    HarvestCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 10) {
          HarvestSymbolBadge(
            systemImage: schedule.enabled ? "checkmark.circle.fill" : "xmark.circle.fill",
            color: schedule.enabled ? HarvestPalette.success : HarvestPalette.secondaryText,
            size: 38,
            iconSize: 18
          )

          VStack(alignment: .leading, spacing: 4) {
            Text(schedule.name.isEmpty ? schedule.task : schedule.name)
              .font(.system(size: 16, weight: .black))
              .foregroundColor(HarvestPalette.text)
              .lineLimit(1)
            Text(schedule.description.isEmpty ? schedule.task : schedule.description)
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(HarvestPalette.secondaryText)
              .lineLimit(2)
          }

          Spacer()
          HarvestPill(text: schedule.enabled ? "启用" : "停用", color: schedule.enabled ? HarvestPalette.success : HarvestPalette.secondaryText)
        }

        HStack {
          Image(systemName: "clock.fill")
            .font(.system(size: 13, weight: .bold))
          Text(schedule.crontabText)
            .font(.system(size: 12, weight: .bold))
            .lineLimit(1)
          Spacer()
        }
        .foregroundColor(HarvestPalette.secondaryText)
        .padding(10)
        .background(HarvestPalette.field)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.18))

        HStack(spacing: 8) {
          HarvestSmallAction(title: schedule.enabled ? "停用" : "启用", systemImage: "power.circle.fill") {
            store.toggleSchedule(schedule)
          }
          HarvestSmallAction(title: "执行", systemImage: "play.circle.fill") {
            store.runSchedule(schedule)
          }
        }
      }
    }
  }
}

// MARK: - Search

struct HarvestSearchPage: View {
  @EnvironmentObject private var store: HarvestNativeAppStore
  @State private var query = ""
  @State private var source: HarvestSearchSource = .all

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        HarvestHeaderIcon(systemImage: "xmark.circle.fill") {
          store.closeSearch()
        }
        HarvestTextField(title: "搜索影视信息与站点资源", text: $query, systemImage: "magnifyingglass.circle.fill", compact: true)
        HarvestHeaderIcon(systemImage: "arrow.right.circle.fill") {
          store.search(query, source: source)
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 10)
      .padding(.bottom, 8)
      .background(HarvestGlassBackground(radius: 0))

      HStack {
        HarvestSegmentedPicker(items: HarvestSearchSource.allCases, selection: $source)
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 8)
      .background(HarvestGlassBackground(radius: 0))

      ScrollView {
        if store.isSearching {
          HarvestProgressState(text: "搜索中...")
            .padding(.top, 96)
        } else if store.searchResults.isEmpty {
          HarvestEmptyState(
            systemImage: "magnifyingglass.circle.fill",
            title: "搜索",
            subtitle: "输入关键词后可同时检索 TMDB 与豆瓣。"
          )
          .padding(.top, 84)
        } else {
          LazyVStack(spacing: 10) {
            ForEach(store.searchResults) { result in
              HarvestSearchResultRow(result: result)
            }
          }
          .padding(.horizontal, 12)
          .padding(.top, 8)
          .padding(.bottom, 24)
        }
      }
    }
    .background(HarvestAppBackground())
  }
}

struct HarvestSearchResultRow: View {
  let result: HarvestSearchResult

  var body: some View {
    HarvestCard {
      HStack(spacing: 12) {
        RemoteImageView(urlString: result.posterURL)
          .frame(width: 56, height: 78)
          .background(HarvestPalette.surface)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.20))

        VStack(alignment: .leading, spacing: 5) {
          HStack {
            Text(result.title)
              .font(.system(size: 15, weight: .black))
              .foregroundColor(HarvestPalette.text)
              .lineLimit(1)
            Spacer()
            HarvestPill(text: result.source.label, color: result.source.color)
          }
          Text(result.subtitle)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(HarvestPalette.secondaryText)
            .lineLimit(2)
          Text(result.ratingText)
            .font(.system(size: 12, weight: .heavy))
            .foregroundColor(HarvestPalette.warning)
        }
      }
    }
  }
}

// MARK: - Drawer and Menus

struct HarvestDrawerOverlay: View {
  @EnvironmentObject private var store: HarvestNativeAppStore

  var body: some View {
    ZStack(alignment: .leading) {
      Color.black.opacity(0.22)
        .edgesIgnoringSafeArea(.all)
        .onTapGesture {
          withAnimation(.easeOut(duration: 0.2)) {
            store.showDrawer = false
          }
        }

      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 12) {
            Text(store.currentUserInitial)
              .font(.system(size: 22, weight: .black))
              .frame(width: 52, height: 52)
              .background(HarvestPalette.primaryGradient)
              .foregroundColor(.white)
              .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
              Text(store.session?.user.username ?? "Harvest")
                .font(.system(size: 18, weight: .black))
                .foregroundColor(HarvestPalette.text)
              Text(store.session?.baseURL ?? "")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(HarvestPalette.secondaryText)
                .lineLimit(1)
            }
          }
        }
        .padding(18)

        Divider()

        VStack(spacing: 4) {
          ForEach(HarvestTab.primaryTabs) { tab in
            HarvestDrawerRow(title: tab.title, subtitle: tab.subtitle, systemImage: tab.systemImage, selected: store.selectedTab == tab) {
              store.selectTab(tab)
              withAnimation(.easeOut(duration: 0.2)) {
                store.showDrawer = false
              }
            }
          }
        }
        .padding(.vertical, 8)

        Divider()

        VStack(spacing: 4) {
          HarvestDrawerRow(title: "主题设置", subtitle: "浅色原生主题", systemImage: "paintpalette.fill", selected: false) {
            store.showInfo("主题设置已保留入口")
          }
          HarvestDrawerRow(title: "设置中心", subtitle: "系统配置与偏好", systemImage: "gearshape.fill", selected: false) {
            store.showInfo("设置中心已保留入口")
          }
          HarvestDrawerRow(title: "日志中心", subtitle: "查看运行日志", systemImage: "terminal.fill", selected: false) {
            store.showInfo("日志中心已保留入口")
          }
          HarvestDrawerRow(title: "退出登录", subtitle: "清除当前登录态", systemImage: "rectangle.portrait.and.arrow.right", selected: false, destructive: true) {
            store.logout()
          }
        }
        .padding(.vertical, 8)

        Spacer()
      }
      .frame(width: 312)
      .background(HarvestGlassBackground(radius: 0))
      .edgesIgnoringSafeArea(.vertical)
      .transition(.move(edge: .leading).combined(with: .opacity))
    }
  }
}

struct HarvestDrawerRow: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let selected: Bool
  var destructive = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        HarvestSymbolBadge(
          systemImage: systemImage,
          color: destructive ? HarvestPalette.danger : (selected ? HarvestPalette.primary : HarvestPalette.secondaryText),
          size: 34,
          iconSize: 15
        )
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 14, weight: .heavy))
            .foregroundColor(destructive ? HarvestPalette.danger : HarvestPalette.text)
          Text(subtitle)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(HarvestPalette.secondaryText)
            .lineLimit(1)
        }
        Spacer()
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 10)
      .background(selected ? HarvestPalette.primary.opacity(0.10) : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .padding(.horizontal, 8)
    }
    .buttonStyle(PlainButtonStyle())
  }
}

struct HarvestAccountMenuOverlay: View {
  @EnvironmentObject private var store: HarvestNativeAppStore
  let topInset: CGFloat

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Color.black.opacity(0.001)
        .edgesIgnoringSafeArea(.all)
        .onTapGesture {
          withAnimation(.easeOut(duration: 0.18)) {
            store.showAccountMenu = false
          }
        }

      VStack(alignment: .leading, spacing: 4) {
        HarvestMenuLabel("账号")
        HarvestMenuRow(title: "用户中心", systemImage: "person.crop.circle") {
          store.showInfo("用户中心已保留入口")
        }
        HarvestMenuRow(title: "邀请用户", systemImage: "person.crop.circle.badge.plus") {
          store.showInfo("邀请用户已保留入口")
        }
        HarvestMenuRow(title: "退出登录", systemImage: "rectangle.portrait.and.arrow.right", color: HarvestPalette.danger) {
          store.logout()
        }
        Divider().padding(.vertical, 4)
        HarvestMenuLabel("设置")
        HarvestMenuRow(title: "主题设置", systemImage: "paintpalette.fill") {
          store.showInfo("主题设置已保留入口")
        }
        HarvestMenuRow(title: "截图分享", systemImage: "camera.fill") {
          store.showInfo("截图分享已保留入口")
        }
        HarvestMenuRow(title: "程序更新", systemImage: "arrow.down.circle.fill") {
          store.showInfo("程序更新已保留入口")
        }
        HarvestMenuRow(title: "设置中心", systemImage: "gearshape.fill") {
          store.showInfo("设置中心已保留入口")
        }
      }
      .padding(8)
      .frame(width: 188)
      .background(HarvestGlassBackground(radius: 8))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.30))
      .shadow(color: Color.black.opacity(0.14), radius: 24, x: 0, y: 12)
      .padding(.top, topInset + 48)
      .padding(.trailing, 10)
      .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
    }
  }
}

struct HarvestMenuLabel: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(.system(size: 11, weight: .heavy))
      .foregroundColor(HarvestPalette.secondaryText)
      .padding(.horizontal, 8)
      .padding(.top, 5)
  }
}

struct HarvestMenuRow: View {
  let title: String
  let systemImage: String
  var color: Color = HarvestPalette.text
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: systemImage)
          .font(.system(size: 15, weight: .heavy))
          .frame(width: 20)
        Text(title)
          .font(.system(size: 13, weight: .bold))
        Spacer()
      }
      .foregroundColor(color)
      .padding(.horizontal, 8)
      .frame(height: 34)
      .contentShape(Rectangle())
    }
    .buttonStyle(PlainButtonStyle())
  }
}

// MARK: - Reusable UI

struct HarvestAppBackground: View {
  var body: some View {
    ZStack {
      HarvestPalette.background
      LinearGradient(
        gradient: Gradient(colors: [
          HarvestPalette.primary.opacity(0.10),
          HarvestPalette.mint.opacity(0.06),
          HarvestPalette.warning.opacity(0.05),
          HarvestPalette.background
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      Image("HarvestBackground")
        .resizable()
        .scaledToFill()
        .saturation(0.55)
        .opacity(0.035)
        .blur(radius: 2)
    }
    .edgesIgnoringSafeArea(.all)
  }
}

struct HarvestLogoMark: View {
  var size: CGFloat = 48

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(HarvestPalette.primaryGradient)
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.white.opacity(0.18))
        .padding(size * 0.08)
      Image("HarvestLogo")
        .resizable()
        .scaledToFit()
        .padding(size * 0.18)
    }
    .frame(width: size, height: size)
    .overlay(
      LinearGradient(
        gradient: Gradient(colors: [Color.white.opacity(0.34), Color.white.opacity(0.02)]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    )
    .overlay(HarvestRoundedBorder(radius: 8, color: Color.white, opacity: 0.26))
    .shadow(color: HarvestPalette.primary.opacity(0.24), radius: size * 0.22, x: 0, y: size * 0.11)
  }
}

struct HarvestSymbolBadge: View {
  let systemImage: String
  var color: Color = HarvestPalette.primary
  var size: CGFloat = 36
  var iconSize: CGFloat = 16

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(
          LinearGradient(
            gradient: Gradient(colors: [
              color.opacity(0.18),
              color.opacity(0.08),
              HarvestPalette.card.opacity(0.34)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      Image(systemName: systemImage)
        .font(.system(size: iconSize, weight: .heavy))
        .foregroundColor(color)
    }
    .frame(width: size, height: size)
    .overlay(
      LinearGradient(
        gradient: Gradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0.02)]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    )
    .overlay(HarvestRoundedBorder(radius: 8, color: color, opacity: 0.16))
  }
}

struct HarvestAssetBadge: View {
  let imageName: String
  var color: Color = HarvestPalette.primary
  var size: CGFloat = 44

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(
          LinearGradient(
            gradient: Gradient(colors: [
              color.opacity(0.14),
              HarvestPalette.card.opacity(0.74)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      Image(imageName)
        .resizable()
        .scaledToFit()
        .padding(size * 0.18)
    }
    .frame(width: size, height: size)
    .overlay(
      LinearGradient(
        gradient: Gradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.03)]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    )
    .overlay(HarvestRoundedBorder(radius: 8, color: color, opacity: 0.16))
  }
}

struct HarvestTextField: View {
  let title: String
  @Binding var text: String
  let systemImage: String
  var compact = false

  var body: some View {
    HStack(spacing: 9) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .bold))
        .foregroundColor(HarvestPalette.primary)
        .frame(width: 18)
      TextField(title, text: $text)
        .font(.system(size: 14, weight: .semibold))
        .autocapitalization(.none)
        .disableAutocorrection(true)
      if !text.isEmpty {
        Button(action: { text = "" }) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(HarvestPalette.secondaryText)
        }
        .buttonStyle(PlainButtonStyle())
      }
    }
    .frame(height: compact ? 34 : 42)
    .padding(.horizontal, 12)
    .background(HarvestPalette.field)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.32))
  }
}

struct HarvestPasswordField: View {
  let title: String
  @Binding var text: String
  @Binding var showPassword: Bool

  var body: some View {
    HStack(spacing: 9) {
      Image(systemName: "lock")
        .font(.system(size: 14, weight: .bold))
        .foregroundColor(HarvestPalette.primary)
        .frame(width: 18)
      Group {
        if showPassword {
          TextField(title, text: $text)
        } else {
          SecureField(title, text: $text)
        }
      }
      .font(.system(size: 14, weight: .semibold))
      .autocapitalization(.none)
      .disableAutocorrection(true)

      Button(action: { showPassword.toggle() }) {
        Image(systemName: showPassword ? "eye.slash" : "eye")
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(HarvestPalette.secondaryText)
      }
      .buttonStyle(PlainButtonStyle())
    }
    .frame(height: 42)
    .padding(.horizontal, 12)
    .background(HarvestPalette.field)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.32))
  }
}

struct HarvestHeaderIcon: View {
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .heavy))
        .foregroundColor(HarvestPalette.primary)
        .frame(width: 34, height: 34)
        .background(HarvestGlassBackground(radius: 8))
        .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.22))
        .contentShape(Rectangle())
    }
    .buttonStyle(PlainButtonStyle())
  }
}

struct HarvestIconButton: View {
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .heavy))
        .foregroundColor(HarvestPalette.primary)
        .frame(width: 44, height: 44)
        .background(HarvestGlassBackground(radius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.28))
    }
    .buttonStyle(PlainButtonStyle())
  }
}

struct HarvestFloatingButton: View {
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .heavy))
        .foregroundColor(HarvestPalette.primary)
        .frame(width: 42, height: 42)
        .background(HarvestGlassBackground(radius: 8))
        .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.26))
        .shadow(color: HarvestPalette.shadow, radius: 12, x: 0, y: 6)
    }
    .buttonStyle(PlainButtonStyle())
  }
}

struct HarvestCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        LinearGradient(
          gradient: Gradient(colors: [
            HarvestPalette.card,
            HarvestPalette.card.opacity(0.86),
            HarvestPalette.surface.opacity(0.58)
          ]),
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(
        LinearGradient(
          gradient: Gradient(colors: [
            Color.white.opacity(0.26),
            Color.white.opacity(0.02),
            Color.clear
          ]),
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      )
      .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.34))
      .shadow(color: HarvestPalette.shadow, radius: 16, x: 0, y: 8)
  }
}

struct HarvestStatCard: View {
  let title: String
  let value: String
  let systemImage: String
  let color: Color

  var body: some View {
    HarvestCard {
      HStack(spacing: 10) {
        HarvestSymbolBadge(systemImage: systemImage, color: color, size: 36, iconSize: 16)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(HarvestPalette.secondaryText)
          Text(value)
            .font(.system(size: 15, weight: .black))
            .foregroundColor(HarvestPalette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
      }
    }
  }
}

struct HarvestActionTile: View {
  let title: String
  let systemImage: String
  let color: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        HarvestSymbolBadge(systemImage: systemImage, color: color, size: 36, iconSize: 17)
        Text(title)
          .font(.system(size: 12, weight: .heavy))
          .foregroundColor(HarvestPalette.text)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .background(
        LinearGradient(
          gradient: Gradient(colors: [
            HarvestPalette.card,
            color.opacity(0.09)
          ]),
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(HarvestRoundedBorder(radius: 8, color: color, opacity: 0.16))
      .shadow(color: HarvestPalette.shadow, radius: 12, x: 0, y: 6)
    }
    .buttonStyle(PlainButtonStyle())
  }
}

struct HarvestMiniMetric: View {
  let title: String
  let value: String
  let systemImage: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Image(systemName: systemImage)
          .font(.system(size: 10, weight: .heavy))
          .foregroundColor(HarvestPalette.primary)
          .frame(width: 18, height: 18)
          .background(HarvestPalette.primary.opacity(0.08))
          .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        Text(title)
          .font(.system(size: 10, weight: .bold))
          .foregroundColor(HarvestPalette.secondaryText)
      }
      Text(value)
        .font(.system(size: 12, weight: .black))
        .foregroundColor(HarvestPalette.text)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(9)
    .background(HarvestPalette.field)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.18))
  }
}

struct HarvestSmallAction: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: systemImage)
          .font(.system(size: 12, weight: .heavy))
        Text(title)
          .font(.system(size: 12, weight: .heavy))
      }
      .frame(maxWidth: .infinity)
      .frame(height: 34)
      .background(
        LinearGradient(
          gradient: Gradient(colors: [
            HarvestPalette.primary.opacity(0.14),
            HarvestPalette.cyan.opacity(0.08)
          ]),
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .foregroundColor(HarvestPalette.primary)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(HarvestRoundedBorder(radius: 8, color: HarvestPalette.primary, opacity: 0.16))
    }
    .buttonStyle(PlainButtonStyle())
  }
}

struct HarvestPill: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.system(size: 10, weight: .black))
      .padding(.horizontal, 7)
      .frame(height: 20)
      .background(color.opacity(0.10))
      .foregroundColor(color)
      .clipShape(Capsule())
      .overlay(
        Capsule()
          .stroke(color.opacity(0.18), lineWidth: 1)
      )
  }
}

struct HarvestEmptyState: View {
  let systemImage: String
  let title: String
  let subtitle: String

  var body: some View {
    VStack(spacing: 12) {
      HarvestSymbolBadge(systemImage: systemImage, color: HarvestPalette.primary, size: 54, iconSize: 24)
      Text(title)
        .font(.system(size: 18, weight: .black))
        .foregroundColor(HarvestPalette.text)
      Text(subtitle)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(HarvestPalette.secondaryText)
        .multilineTextAlignment(.center)
        .lineSpacing(3)
    }
    .padding(20)
    .frame(maxWidth: 420)
    .frame(maxWidth: .infinity)
  }
}

struct HarvestProgressState: View {
  let text: String

  var body: some View {
    VStack(spacing: 12) {
      ProgressView()
        .progressViewStyle(CircularProgressViewStyle())
        .accentColor(HarvestPalette.primary)
      Text(text)
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(HarvestPalette.secondaryText)
    }
    .frame(maxWidth: .infinity)
  }
}

struct HarvestLoadingOverlay: View {
  var body: some View {
    ZStack {
      Color.black.opacity(0.08).edgesIgnoringSafeArea(.all)
      ProgressView()
        .progressViewStyle(CircularProgressViewStyle())
        .accentColor(HarvestPalette.primary)
        .padding(18)
        .background(HarvestGlassBackground(radius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 24, x: 0, y: 12)
    }
  }
}

struct HarvestSegmentedPicker<T: HarvestSegmentItem>: View {
  let items: [T]
  @Binding var selection: T

  var body: some View {
    HStack(spacing: 4) {
      ForEach(items) { item in
        Button(action: { selection = item }) {
          Text(item.label)
            .font(.system(size: 13, weight: .heavy))
            .foregroundColor(selection.id == item.id ? HarvestPalette.text : HarvestPalette.secondaryText)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
              Group {
                if selection.id == item.id {
                  RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(HarvestPalette.card)
                    .shadow(color: HarvestPalette.shadow, radius: 8, x: 0, y: 3)
                }
              }
            )
        }
        .buttonStyle(PlainButtonStyle())
      }
    }
    .padding(3)
    .background(HarvestPalette.field)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(HarvestRoundedBorder(radius: 8, opacity: 0.22))
  }
}

struct HarvestGlassBackground: View {
  let radius: CGFloat

  var body: some View {
    VisualEffectBlur(effect: UIBlurEffect(style: .systemChromeMaterial))
      .background(HarvestPalette.card.opacity(0.74))
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
  }
}

struct HarvestRoundedBorder: View {
  var radius: CGFloat
  var color: Color = HarvestPalette.border
  var opacity: Double = 0.55

  var body: some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      .stroke(color.opacity(opacity), lineWidth: 1)
  }
}

struct VisualEffectBlur: UIViewRepresentable {
  let effect: UIVisualEffect?

  func makeUIView(context: Context) -> UIVisualEffectView {
    UIVisualEffectView(effect: effect)
  }

  func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
    uiView.effect = effect
  }
}

final class HarvestImageLoader: ObservableObject {
  @Published var image: UIImage?
  private static let cache = NSCache<NSString, UIImage>()
  private var currentURL: String?

  func load(_ urlString: String) {
    guard !urlString.isEmpty, currentURL != urlString else { return }
    currentURL = urlString
    if let cached = Self.cache.object(forKey: urlString as NSString) {
      image = cached
      return
    }
    guard let url = URL(string: urlString) else { return }
    URLSession.shared.dataTask(with: url) { data, _, _ in
      guard let data = data, let uiImage = UIImage(data: data) else { return }
      Self.cache.setObject(uiImage, forKey: urlString as NSString)
      DispatchQueue.main.async {
        self.image = uiImage
      }
    }.resume()
  }
}

struct RemoteImageView: View {
  @StateObject private var loader = HarvestImageLoader()
  let urlString: String

  var body: some View {
    ZStack {
      if let image = loader.image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        HarvestSymbolBadge(systemImage: "photo.fill", color: HarvestPalette.secondaryText.opacity(0.72), size: 44, iconSize: 20)
      }
    }
    .clipped()
    .onAppear {
      loader.load(urlString)
    }
  }
}

// MARK: - Models

struct HarvestSession: Codable {
  var baseURL: String
  var accessToken: String
  var refreshToken: String?
  var user: HarvestUser
}

struct HarvestUser: Codable {
  var id: Int
  var username: String
  var isActive: Bool = false
  var isStaff: Bool = false
  var isSuperuser: Bool = false
  var email: String = ""

  init(id: Int, username: String) {
    self.id = id
    self.username = username
  }

  init(json: [String: Any], fallbackName: String) {
    id = json.int("id")
    username = json.string("username").nilIfEmpty ?? fallbackName
    isActive = json.bool("is_active", "isActive")
    isStaff = json.bool("is_staff", "isStaff")
    isSuperuser = json.bool("is_superuser", "isSuperuser")
    email = json.string("email")
  }
}

struct HarvestLoginRecord: Codable, Identifiable {
  var id: String { "\(server)|\(username)" }
  let server: String
  let username: String
  let password: String
  let timestamp: TimeInterval

  init(server: String, username: String, password: String, timestamp: TimeInterval = Date().timeIntervalSince1970) {
    self.server = server
    self.username = username
    self.password = password
    self.timestamp = timestamp
  }
}

struct HarvestToast: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

enum HarvestTab: String, CaseIterable, Identifiable {
  case news
  case sites
  case dashboard
  case downloads
  case tasks
  case search

  var id: String { rawValue }

  static let primaryTabs: [HarvestTab] = [.news, .sites, .dashboard, .downloads, .tasks]

  var isPrimary: Bool {
    Self.primaryTabs.contains(self)
  }

  var title: String {
    switch self {
    case .news: return "资讯"
    case .sites: return "站点"
    case .dashboard: return "仪表盘"
    case .downloads: return "下载器"
    case .tasks: return "任务中心"
    case .search: return "搜索"
    }
  }

  var shortTitle: String {
    switch self {
    case .dashboard: return "仪表"
    case .downloads: return "下载"
    case .tasks: return "任务"
    default: return title
    }
  }

  var subtitle: String {
    switch self {
    case .news: return "跟踪最新动态与公告"
    case .sites: return "维护站点配置与状态"
    case .dashboard: return "查看关键运行指标"
    case .downloads: return "管理下载器与传输任务"
    case .tasks: return "处理自动化与后台任务"
    case .search: return "检索影视信息与站点资源"
    }
  }

  var systemImage: String {
    switch self {
    case .news: return "sparkles"
    case .sites: return "network"
    case .dashboard: return "chart.bar"
    case .downloads: return "tray.and.arrow.down"
    case .tasks: return "calendar"
    case .search: return "magnifyingglass"
    }
  }

  var selectedSystemImage: String {
    switch self {
    case .news: return "sparkles"
    case .sites: return "network"
    case .dashboard: return "chart.bar.fill"
    case .downloads: return "tray.and.arrow.down.fill"
    case .tasks: return "calendar"
    default: return systemImage
    }
  }
}

protocol HarvestSegmentItem: Identifiable, Equatable {
  var label: String { get }
}

enum HarvestMediaSource: String, CaseIterable, HarvestSegmentItem {
  case tmdb
  case douban

  var id: String { rawValue }
  var label: String { self == .tmdb ? "TMDB" : "豆瓣" }

  var systemImage: String {
    self == .tmdb ? "film.fill" : "sparkles"
  }

  var color: Color {
    self == .tmdb ? HarvestPalette.success : HarvestPalette.danger
  }
}

enum HarvestSearchSource: String, CaseIterable, HarvestSegmentItem {
  case all
  case tmdb
  case douban

  var id: String { rawValue }

  var label: String {
    switch self {
    case .all: return "全部"
    case .tmdb: return "TMDB"
    case .douban: return "豆瓣"
    }
  }

  var color: Color {
    switch self {
    case .all: return HarvestPalette.primary
    case .tmdb: return HarvestPalette.success
    case .douban: return HarvestPalette.danger
    }
  }
}

enum HarvestSiteAction {
  case refresh
  case signIn
  case repeatTorrent
}

struct HarvestDashboardSnapshot {
  let totalUploaded: Double
  let totalDownloaded: Double
  let totalSeedVolume: Double
  let totalSeeding: Double
  let totalLeeching: Double
  let todayUpload: Double
  let todayDownload: Double
  let totalPublished: Double
  let siteCount: Double
  let updatedAt: String
  let earliestSite: String
  let seedItems: [HarvestMetricItem]
  let incrementItems: [HarvestMetricItem]

  init(json: [String: Any]) {
    totalUploaded = json.double("totalUploaded", "total_uploaded")
    totalDownloaded = json.double("totalDownloaded", "total_downloaded")
    totalSeedVolume = json.double("totalSeedVol", "total_seed_vol", "total_seed_volume")
    totalSeeding = json.double("totalSeeding", "total_seeding")
    totalLeeching = json.double("totalLeeching", "total_leeching")
    todayUpload = json.double("todayUploadIncrement", "today_upload_increment")
    todayDownload = json.double("todayDownloadIncrement", "today_download_increment")
    totalPublished = json.double("totalPublished", "total_published")
    siteCount = json.double("siteCount", "site_count")
    updatedAt = json.string("updatedAt", "updated_at")
    earliestSite = json.dictionary("earliestSite", "earliest_site")?.string("site", "name") ?? ""
    seedItems = HarvestMetricItem.list(from: json.anyList("seedDataList", "seed_data_list"), bytes: true)
    let uploads = HarvestMetricItem.list(from: json.anyList("uploadIncrementDataList", "upload_increment_data_list"), bytes: true, color: HarvestPalette.success)
    let downloads = HarvestMetricItem.list(from: json.anyList("downloadIncrementDataList", "download_increment_data_list"), bytes: true, color: HarvestPalette.primary)
    incrementItems = Array((uploads + downloads).prefix(8))
  }

  var totalUploadedText: String { HarvestFormat.bytes(totalUploaded) }
  var totalDownloadedText: String { HarvestFormat.bytes(totalDownloaded) }
  var todayUploadText: String { HarvestFormat.bytes(todayUpload) }
  var todayDownloadText: String { HarvestFormat.bytes(todayDownload) }

  var updatedText: String {
    updatedAt.isEmpty ? "刚刚更新" : HarvestFormat.shortDate(updatedAt)
  }

  var designation: String {
    let count = Int(siteCount)
    if count >= 200 { return "万界之尊" }
    if count >= 150 { return "九天霸主" }
    if count >= 100 { return "天命之子" }
    if count >= 50 { return "纵横天下" }
    if count >= 30 { return "龙腾九霄" }
    if count >= 20 { return "光耀九天" }
    if count >= 10 { return "星辰初现" }
    if count >= 1 { return "初窥门径" }
    return "无称号"
  }
}

struct HarvestMetricItem: Identifiable {
  let id = UUID()
  let name: String
  let value: Double
  let displayValue: String
  let ratio: Double
  let color: Color

  static func list(from value: Any, bytes: Bool, color: Color? = nil) -> [HarvestMetricItem] {
    let rows = HarvestJSON.rows(from: value)
    let values = rows.map { row -> (String, Double) in
      let name = row.string("name", "key", "label", "site").nilIfEmpty ?? "未命名"
      let amount = row.double("value", "count", "total", "size", "uploaded", "downloaded")
      return (name, amount)
    }
    let maxValue = values.map { $0.1 }.max() ?? 1
    let palette = [HarvestPalette.primary, HarvestPalette.success, HarvestPalette.warning, HarvestPalette.danger]
    return values.enumerated().map { index, item in
      HarvestMetricItem(
        name: item.0,
        value: item.1,
        displayValue: bytes ? HarvestFormat.bytes(item.1) : HarvestFormat.compactNumber(item.1),
        ratio: maxValue <= 0 ? 0 : min(1, item.1 / maxValue),
        color: color ?? palette[index % palette.count]
      )
    }
  }
}

struct HarvestSiteInfo: Identifiable {
  let id: Int
  let site: String
  let nickname: String
  let tags: [String]
  let username: String
  let email: String
  let available: Bool
  let signInText: String?
  let uploaded: Double
  let downloaded: Double
  let ratio: Double
  let seed: Int
  let leech: Int
  let invitation: Int
  let level: String
  let updatedAt: String

  init(json: [String: Any]) {
    id = json.int("id")
    site = json.string("site")
    nickname = json.string("nickname")
    tags = json.stringArray("tags")
    username = json.string("username")
    email = json.string("email")
    available = json.bool("available")
    let latestStatus = HarvestSiteInfo.latestStatus(from: json.dictionary("status"))
    uploaded = latestStatus?.double("uploaded") ?? 0
    downloaded = latestStatus?.double("downloaded") ?? 0
    ratio = latestStatus?.double("ratio") ?? 0
    seed = latestStatus?.int("seed") ?? 0
    leech = latestStatus?.int("leech") ?? 0
    invitation = latestStatus?.int("invitation") ?? 0
    level = latestStatus?.string("my_level", "level") ?? ""
    updatedAt = latestStatus?.string("updated_at", "created_at") ?? json.string("updated_at")
    signInText = HarvestSiteInfo.todaySignInText(from: json.dictionary("sign_info"))
  }

  var displayName: String {
    if !nickname.isEmpty { return nickname }
    if !site.isEmpty { return site }
    return "未命名站点"
  }

  var uploadedText: String { HarvestFormat.bytes(uploaded) }
  var downloadedText: String { HarvestFormat.bytes(downloaded) }
  var ratioText: String { ratio <= 0 ? "-" : String(format: "%.2f", ratio) }

  static func list(from value: Any) -> [HarvestSiteInfo] {
    HarvestJSON.rows(from: value).map(HarvestSiteInfo.init)
  }

  private static func latestStatus(from status: [String: Any]?) -> [String: Any]? {
    guard let status = status, !status.isEmpty else { return nil }
    let latestKey = status.keys.sorted().last
    guard let key = latestKey else { return nil }
    return status[key] as? [String: Any]
  }

  private static func todaySignInText(from signInfo: [String: Any]?) -> String? {
    guard let signInfo = signInfo else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return signInfo.keys.contains(formatter.string(from: Date())) ? "已签到" : nil
  }
}

struct HarvestDownloader: Identifiable {
  let id: Int
  let name: String
  let category: String
  let proto: String
  let host: String
  let port: Int
  let isActive: Bool
  let status: [String: Any]

  init(json: [String: Any]) {
    id = json.int("id")
    name = json.string("name").nilIfEmpty ?? "未命名下载器"
    category = json.string("category")
    proto = json.string("protocol").nilIfEmpty ?? "http"
    host = json.string("external_host", "host")
    port = json.int("port")
    isActive = json.bool(defaultValue: true, "is_active", "isActive")
    status = json.dictionary("status") ?? [:]
  }

  var isTransmission: Bool { category.localizedCaseInsensitiveContains("Tr") }
  var endpoint: String { port > 0 ? "\(proto)://\(host):\(port)" : "\(proto)://\(host)" }
  var downloadSpeedText: String { HarvestFormat.speed(status.double("dl_info_speed", "download_speed", "downloadSpeed")) }
  var uploadSpeedText: String { HarvestFormat.speed(status.double("up_info_speed", "upload_speed", "uploadSpeed")) }
  var freeSpaceText: String { HarvestFormat.bytes(status.double("free_space_on_disk", "freeSpaceOnDisk", "free_space")) }

  static func list(from value: Any) -> [HarvestDownloader] {
    HarvestJSON.rows(from: value).map(HarvestDownloader.init)
  }
}

struct HarvestSchedule: Identifiable {
  let id: Int
  let name: String
  let task: String
  let description: String
  let enabled: Bool
  let crontabText: String

  init(json: [String: Any]) {
    id = json.int("id")
    name = json.string("name")
    task = json.string("task")
    description = json.string("description")
    enabled = json.bool(defaultValue: true, "enabled")
    if let crontab = json.dictionary("crontab") {
      crontabText = HarvestSchedule.readableCrontab(crontab)
    } else {
      crontabText = "每分钟执行"
    }
  }

  func toggled() -> HarvestSchedule {
    HarvestSchedule(
      id: id,
      name: name,
      task: task,
      description: description,
      enabled: !enabled,
      crontabText: crontabText
    )
  }

  private init(id: Int, name: String, task: String, description: String, enabled: Bool, crontabText: String) {
    self.id = id
    self.name = name
    self.task = task
    self.description = description
    self.enabled = enabled
    self.crontabText = crontabText
  }

  static func list(from value: Any) -> [HarvestSchedule] {
    HarvestJSON.rows(from: value).map(HarvestSchedule.init)
  }

  private static func readableCrontab(_ json: [String: Any]) -> String {
    var parts: [String] = []
    let minute = json.string("minute")
    let hour = json.string("hour")
    let day = json.string("day_of_month", "dayOfMonth")
    let month = json.string("month_of_year", "monthOfYear")
    let week = json.string("day_of_week", "dayOfWeek")
    if !minute.isEmpty && minute != "*" { parts.append("第 \(minute) 分钟") }
    if !hour.isEmpty && hour != "*" { parts.append("第 \(hour) 小时") }
    if !day.isEmpty && day != "*" { parts.append("每月 \(day) 号") }
    if !month.isEmpty && month != "*" { parts.append("\(month) 月") }
    if !week.isEmpty && week != "*" { parts.append("星期 \(week)") }
    return parts.isEmpty ? "每分钟执行" : parts.joined(separator: "，")
  }
}

struct HarvestMediaSection: Identifiable {
  let id = UUID()
  let title: String
  let source: HarvestMediaSource
  let items: [HarvestMediaItem]
}

struct HarvestMediaItem: Identifiable {
  let id: String
  let title: String
  let overview: String
  let posterURL: String
  let rating: Double
  let mediaType: String
  let year: String

  init(json: [String: Any], source: HarvestMediaSource, mediaType fallbackType: String = "") {
    let rawID = json.string("id", "subject_id", "douban_id")
    id = "\(source.rawValue)-\(rawID.isEmpty ? UUID().uuidString : rawID)"
    title = json.string("title", "name", "original_title", "original_name").nilIfEmpty ?? "未命名"
    overview = json.string("overview", "description", "card_subtitle", "abstract")
    let poster = json.string("poster_path", "poster", "cover", "pic", "url")
    if poster.hasPrefix("http") {
      posterURL = poster
    } else if !poster.isEmpty && source == .tmdb {
      posterURL = "https://image.tmdb.org/t/p/w342\(poster)"
    } else {
      posterURL = ""
    }
    rating = json.double("vote_average", "rating", "rate", "score")
    mediaType = json.string("media_type").nilIfEmpty ?? fallbackType
    let date = json.string("release_date", "first_air_date", "year")
    year = String(date.prefix(4))
  }

  var ratingText: String {
    rating <= 0 ? "暂无评分" : String(format: "%.1f", rating)
  }

  static func tmdbList(from value: Any, mediaType: String) -> [HarvestMediaItem] {
    HarvestJSON.rows(from: value).map { HarvestMediaItem(json: $0, source: .tmdb, mediaType: mediaType) }
  }

  static func doubanList(from value: Any) -> [HarvestMediaItem] {
    HarvestJSON.rows(from: value).map { HarvestMediaItem(json: $0, source: .douban) }
  }
}

struct HarvestSearchResult: Identifiable {
  let id: String
  let title: String
  let subtitle: String
  let posterURL: String
  let rating: Double
  let source: HarvestSearchSource

  var ratingText: String {
    rating <= 0 ? "暂无评分" : String(format: "%.1f 分", rating)
  }

  static func tmdbList(from value: Any) -> [HarvestSearchResult] {
    HarvestJSON.rows(from: value).map { row in
      let item = HarvestMediaItem(json: row, source: .tmdb)
      return HarvestSearchResult(
        id: item.id,
        title: item.title,
        subtitle: item.overview.nilIfEmpty ?? item.year,
        posterURL: item.posterURL,
        rating: item.rating,
        source: .tmdb
      )
    }
  }

  static func doubanList(from value: Any) -> [HarvestSearchResult] {
    HarvestJSON.rows(from: value).map { row in
      let item = HarvestMediaItem(json: row, source: .douban)
      return HarvestSearchResult(
        id: item.id,
        title: item.title,
        subtitle: item.overview.nilIfEmpty ?? item.year,
        posterURL: item.posterURL,
        rating: item.rating,
        source: .douban
      )
    }
  }
}

struct HarvestNotice: Identifiable {
  let id: Int
  let title: String
  let content: String
  let isRead: Bool
  let createdAt: String

  init(json: [String: Any]) {
    id = json.int("id")
    title = json.string("title")
    content = json.string("content", "message", "body")
    isRead = json.bool("is_read", "isRead", "read")
    createdAt = json.string("created_at", "createdAt")
  }

  var cleanContent: String {
    content
      .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "[*_~`#>\\[\\]()]",
                            with: "",
                            options: .regularExpression)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func markedRead() -> HarvestNotice {
    HarvestNotice(id: id, title: title, content: content, isRead: true, createdAt: createdAt)
  }

  private init(id: Int, title: String, content: String, isRead: Bool, createdAt: String) {
    self.id = id
    self.title = title
    self.content = content
    self.isRead = isRead
    self.createdAt = createdAt
  }

  static func list(from value: Any) -> [HarvestNotice] {
    HarvestJSON.rows(from: value).map(HarvestNotice.init)
  }
}

// MARK: - API

enum HarvestAPI {
  static let tokenPair = "/api/token/pair"
  static let tokenRefresh = "/api/token/refresh"
  static let userInfo = "/api/auth/userinfo"
  static let dashboard = "/api/mysite/dashboard"
  static let mySiteList = "/api/mysite/mysite"
  static let mySiteStatusOperate = "/api/mysite/info/"
  static let mySiteSignInOperate = "/api/mysite/sign/"
  static let mySiteRepeatOperate = "/api/mysite/repeat/"
  static let downloaderList = "/api/option/downloaders"
  static let schedule = "/api/option/schedule"
  static let taskExec = "/api/option/exec"
  static let noticeHistory = "/api/option/notice"
  static let tmdbSearch = "/api/tmdb/search"
  static let tmdbPlayingMovies = "/api/tmdb/playing/movies"
  static let tmdbPopularMovies = "/api/tmdb/popular/movies"
  static let tmdbUpcomingMovies = "/api/tmdb/upcoming/movies"
  static let tmdbPopularTV = "/api/tmdb/popular/tvs"
  static let doubanSearch = "/api/option/douban/search"
  static let doubanHot = "/api/option/douban/hot"
  static let doubanTop250 = "/api/option/douban/top250"
}

struct HarvestTokenPair {
  let access: String
  let refresh: String?
}

enum HarvestAPIError: Error {
  case badURL
  case invalidResponse
  case unauthorized
  case message(String)
}

final class HarvestAPIClient {
  let baseURL: String
  let accessToken: String?

  init(baseURL: String, accessToken: String? = nil) {
    self.baseURL = HarvestAPIClient.normalizeBaseURL(baseURL)
    self.accessToken = accessToken
  }

  static func normalizeBaseURL(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return "" }
    if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
      value = "http://\(value)"
    }
    while value.hasSuffix("/") {
      value.removeLast()
    }
    return value
  }

  func request(
    path: String,
    method: String = "GET",
    query: [String: String] = [:],
    body: [String: Any]? = nil,
    authenticated: Bool = true
  ) async throws -> Any {
    guard let url = buildURL(path: path, query: query) else {
      throw HarvestAPIError.badURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body = body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if authenticated, let token = accessToken, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await URLSession.shared.harvestData(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw HarvestAPIError.invalidResponse
    }
    if http.statusCode == 401 {
      throw HarvestAPIError.unauthorized
    }

    let json: Any
    if data.isEmpty {
      json = [:]
    } else {
      json = try JSONSerialization.jsonObject(with: data)
    }

    if http.statusCode >= 400 {
      throw HarvestAPIError.message(Self.message(from: json) ?? "请求失败 (\(http.statusCode))")
    }
    return try unwrap(json)
  }

  func refreshToken(_ refreshToken: String) async throws -> HarvestTokenPair {
    let payload = try await request(
      path: HarvestAPI.tokenRefresh,
      method: "POST",
      body: ["refresh": refreshToken],
      authenticated: false
    )
    guard let dict = payload as? [String: Any],
          let access = dict.string("access").nilIfEmpty else {
      throw HarvestAPIError.unauthorized
    }
    return HarvestTokenPair(access: access, refresh: dict.string("refresh").nilIfEmpty)
  }

  private func buildURL(path: String, query: [String: String]) -> URL? {
    let raw: String
    if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") {
      raw = path
    } else {
      raw = "\(baseURL)\(path.hasPrefix("/") ? path : "/\(path)")"
    }
    guard var components = URLComponents(string: raw) else { return nil }
    var items = components.queryItems ?? []
    items.append(contentsOf: query.map { URLQueryItem(name: $0.key, value: $0.value) })
    components.queryItems = items.isEmpty ? nil : items
    return components.url
  }

  private func unwrap(_ json: Any) throws -> Any {
    guard let map = json as? [String: Any] else { return json }
    if let succeed = map["succeed"] as? Bool, succeed == false {
      throw HarvestAPIError.message(Self.message(from: map) ?? "请求失败")
    }
    if let code = map["code"] as? Int, code != 0, map.keys.contains("succeed") {
      throw HarvestAPIError.message(Self.message(from: map) ?? "请求失败")
    }
    if let data = map["data"] {
      return data
    }
    return map
  }

  static func message(from value: Any) -> String? {
    if let string = value as? String {
      return string.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
    if let map = value as? [String: Any] {
      for key in ["message", "msg", "info", "detail", "result"] {
        if let message = Self.message(from: map[key] as Any) {
          return message
        }
      }
      return Self.message(from: map["data"] as Any)
    }
    if let list = value as? [Any] {
      let messages = list.compactMap { Self.message(from: $0) }
      return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }
    return nil
  }
}

// MARK: - Persistence

enum HarvestDefaults {
  private static let serverKey = "harvest.native.server"
  private static let sessionKey = "harvest.native.session"
  private static let historyKey = "harvest.native.loginHistory"

  static var server: String {
    get { UserDefaults.standard.string(forKey: serverKey) ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: serverKey) }
  }

  static var session: HarvestSession? {
    get {
      guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
      return try? JSONDecoder().decode(HarvestSession.self, from: data)
    }
    set {
      guard let value = newValue else {
        UserDefaults.standard.removeObject(forKey: sessionKey)
        return
      }
      if let data = try? JSONEncoder().encode(value) {
        UserDefaults.standard.set(data, forKey: sessionKey)
      }
    }
  }

  static var loginHistory: [HarvestLoginRecord] {
    get {
      guard let data = UserDefaults.standard.data(forKey: historyKey) else { return [] }
      return (try? JSONDecoder().decode([HarvestLoginRecord].self, from: data)) ?? []
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        UserDefaults.standard.set(data, forKey: historyKey)
      }
    }
  }

  static func addLoginRecord(_ record: HarvestLoginRecord) {
    var records = loginHistory.filter { $0.id != record.id }
    records.insert(record, at: 0)
    loginHistory = Array(records.prefix(8))
  }

  static func clearAll() {
    UserDefaults.standard.removeObject(forKey: serverKey)
    UserDefaults.standard.removeObject(forKey: sessionKey)
    UserDefaults.standard.removeObject(forKey: historyKey)
  }
}

// MARK: - Helpers

enum HarvestPalette {
  static let background = Color(UIColor.systemGroupedBackground)
  static let surface = Color(UIColor.secondarySystemGroupedBackground)
  static let card = Color(UIColor.systemBackground).opacity(0.92)
  static let field = Color(UIColor.secondarySystemFill).opacity(0.52)
  static let text = Color(UIColor.label)
  static let secondaryText = Color(UIColor.secondaryLabel)
  static let border = Color(UIColor.separator)
  static let primary = Color(red: 0.00, green: 0.48, blue: 1.00)
  static let cyan = Color(red: 0.10, green: 0.72, blue: 0.88)
  static let mint = Color(red: 0.18, green: 0.78, blue: 0.55)
  static let indigo = Color(red: 0.36, green: 0.35, blue: 0.86)
  static let success = Color(red: 0.12, green: 0.68, blue: 0.45)
  static let warning = Color(red: 0.96, green: 0.63, blue: 0.18)
  static let danger = Color(red: 1.00, green: 0.27, blue: 0.34)
  static let shadow = Color.black.opacity(0.075)

  static var primaryGradient: LinearGradient {
    LinearGradient(
      gradient: Gradient(colors: [primary, cyan, indigo.opacity(0.92)]),
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
}

@MainActor
enum HarvestSafeArea {
  static var insets: UIEdgeInsets {
    UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets ?? .zero
  }
}

enum HarvestFormat {
  static func bytes(_ value: Double) -> String {
    if value <= 0 { return "0 B" }
    let units = ["B", "KB", "MB", "GB", "TB", "PB"]
    var amount = value
    var index = 0
    while amount >= 1024, index < units.count - 1 {
      amount /= 1024
      index += 1
    }
    if amount >= 100 || index == 0 {
      return "\(Int(amount.rounded())) \(units[index])"
    }
    return String(format: "%.1f %@", amount, units[index])
  }

  static func speed(_ value: Double) -> String {
    "\(bytes(value))/s"
  }

  static func compactNumber(_ value: Double) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    return "\(Int(value.rounded()))"
  }

  static func shortDate(_ raw: String) -> String {
    if raw.count >= 16 {
      let start = raw.index(raw.startIndex, offsetBy: 5)
      let end = raw.index(raw.startIndex, offsetBy: 16)
      return String(raw[start..<end])
    }
    return raw
  }
}

enum HarvestJSON {
  static func rows(from value: Any) -> [[String: Any]] {
    if let rows = value as? [[String: Any]] {
      return rows
    }
    if let list = value as? [Any] {
      return list.compactMap { item in
        if let row = item as? [String: Any] { return row }
        if let row = item as? NSDictionary { return row as? [String: Any] }
        return nil
      }
    }
    if let dict = value as? [String: Any] {
      for key in ["results", "list", "items", "records", "data"] {
        if let nested = dict[key] {
          let rows = self.rows(from: nested)
          if !rows.isEmpty { return rows }
        }
      }
    }
    return []
  }
}

extension URLSession {
  func harvestData(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await withCheckedThrowingContinuation { continuation in
      let task = dataTask(with: request) { data, response, error in
        if let error = error {
          continuation.resume(throwing: error)
          return
        }
        guard let data = data, let response = response else {
          continuation.resume(throwing: HarvestAPIError.invalidResponse)
          return
        }
        continuation.resume(returning: (data, response))
      }
      task.resume()
    }
  }
}

extension Error {
  var harvestMessage: String {
    if let api = self as? HarvestAPIError {
      switch api {
      case .badURL:
        return "服务器地址不正确"
      case .invalidResponse:
        return "服务器响应异常"
      case .unauthorized:
        return "登录已过期，请重新登录"
      case .message(let message):
        return message
      }
    }
    return localizedDescription
  }
}

extension String {
  var nilIfEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

extension Dictionary where Key == String, Value == Any {
  func string(_ keys: String...) -> String {
    for key in keys {
      guard let value = self[key], !(value is NSNull) else { continue }
      if let string = value as? String { return string }
      if let number = value as? NSNumber { return number.stringValue }
      return "\(value)"
    }
    return ""
  }

  func int(_ keys: String...) -> Int {
    for key in keys {
      guard let value = self[key], !(value is NSNull) else { continue }
      if let int = value as? Int { return int }
      if let number = value as? NSNumber { return number.intValue }
      if let string = value as? String, let int = Int(string) { return int }
    }
    return 0
  }

  func double(_ keys: String...) -> Double {
    for key in keys {
      guard let value = self[key], !(value is NSNull) else { continue }
      if let double = value as? Double { return double }
      if let int = value as? Int { return Double(int) }
      if let number = value as? NSNumber { return number.doubleValue }
      if let string = value as? String, let double = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return double
      }
    }
    return 0
  }

  func bool(_ keys: String...) -> Bool {
    boolValue(keys, defaultValue: false)
  }

  func bool(defaultValue: Bool, _ keys: String...) -> Bool {
    boolValue(keys, defaultValue: defaultValue)
  }

  private func boolValue(_ keys: [String], defaultValue: Bool) -> Bool {
    for key in keys {
      guard let value = self[key], !(value is NSNull) else { continue }
      if let bool = value as? Bool { return bool }
      if let number = value as? NSNumber { return number.boolValue }
      if let string = value as? String {
        let lower = string.lowercased()
        if ["true", "1", "yes"].contains(lower) { return true }
        if ["false", "0", "no"].contains(lower) { return false }
      }
    }
    return defaultValue
  }

  func dictionary(_ keys: String...) -> [String: Any]? {
    for key in keys {
      if let dict = self[key] as? [String: Any] { return dict }
      if let dict = self[key] as? NSDictionary { return dict as? [String: Any] }
    }
    return nil
  }

  func anyList(_ keys: String...) -> Any {
    for key in keys {
      if let value = self[key] { return value }
    }
    return []
  }

  func stringArray(_ keys: String...) -> [String] {
    for key in keys {
      if let list = self[key] as? [String] { return list }
      if let list = self[key] as? [Any] {
        return list.map { "\($0)" }
      }
      if let string = self[key] as? String, !string.isEmpty {
        return [string]
      }
    }
    return []
  }
}
