import SwiftUI

struct GroupListView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var symbol = "folder"
    private let symbols = ["folder", "briefcase", "sun.max", "moon.stars", "figure.run", "book", "heart", "alarm"]

    var body: some View {
        List {
            Section("groups.add") {
                TextField("groups.name", text: $name)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(symbols, id: \.self) { item in
                            Button {
                                symbol = item
                            } label: {
                                Image(systemName: item)
                                    .frame(width: 40, height: 40)
                                    .background(symbol == item ? Color.orange.opacity(0.25) : Color.clear, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item)
                        }
                    }
                }
                Button("groups.create") {
                    model.createGroup(name: name, symbol: symbol)
                    name = ""
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.library.groups.isEmpty {
                ContentUnavailableView("groups.empty", systemImage: "folder", description: Text("groups.add"))
            } else {
                ForEach(model.library.groups) { group in
                    HStack {
                        Label(group.name, systemImage: group.symbol)
                        Spacer()
                        Toggle(isOn: Binding(
                            get: { group.isEnabled },
                            set: { _ in model.toggle(groupID: group.id) }
                        )) {
                            Text(group.name)
                        }
                        .labelsHidden()
                        .tint(.orange)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        model.deleteGroup(id: model.library.groups[index].id)
                    }
                }
            }
        }
        .navigationTitle("groups.title")
        .accessibilityIdentifier("group-list")
    }
}
