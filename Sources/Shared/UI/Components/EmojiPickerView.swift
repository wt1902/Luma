import SwiftUI

/// A reusable emoji picker: category tabs on the bottom and a grid of emojis
/// for the selected category. Used both for reactions and for inserting an
/// emoji into the composer.
struct EmojiPickerView: View {
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategoryID = EmojiCatalog.categories.first?.id ?? ""

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 4)]

    private var selectedCategory: EmojiCategory {
        EmojiCatalog.categories.first { $0.id == selectedCategoryID }
            ?? EmojiCatalog.categories[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(selectedCategory.emojis, id: \.self) { emoji in
                        Button {
                            onSelect(emoji)
                            dismiss()
                        } label: {
                            Text(emoji)
                                .font(.system(size: 28))
                                .frame(width: 46, height: 46)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(emoji)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }

            Divider()

            categorySelector
                .padding(.vertical, 8)
        }
        .frame(minHeight: 360)
#if os(macOS)
        .frame(minWidth: 380)
#endif
    }

    private var header: some View {
        HStack {
            Text("Выберите эмодзи")
                .font(.headline)
            Spacer()
            Button("Готово") { dismiss() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(EmojiCatalog.categories) { category in
                    let isSelected = category.id == selectedCategoryID
                    Button {
                        selectedCategoryID = category.id
                    } label: {
                        Image(systemName: category.symbol)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .frame(width: 44, height: 44)
                            .background(
                                isSelected
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(category.title)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

#Preview {
    EmojiPickerView { _ in }
}
