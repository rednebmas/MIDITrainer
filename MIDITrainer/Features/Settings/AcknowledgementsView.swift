import SwiftUI

struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                Text("This app uses melody data from the following sources. We are grateful to the researchers and institutions who made these datasets publicly available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Weimar Jazz Database") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Jazz solo transcriptions from the Jazzomat Research Project")
                        .font(.subheadline)

                    Text("Licensed under the Open Database License (ODbL)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Citation:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.top, 4)

                    Text("Pfleiderer, M., Frieler, K., Abeßer, J., Zaddach, W.-G., & Burkhart, B. (Eds.). (2017). Inside the Jazzomat: New Perspectives for Jazz Research. Schott Campus.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("jazzomat.hfm-weimar.de", destination: URL(string: "https://jazzomat.hfm-weimar.de")!)
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }

            Section("McGill Billboard Dataset") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chord annotations from Billboard Year-End charts")
                        .font(.subheadline)

                    Text("Released under CC0 (Public Domain)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Citation:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.top, 4)

                    Text("Burgoyne, J. A., Wild, J., & Fujinaga, I. (2011). An Expert Ground Truth Set for Audio Chord Recognition and Music Analysis. Proceedings of the 12th International Society for Music Information Retrieval Conference (ISMIR), 633-638.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("ddmal.ca", destination: URL(string: "https://ddmal.ca/research/The_McGill_Billboard_Project_(Chord_Analysis_Dataset)/")!)
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }

            Section("POP909 Dataset") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pop music melody transcriptions")
                        .font(.subheadline)

                    Text("Licensed under the MIT License")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("github.com/music-x-lab/POP909-Dataset", destination: URL(string: "https://github.com/music-x-lab/POP909-Dataset")!)
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }

            Section("App Information") {
                LabeledContent("Version", value: Bundle.main.appVersion)
                LabeledContent("Build", value: Bundle.main.buildNumber)
            }
        }
        .navigationTitle("Acknowledgements")
    }
}

private extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

#Preview {
    NavigationStack {
        AcknowledgementsView()
    }
}
