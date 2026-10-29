import SwiftUI

/// 2AI — accountant asks the client about a receipt.
struct ReportIssueSheet: View {
    let receipt: Receipt
    let store: ReceiptStore
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var template: String?
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool

    static let templates: [(String, String)] = [
        ("Şirket adına değil", "Bu fatura şirket adına mı kesilmiş? VKN görünmüyor."),
        ("VKN yok", "Fişte satıcının VKN'si görünmüyor, kontrol eder misin?"),
        ("Okunmuyor", "Fiş okunmuyor, daha net bir fotoğraf yükleyebilir misin?"),
        ("Yanlış ay", "Bu fiş başka bir aya ait görünüyor, doğru aya taşır mısın?"),
        ("Mükerrer", "Bu fiş daha önce de yüklenmiş olabilir, kontrol eder misin?"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ReceiptThumb(receipt: receipt, showPaper: false)
                    .frame(width: 48, height: 60)
                    .background(Color(hex: 0x2A3937))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sorun bildir").fFont(20, .heavy, tracking: -0.4)
                    Text([receipt.merchant, TR.shortDay(receipt.displayDate), TR.money(receipt.total), receipt.extraction?.docType?.label].compactMap { $0 }.joined(separator: " · "))
                        .fFont(12, .semibold).foregroundStyle(FColor.muted)
                }
                Spacer()
                Button { dismiss() } label: {
                    Icon(.x, size: 16).foregroundStyle(FColor.muted)
                        .frame(width: 32, height: 32)
                        .background(FColor.ink.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
            FlowLayout(spacing: 6) {
                ForEach(Self.templates, id: \.0) { title, text in
                    FChip(title: title, selected: template == title) {
                        template = title
                        message = text
                    }
                }
            }
            TextField("Mükellefe sorunu yaz…", text: $message, axis: .vertical)
                .lineLimit(3...8)
                .focused($focused)
                .fFont(14, .semibold)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .frame(minHeight: 88, alignment: .topLeading)
                .background(FColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? FColor.brand : FColor.fieldBorder))
                .onChange(of: message) { _, v in if v.count > 1000 { message = String(v.prefix(1000)) } }
            HStack {
                Text("Mükellef bildirim alır ve fişin üstünde görür.")
                Spacer()
                Text("\(message.count) / 1000").monospacedDigit()
            }
            .fFont(11.5, .semibold)
            .foregroundStyle(FColor.muted)
            if let error { Text(error).fFont(12, .semibold).foregroundStyle(FColor.danger) }
            Button(action: send) { FButtonLabel(title: "Gönder", icon: .send, loading: sending) }
                .buttonStyle(.fPrimary)
                .disabled(message.nilIfBlank == nil || sending)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .background(FColor.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onAppear { focused = true }
    }

    private func send() {
        sending = true
        Task {
            defer { sending = false }
            do {
                try await store.reportIssue(receipt, message: message.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            } catch let e as APIError {
                error = e.status == 409 ? "Bu fişte zaten açık bir soru var." : e.message
            } catch {}
        }
    }
}
