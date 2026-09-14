//
//  StatusSectionView.swift
//  mac-duo-status
//

import SwiftUI

struct StatusSectionView<Content: View>: View {
    let section: StatusSection
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
                .padding(.top, 6)
        } label: {
            Label(section.localizedTitle, systemImage: section.systemImageName)
                .font(.headline)
        }
    }
}

struct StatusValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

struct UnavailableStatusView: View {
    let reason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("status.unavailable", comment: ""))
                .foregroundStyle(.secondary)

            if let reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
