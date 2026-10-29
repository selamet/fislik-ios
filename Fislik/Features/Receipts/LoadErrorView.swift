import SwiftUI

/// 2AC — "Fişler yüklenemedi".
struct LoadErrorView: View {
    let error: APIError
    let retry: () -> Void
    var onShowCache: (() -> Void)?
    @State private var retrying = false

    var body: some View {
        VStack(spacing: 16) {
            Icon(.circleAlert, size: 28)
                .foregroundStyle(FColor.danger)
                .frame(width: 72, height: 72)
                .background(FColor.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(spacing: 6) {
                Text("Fişler yüklenemedi").fFont(18, .heavy, tracking: -0.3)
                Text(error == .offline
                     ? "İnternet bağlantın yok. Bağlantını kontrol edip tekrar dene; son görülen fişler aşağıda saklı."
                     : "Sunucuya ulaşılamadı. Bağlantını kontrol edip tekrar dene; son görülen fişler aşağıda saklı.")
                    .fFont(13.5, .medium).foregroundStyle(FColor.muted).multilineTextAlignment(.center).lineSpacing(3)
            }
            HStack(spacing: 10) {
                Button {
                    retrying = true
                    retry()
                    Task { try? await Task.sleep(for: .seconds(1)); retrying = false }
                } label: { FButtonLabel(title: "Tekrar dene", icon: .rotateCw, loading: retrying) }
                    .buttonStyle(.f(.primary, height: 46, fontSize: 14, hPadding: 18))
                    .fixedSize()
                if let onShowCache {
                    Button("Önbellekten göster", action: onShowCache)
                        .buttonStyle(.f(.secondary, height: 46, fontSize: 14, hPadding: 16))
                        .fixedSize()
                }
            }
            Text("Hata kodu: \(error.code) · \(TR.time(Date()))").fFont(11.5, .semibold).foregroundStyle(FColor.faint)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}
