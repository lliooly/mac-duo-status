//
//  StatusSectionView.swift
//  mac-duo-status
//

import SwiftUI

struct DuoStatusCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DuoStatusStyle.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                DuoStatusStyle.cardFill,
                in: RoundedRectangle(
                    cornerRadius: DuoStatusStyle.cardCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: DuoStatusStyle.cardCornerRadius,
                    style: .continuous
                )
                .strokeBorder(DuoStatusStyle.cardStroke, lineWidth: 0.75)
            }
    }
}

struct PopoverPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let onBack: (() -> Void)?
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(DuoStatusStyle.controlFill, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("common.back", comment: ""))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DuoStatusStyle.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
            trailing()
        }
        .frame(minHeight: 38)
    }
}

extension PopoverPageHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.init(title: title, subtitle: subtitle, onBack: onBack) {
            EmptyView()
        }
    }
}

struct DuoStatusIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? .primary : DuoStatusStyle.muted)
            .frame(width: 30, height: 30)
            .background(
                configuration.isPressed
                    ? DuoStatusStyle.controlFill
                    : Color.clear,
                in: Circle()
            )
            .contentShape(Circle())
    }
}

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
