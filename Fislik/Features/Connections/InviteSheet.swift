import SwiftUI

/// 2W — invite by e-mail. Clients invite accountants; accountants invite clients.
struct InviteSheet: View {
    var invitingAccountant = true
    var onSent: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(invitingAccountant ? "Muhasebecini davet et" : "Mükellef davet et").fFont(22, .heavy, tracking: -0.4)
                Text(invitingAccountant
                     ? "E-posta adresini gir; davet bağlantısıyla hesabına bağlansın ve fişlerini görsün. Zaten Fişlik'teyse bildirim alır."
                     : "Mükellefinin e-postasını gir; kabul ettiğinde fişlerini görmeye başlarsın. Zaten Fişlik'teyse bildirim alır.")
                    .fFont(12.5, .medium).foregroundStyle(FColor.muted).lineSpacing(3)
            }
            VStack(alignment: .leading, spacing: 6) {
                FFieldLabel(text: invitingAccountant ? "Muhasebeci e-postası" : "Mükellef e-postası")
                TextField("ornek@firma.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(send)
                    .focused($focused)
                    .fFont(15, .medium)
                    .padding(.horizontal, 13)
                    .frame(height: 48)
                    .background(FColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(error != nil ? FColor.danger.opacity(0.6) : focused ? FColor.brand : FColor.fieldBorder, lineWidth: 1.5))
            }
            if let error {
                HStack(spacing: 8) {
                    Icon(.circleAlert, size: 15)
                    Text(error)
                }
                .fFont(12, .semibold)
                .foregroundStyle(FColor.danger)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(light: 0xFEF2F2, dark: 0x2A1513), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(light: 0xFECACA, dark: 0x5A2520)))
            }
            let recents = GrantDates.recentEmails.filter { $0 != email }
            if !recents.isEmpty {
                HStack(spacing: 10) {
                    Text("Son kullanılan:").fFont(11.5, .bold).foregroundStyle(FColor.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(recents, id: \.self) { r in
                                Button(r) { email = r; error = nil }
                                    .fFont(12, .bold)
                                    .foregroundStyle(FColor.ink)
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(FColor.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(FColor.lineStrong))
                            }
                        }
                    }
                }
            }
            Button(action: send) { FButtonLabel(title: "Davet Gönder", icon: .send, loading: sending) }
                .buttonStyle(.fPrimary)
                .disabled(!email.isValidEmail || sending)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .background(FColor.bg.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onAppear { focused = true }
        .onChange(of: email) { error = nil }
    }

    private func send() {
        guard email.isValidEmail else { return }
        sending = true
        Task {
            defer { sending = false }
            let address = email.trimmingCharacters(in: .whitespaces).lowercased()
            do {
                _ = try await API.invite(email: address)
                GrantDates.recentEmails = [address] + GrantDates.recentEmails.filter { $0 != address }
                await ReceiptStore.shared.refreshGrants()
                onSent()
                dismiss()
            } catch let e as APIError {
                switch e.status {
                case 409: error = "Bu e-postaya zaten davet gönderilmiş"
                case 422:
                    if e.detail?.contains("yourself") == true { error = "Kendini davet edemezsin" }
                    else { error = invitingAccountant ? "Bu e-posta bir muhasebeci hesabına ait değil" : "Bu e-posta bir mükellef hesabına ait değil" }
                default: error = e.message
                }
            } catch {}
        }
    }
}

struct InviteAccountantSheet: View {
    var body: some View { InviteSheet(invitingAccountant: true) }
}
