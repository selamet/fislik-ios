import SwiftUI

/// 2X / 2AD — notifications grouped by today / earlier, swipe left to mark read.
struct NotificationsScreen: View {
    var onOpen: (AppNotification, NotificationContent) -> Void = { _, _ in }

    @Environment(AppModel.self) private var app
    @State private var store = NotificationsStore.shared
    @State private var receipts = ReceiptStore.shared

    var body: some View {
        let today = store.items.filter { Calendar.fislik.isDateInToday($0.createdAt) }
        let earlier = store.items.filter { !Calendar.fislik.isDateInToday($0.createdAt) }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(store.unreadCount > 0 ? "\(store.unreadCount) OKUNMAMIŞ" : "TÜMÜ OKUNDU")
                        .fFont(11, .heavy, tracking: 0.4).foregroundStyle(FColor.muted)
                    Spacer()
                    if store.unreadCount > 0 {
                        Button("Tümünü okundu işaretle") { Task { await store.markAllRead() } }
                            .fFont(13, .bold).foregroundStyle(FColor.brand)
                    }
                }
                .frame(height: 44)
                Text("Bildirimler").fFont(30, .heavy, tracking: -0.9)
                    .padding(.bottom, 2)

                if store.loaded && store.items.isEmpty {
                    EmptyNotificationsCard()
                        .padding(.top, 8)
                }
                if !today.isEmpty { section("BUGÜN", today) }
                if !earlier.isEmpty { section("DAHA ÖNCE", earlier) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .refreshable { await store.refresh() }
        .background(FColor.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.refresh() }
    }

    private func section(_ title: String, _ items: [AppNotification]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).fFont(11, .heavy, tracking: 0.3).foregroundStyle(FColor.muted).padding(.horizontal, 2)
            FGroupedCard {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, n in
                    if i > 0 { RowDivider() }
                    let content = NotificationContent(n, isAccountant: app.isAccountant, accountantName: receipts.activeAccountant?.displayName)
                    SwipeToRead(enabled: !n.read) {
                        Task { await store.markRead([n.id]) }
                    } content: {
                        NotificationRow(notification: n, content: content)
                    }
                    .onTapGesture {
                        Task { await store.markRead([n.id]) }
                        onOpen(n, content)
                    }
                }
            }
        }
    }
}

private struct NotificationRow: View {
    let notification: AppNotification
    let content: NotificationContent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(content.icon, size: 17)
                .foregroundStyle(content.color)
                .frame(width: 36, height: 36)
                .background(content.tone == .neutral ? FColor.ink.opacity(0.05) : content.color.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(content.text).fFont(13.5, .bold).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(metaText)
                    if let linkTitle = content.linkTitle {
                        Text(linkTitle).fontWeight(.bold).foregroundStyle(FColor.brand)
                    }
                }
                .fFont(11, .semibold)
                .foregroundStyle(FColor.muted)
            }
            Spacer(minLength: 0)
            if !notification.read {
                Circle().fill(FColor.brand).frame(width: 8, height: 8).padding(.top, 6)
            }
        }
        .foregroundStyle(FColor.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(notification.read ? FColor.card : Color(light: 0xF2F7F6, dark: 0x18302C))
        .contentShape(Rectangle())
    }

    private var metaText: String {
        let isToday = Calendar.fislik.isDateInToday(notification.createdAt)
        let when = isToday ? TR.time(notification.createdAt) : TR.longDateTime(notification.createdAt)
        return [when, content.meta].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Reveals a 72pt teal "Okundu" action when swiped left.
struct SwipeToRead<Content: View>: View {
    var enabled: Bool
    let onRead: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            if enabled {
                Button {
                    onRead()
                    withAnimation(.spring(duration: 0.25)) { offset = 0 }
                } label: {
                    VStack(spacing: 3) {
                        Icon(.check, size: 16)
                        Text("Okundu").fFont(10, .heavy)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 72)
                    .frame(maxHeight: .infinity)
                    .background(FColor.brand)
                }
                .buttonStyle(.plain)
            }
            content()
                .offset(x: offset)
                .gesture(enabled ? DragGesture(minimumDistance: 15)
                    .onChanged { v in offset = min(0, max(-110, v.translation.width)) }
                    .onEnded { v in
                        withAnimation(.spring(duration: 0.25)) {
                            if v.translation.width < -140 { onRead(); offset = 0 }
                            else { offset = v.translation.width < -40 ? -72 : 0 }
                        }
                    } : nil)
        }
        .clipped()
    }
}

/// 2AD bottom — "Henüz bildirim yok".
struct EmptyNotificationsCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Icon(.bell, size: 18)
                .foregroundStyle(FColor.muted)
                .frame(width: 40, height: 40)
                .background(FColor.ink.opacity(0.05), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Henüz bildirim yok").fFont(14, .heavy)
                Text("Yeni bir şey olduğunda burada göreceksin.").fFont(12, .medium).foregroundStyle(FColor.muted)
            }
            Spacer()
        }
        .padding(14)
        .fCard(radius: 16)
    }
}
