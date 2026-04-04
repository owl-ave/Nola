import SwiftUI

struct LanguageOption: Identifiable {
    let id: String // BCP 47 code
    let nativeName: String
}

private let languages: [LanguageOption] = [
    LanguageOption(id: "en", nativeName: "English"),
    LanguageOption(id: "ja", nativeName: "日本語"),
    LanguageOption(id: "ar", nativeName: "العربية"),
    LanguageOption(id: "de", nativeName: "Deutsch"),
]

struct LanguageGateView: View {
    @AppStorage("preferredLanguage") private var preferredLanguage = ""
    @State private var selectedLanguage: String = ""
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "globe")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Choose your language")
                .font(.title2.weight(.bold))
                .environment(\.locale, Locale(identifier: selectedLanguage.isEmpty ? "en" : selectedLanguage))

            VStack(spacing: 12) {
                ForEach(languages) { lang in
                    Button {
                        selectedLanguage = lang.id
                    } label: {
                        HStack(spacing: 14) {
                            Text(lang.nativeName)
                                .font(.body.weight(.medium))
                            Spacer()
                            if selectedLanguage == lang.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                    .font(.title3)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedLanguage == lang.id
                                      ? Color.accentColor.opacity(0.1)
                                      : Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedLanguage == lang.id
                                        ? Color.accentColor
                                        : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                preferredLanguage = selectedLanguage
                onContinue()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .environment(\.locale, Locale(identifier: selectedLanguage.isEmpty ? "en" : selectedLanguage))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .disabled(selectedLanguage.isEmpty)
        }
        .padding(.bottom, 32)
        .onAppear {
            let deviceLang = Locale.current.language.languageCode?.identifier ?? "en"
            let supported = languages.map(\.id)
            selectedLanguage = supported.contains(deviceLang) ? deviceLang : "en"
        }
    }
}
