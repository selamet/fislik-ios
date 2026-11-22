import SwiftUI

/// "Abonelikler": monthly charges found in the last six months that are not
/// set up as recurring expenses. Owners and admins; the API says whether
/// the plan includes the list.
struct SubscriptionsSection: View {
    let version: Int
    let changed: () async -> Void

    @State private var data: DetectedSubscriptions?
    @State private var error: String?
    @State private var tracking: DetectedSubscription?
    @State private var busy = false

    var body: some View {
        ReportSection(title: "Abonelikler", hint: data.flatMap { $0.available && !$0.items.isEmpty ? "Yıllık ~\(TR.moneyWhole($0.yearlyTotal))" : nil } ?? "Her ay tekrarlanan ödemeler") {
            if let error {
                Text(error).fFont(12.5, .semibold).foregroundStyle(FColor.danger)
            }
            if let data {
                if !data.available {
                    Text("Pro ve İşletme planlarında Fişlik, fişlerinden ve ekstrelerinden her ay tekrar eden ödemeleri kendiliğinden bulur, yıllık maliyetini ve fiyat artışlarını gösterir.")
                        .fFont(12.5, .semibold)
                        .foregroundStyle(FColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("subscriptions-plan-note")
                } else if data.items.isEmpty {
                    Text("Şu an tekrarlanan bir ödeme bulunamadı. Fiş ve ekstre yükledikçe burada görünür.")
                        .fFont(12.5, .semibold)
                        .foregroundStyle(FColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if data.available {
                    ForEach(data.items) { item in row(item) }
                    if data.dismissedCount > 0 {
                        Button("Gizlenenleri geri getir (\(data.dismissedCount))") { act { try await API.restoreDismissedSubscriptions() } }
                            .fFont(12.5, .heavy)
                            .foregroundStyle(FColor.brand)
                            .disabled(busy)
                    }
                }
            }
        }
        .task(id: version) { await load() }
        .confirmationDialog("Tekrarlayan gidere çevrilsin mi?", isPresented: Binding(get: { tracking != nil }, set: { if !$0 { tracking = nil } }), titleVisibility: .visible) {
            Button("Tekrarlayana çevir") {
                if let item = tracking { act { try await API.trackSubscription(item.id) } }
            }
        } message: {
            if let item = tracking {
                Text("\(item.name) her ayın \(item.dayOfMonth). günü \(TR.money(item.lastAmount)) olarak giderlere kendiliğinden eklenecek. Bu ödemenin fişini ayrıca yüklemene gerek yok; yüklersen iki kez sayılır.")
            }
        }
    }

    private func row(_ item: DetectedSubscription) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name).fFont(13.5, .bold).lineLimit(1)
                        if item.priceIncreased, let change = item.priceChangePercent {
                            Text("↑ %\(change)")
                                .fFont(10, .heavy)
                                .foregroundStyle(FColor.warning)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(FColor.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                    Text("\(CategoryLabels.label(item.category)) · \(item.line)")
                        .fFont(11.5, .semibold).foregroundStyle(FColor.muted).lineLimit(2)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(TR.money(item.yearlyEstimate)).fFont(13.5, .heavy).monospacedDigit()
                    Text("yıllık").fFont(10.5, .semibold).foregroundStyle(FColor.muted)
                }
            }
            HStack(spacing: 8) {
                Button("Tekrarlayana çevir") { tracking = item }
                    .buttonStyle(.f(.secondary, height: 34, fontSize: 12.5))
                    .accessibilityIdentifier("track-\(item.id)")
                Button("Abonelik değil") { act { try await API.dismissSubscription(item.id) } }
                    .buttonStyle(.f(.secondary, height: 34, fontSize: 12.5))
                    .accessibilityIdentifier("dismiss-\(item.id)")
            }
            .disabled(busy)
        }
        .foregroundStyle(FColor.ink)
    }

    private func load() async {
        do {
            data = try await API.subscriptions()
            error = nil
        } catch let failure as APIError {
            if !failure.isCancellation { error = failure.message }
        } catch {}
    }

    private func act(_ work: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await work()
                tracking = nil
                await load()
                await changed()
            } catch let failure as APIError {
                error = failure.message
            } catch {}
        }
    }
}
