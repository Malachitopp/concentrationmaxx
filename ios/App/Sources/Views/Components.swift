import FamilyControls
import SwiftUI

/// A dismissible message at the top of the main screen.
struct BannerView: View {
    let banner: Banner
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(banner.message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var icon: String {
        switch banner.kind {
        case .error: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch banner.kind {
        case .error: return .red
        case .warning: return .orange
        case .info: return .green
        }
    }
}

/// Shows a saved list and lets the person change it in Apple's picker. iOS never tells
/// the app which apps were picked; it only hands back tokens that Label can draw.
struct SelectionEditor: View {
    @EnvironmentObject private var model: AppModel
    let kind: SelectionKind
    var buttonTitle = "Choose"
    var showsItems = true

    @State private var draft = FamilyActivitySelection()
    @State private var isPickerPresented = false

    var body: some View {
        let selection = model.selection(kind)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selection.summary)
                    .foregroundStyle(selection.isEmptySelection ? .secondary : .primary)
                Spacer()
                Button(model.isBlockRunning ? "Locked" : buttonTitle) {
                    draft = selection
                    isPickerPresented = true
                }
                .buttonStyle(.borderless)
                .disabled(model.isBlockRunning)
            }
            if showsItems, !selection.isEmptySelection {
                SelectionItemsView(selection: selection)
            }
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $draft)
        .onAppear {
            draft = model.selection(kind)
        }
        .onChange(of: draft) { _, newValue in
            guard newValue != model.selection(kind) else { return }
            if !model.save(newValue, as: kind) {
                draft = model.selection(kind)
            }
        }
    }
}

/// The picked apps, categories and websites, drawn by iOS from their tokens.
struct SelectionItemsView: View {
    let selection: FamilyActivitySelection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(selection.applicationTokens), id: \.self) { token in
                Label(token)
            }
            ForEach(Array(selection.categoryTokens), id: \.self) { token in
                Label(token)
            }
            ForEach(Array(selection.webDomainTokens), id: \.self) { token in
                Label(token)
            }
        }
        .font(.callout)
    }
}

/// A bullet list of plain text, used for "what to tick" instructions.
struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                    Text(item)
                }
            }
        }
    }
}
