import SwiftUI

struct NotificationPermissionView: View {
    @EnvironmentObject var notificationService: NotificationService
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("Stay in the loop")
                .font(.title)
                .fontWeight(.bold)

            Text("Get notified when you receive money, your card is used, or deposits confirm.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        _ = await notificationService.requestPermission()
                        onComplete()
                    }
                } label: {
                    Text("Enable Notifications")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .controlSize(.large)

                Button {
                    onComplete()
                } label: {
                    Text("Skip")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }
}
