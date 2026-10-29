import SwiftUI

/// 2M — "3 dosya yükleniyor" card on top of the month.
struct UploadProgressCard: View {
    let period: Period
    @Environment(UploadQueue.self) private var queue

    var body: some View {
        let items = queue.items(for: period).filter { $0.state != .done || $0.progress < 1 }
        let active = items.filter(\.isActive)
        if !items.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 7) {
                        if active.isEmpty {
                            Icon(.triangleAlert, size: 15).foregroundStyle(FColor.danger)
                        } else {
                            Spinner()
                        }
                        Text(active.isEmpty ? "\(items.count) dosya yüklenemedi" : "\(active.count) dosya yükleniyor")
                            .fFont(12.5, .heavy)
                    }
                    Spacer()
                    Text(Connectivity.shared.isOnline ? "Uygulamayı kapatabilirsin" : "Bağlantı bekleniyor")
                        .fFont(11.5, .semibold).foregroundStyle(FColor.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                ForEach(items.prefix(4)) { item in
                    RowDivider()
                    UploadRow(item: item)
                }
                if items.count > 4 {
                    RowDivider()
                    Text("+\(items.count - 4) dosya daha").fFont(12, .semibold).foregroundStyle(FColor.muted).padding(9)
                }
            }
            .background(FColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FColor.brand.opacity(0.25)))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

private struct UploadRow: View {
    let item: UploadItem
    @Environment(UploadQueue.self) private var queue

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(item.filename).fFont(13, .semibold).lineLimit(1).truncationMode(.middle)
                Spacer()
                if item.state == .failed {
                    Button { queue.retry(item.id) } label: {
                        HStack(spacing: 5) {
                            Icon(.triangleAlert, size: 14)
                            Text("Hata — Tekrar dene")
                        }
                        .fFont(13, .bold)
                        .foregroundStyle(FColor.danger)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if let error = item.error { Text(error) }
                        Button("Kaldır", role: .destructive) { queue.cancel(item.id) }
                    }
                } else {
                    Text(item.statusLabel)
                        .fFont(13, item.state == .uploading ? .bold : .semibold)
                        .foregroundStyle(item.state == .uploading ? FColor.brand : FColor.muted)
                        .monospacedDigit()
                }
            }
            if item.state != .failed {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(FColor.ink.opacity(0.08))
                        Capsule()
                            .fill(item.state == .uploading || item.state == .finishing ? FColor.brand : FColor.brand.opacity(0.45))
                            .frame(width: geo.size.width * max(item.progress, item.state == .compressing ? 0.18 : 0.02))
                            .animation(.easeOut(duration: 0.25), value: item.progress)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

struct Spinner: View {
    var size: CGFloat = 16
    var color: Color = FColor.brand
    @State private var spinning = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.25), lineWidth: 2)
            .overlay(Circle().trim(from: 0, to: 0.25).stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round)))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

/// Dashed "Yükleniyor %64" card shown in the grid while a file uploads.
struct UploadPlaceholderCards: View {
    let period: Period
    @Environment(UploadQueue.self) private var queue

    var body: some View {
        ForEach(queue.items(for: period).filter { $0.state != .done && $0.state != .failed }) { item in
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 6) {
                    Icon(item.contentType == "application/pdf" ? .fileText : .camera, size: 22)
                    Text(item.state == .waitingNetwork ? "Bağlantı bekleniyor" : item.state == .uploading ? "Yükleniyor %\(Int(item.progress * 100))" : item.statusLabel)
                        .fFont(11, .bold)
                        .monospacedDigit()
                }
                .foregroundStyle(item.state == .waitingNetwork ? FColor.muted : FColor.brand)
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fit)
                .background(FColor.brand.opacity(0.04))
                VStack(alignment: .leading, spacing: 4) {
                    if item.state == .waitingNetwork {
                        Text("Bugün").fFont(11, .semibold).foregroundStyle(FColor.muted)
                        HStack(spacing: 5) {
                            Icon(.clock, size: 13)
                            Text("Bağlantı bekleniyor")
                        }
                        .fFont(12, .bold).foregroundStyle(FColor.muted)
                    } else {
                        Text("Bugün").fFont(11, .semibold).foregroundStyle(FColor.muted)
                        FSkeleton(width: 100, height: 12)
                        FSkeleton(width: 64, height: 12)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .background(FColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FColor.brand.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
    }
}
