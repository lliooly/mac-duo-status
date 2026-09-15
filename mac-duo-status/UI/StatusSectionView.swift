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
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: section.systemImageName)
                    .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 22)

                    Text(section.localizedTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DuoStatusStyle.muted)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(DuoStatusStyle.divider)
                    .padding(.horizontal, 12)

                content()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                    .transition(.opacity)
            }
        }
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("status-section-\(section.id)")
    }
}

struct StatusValueRow: View {
    let title: String
    let value: String
    var showsDivider: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .foregroundStyle(DuoStatusStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(value)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .regular))
            .frame(minHeight: 22)

            if showsDivider {
                Divider()
                    .overlay(DuoStatusStyle.divider)
            }
        }
    }
}

struct UnavailableStatusView: View {
    let reason: String?

    @ViewBuilder
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let reason, !reason.isEmpty {
                Text(reason)
                    .foregroundStyle(DuoStatusStyle.muted)
            } else {
                Text(NSLocalizedString("status.unavailable", comment: ""))
                    .foregroundStyle(DuoStatusStyle.muted)
            }
        }
        .font(.system(size: 11))
        .padding(.vertical, 4)
    }
}
