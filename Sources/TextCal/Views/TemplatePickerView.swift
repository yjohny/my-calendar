import SwiftUI

/// Shows saved templates for quick insertion, with options to add/edit/delete.
struct TemplatePickerView: View {
    @State private var templates: [EventTemplate] = []
    @State private var showingEditor = false
    @State private var editingTemplate: EventTemplate?
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    let templateStore: TemplateStore
    let onInsert: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView(
                        Strings.noTemplates,
                        systemImage: "doc.on.clipboard",
                        description: Text(Strings.noTemplatesDescription)
                    )
                } else {
                    List {
                        ForEach(templates) { template in
                            Button {
                                onInsert(template.text)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.name)
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    Text(template.text)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .accessibilityLabel("Insert \(template.name)")
                            .accessibilityHint(template.text)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteTemplate(template)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingTemplate = template
                                    showingEditor = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(Strings.templates)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(Strings.done) }
                        .font(.system(.body, design: .rounded))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingTemplate = nil
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add template")
                }
            }
            .overlay(alignment: .bottom) {
                if let error = saveError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.system(.caption, design: .rounded))
                        Spacer()
                        Button {
                            saveError = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                }
            }
            .sheet(isPresented: $showingEditor) {
                TemplateEditorView(
                    template: editingTemplate,
                    onSave: { template in
                        saveTemplate(template)
                    }
                )
            }
            .task {
                templates = await templateStore.load()
            }
        }
    }

    private func deleteTemplate(_ template: EventTemplate) {
        templates.removeAll { $0.id == template.id }
        persistTemplates()
    }

    private func saveTemplate(_ template: EventTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        persistTemplates()
    }

    private func persistTemplates() {
        Task {
            do {
                try await templateStore.save(templates)
                saveError = nil
            } catch {
                saveError = "Failed to save templates"
            }
        }
    }
}

/// Editor for creating or editing a single template.
struct TemplateEditorView: View {
    let template: EventTemplate?
    let onSave: (EventTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Strings.templateName, text: $name)
                        .font(.system(.body, design: .rounded))
                } header: {
                    Text(Strings.templateName)
                }

                Section {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .rounded))
                        .frame(minHeight: 100)
                } header: {
                    Text(Strings.templateContent)
                } footer: {
                    Text(Strings.templateContentFooter)
                }
            }
            .navigationTitle(template == nil ? Strings.newTemplate : Strings.editTemplate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) {
                        let saved = EventTemplate(
                            id: template?.id ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            text: text.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let template {
                    name = template.name
                    text = template.text
                }
            }
        }
    }
}
