import SwiftUI

/// Temporary placeholder until Task 6 builds the full detail page.
struct TitleDetailView: View {
    let tmdbID: Int
    let mediaType: MediaType
    let name: String

    var body: some View {
        Text(name)
            .navigationTitle(name)
    }
}
