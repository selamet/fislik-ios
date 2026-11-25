import SwiftUI

/// Shown once after an invite put the user in a company or grant: where they
/// landed and what to do first (instead of the new-user company setup).
struct WelcomeView: View {
    let joined: JoinedViaInvite
    /// Called with true when the user picked "take the first photo".
    let onDone: (_ openCamera: Bool) -> Void

    var body: some View {
        let copy = InviteCopy.welcome(joined)
        VStack(spacing: 22) {
            Spacer()
            Icon(.circleCheck, size: 40)
                .foregroundStyle(FColor.brand)
                .frame(width: 88, height: 88)
                .background(FColor.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 28))
            VStack(spacing: 8) {
                Text("HOŞ GELDİN").fFont(11, .heavy, tracking: 0.6).foregroundStyle(FColor.brand)
                Text(copy.title)
                    .fFont(24, .heavy, tracking: -0.5)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(InviteCopy.benefits(kind: joined.kind, role: joined.role), id: \.self) { text in
                    HStack(spacing: 10) {
                        Icon(.check, size: 16).foregroundStyle(FColor.brand)
                        Text(text).fFont(14, .semibold).foregroundStyle(FColor.muted)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
            .background(FColor.card, in: RoundedRectangle(cornerRadius: 18))
            Spacer()
            Button { onDone(copy.opensCamera) } label: {
                FButtonLabel(title: copy.action, icon: copy.opensCamera ? .camera : nil)
            }
            .buttonStyle(.f(.primary, height: 52, fontSize: 16, radius: 16))
            if copy.opensCamera {
                Button("Sonra") { onDone(false) }
                    .fFont(14, .bold)
                    .foregroundStyle(FColor.muted)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(FColor.bg.ignoresSafeArea())
    }
}
