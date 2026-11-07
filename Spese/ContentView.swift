import SwiftUI

struct SheetMode: Identifiable {
    let id = UUID()
    var kind: String
    var cat: String
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @AppStorage("lastBackup") private var lastBackup: Double = 0
    @State private var month = Date()
    @State private var sheet: SheetMode?
    @State private var exporting = false
    @State private var importing = false
    @State private var doc = BackupDoc(data: Data())
    @State private var message: String?

    private var monthTx: [Transaction] {
        store.tx.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }
    private var balance: Double { store.tx.reduce(0) { $0 + ($1.isIncome ? $1.a : -$1.a) } }
    private var incomeM: Double { monthTx.filter { $0.isIncome }.reduce(0) { $0 + $1.a } }
    private var outM: Double { monthTx.filter { !$0.isIncome }.reduce(0) { $0 + $1.a } }
    private var isCurrentMonth: Bool { Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month) }
    private var needsBackup: Bool {
        !store.tx.isEmpty && Date().timeIntervalSince1970 - lastBackup > 4 * 86400
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthBar
                    if needsBackup { banner }
                    balanceCard
                    heading("Categorie")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(expenseCats) { c in tile(c) }
                    }
                    heading("Movimenti")
                    movements
                }
                .padding()
                .padding(.bottom, 70)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Spese")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { startBackup() } label: { Label("Crea backup", systemImage: "square.and.arrow.up") }
                        Button { importing = true } label: { Label("Ripristina da backup", systemImage: "square.and.arrow.down") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button { sheet = SheetMode(kind: "out", cat: "cibo") } label: {
                    Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white)
                        .frame(width: 58, height: 58).background(Color.accentColor, in: Circle())
                        .shadow(radius: 6, y: 3)
                }
                .padding(20)
            }
        }
        .sheet(item: $sheet) { m in
            AddSheet(mode: m) { d in month = d }.environmentObject(store)
        }
        .fileExporter(isPresented: $exporting, document: doc, contentType: .json,
                      defaultFilename: "Spese-backup-" + dayFmt.string(from: Date())) { result in
            if case .success = result {
                lastBackup = Date().timeIntervalSince1970
                message = "Backup salvato. Conserva il file in un posto sicuro."
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let n = store.restore(data) {
                message = n == 0 ? "Nessun movimento nuovo: era già tutto presente." : "Ripristinati \(n) movimenti."
            } else {
                message = "Il file non è un backup valido."
            }
        }
        .alert("Spese", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func startBackup() {
        doc = BackupDoc(data: store.backupData())
        exporting = true
    }

    private func heading(_ s: String) -> some View {
        Text(s).font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
    }

    private var monthBar: some View {
        HStack {
            Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()).capitalized).font(.headline)
            Spacer()
            Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal, 4)
    }

    private var banner: some View {
        HStack {
            Text("Fai un backup: l’app scade ogni 7 giorni.").font(.footnote)
            Spacer()
            Button("Crea backup") { startBackup() }.font(.footnote.bold())
        }
        .padding(12)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saldo").font(.subheadline).foregroundStyle(.secondary)
            Text(balance, format: .currency(code: "EUR"))
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(balance < 0 ? Color.red : Color.primary)
            HStack(spacing: 28) {
                stat("Entrate", incomeM)
                stat("Spese", outM)
            }
            HStack(spacing: 10) {
                Button { sheet = SheetMode(kind: "in", cat: "stip") } label: {
                    Text("Entrata").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Button { sheet = SheetMode(kind: "out", cat: "cibo") } label: {
                    Text("Spesa").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func stat(_ title: String, _ v: Double) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(v, format: .currency(code: "EUR")).font(.headline)
        }
    }

    private func tile(_ c: Cat) -> some View {
        let v = monthTx.filter { !$0.isIncome && $0.k == c.id }.reduce(0) { $0 + $1.a }
        return Button { sheet = SheetMode(kind: "out", cat: c.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: c.symbol).foregroundStyle(c.color)
                    .frame(width: 36, height: 36)
                    .background(c.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                Text(c.name).font(.footnote).foregroundStyle(.secondary)
                Text(v, format: .currency(code: "EUR")).font(.headline).foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var movements: some View {
        let rows = monthTx.sorted { $0.d == $1.d ? $0.id > $1.id : $0.d > $1.d }
        return VStack(spacing: 0) {
            if rows.isEmpty {
                Text("Nessun movimento in questo mese.\nTocca + per aggiungerne uno.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.vertical, 22)
            } else {
                ForEach(rows) { t in row(t) }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func row(_ t: Transaction) -> some View {
        let c = catFor(t.k)
        let tint = t.isIncome ? Color.green : c.color
        return HStack(spacing: 12) {
            Image(systemName: t.isIncome ? "arrow.up" : c.symbol).foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(t.n.isEmpty ? c.name : t.n)
                Text(t.date.formatted(.dateTime.day().month(.abbreviated))).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text((t.isIncome ? "+" : "−") + t.a.formatted(.currency(code: "EUR")))
                .fontWeight(.semibold)
                .foregroundStyle(t.isIncome ? Color.green : Color.primary)
        }
        .padding(.vertical, 10)
        .contextMenu {
            Button(role: .destructive) { store.remove(t.id) } label: { Label("Elimina", systemImage: "trash") }
        }
    }
}

struct AddSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: String
    @State private var cat: String
    @State private var amount = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var bad = false
    var onSave: (Date) -> Void

    init(mode: SheetMode, onSave: @escaping (Date) -> Void) {
        _kind = State(initialValue: mode.kind)
        _cat = State(initialValue: mode.cat)
        self.onSave = onSave
    }

    private var cats: [Cat] { kind == "out" ? expenseCats : incomeCats }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $kind) {
                        Text("Spesa").tag("out")
                        Text("Entrata").tag("in")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _ in cat = kind == "out" ? "cibo" : "stip" }
                }
                Section {
                    TextField("0,00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 34, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(bad ? Color.red : Color.primary)
                }
                Section("Categoria") {
                    ForEach(cats) { c in
                        Button { cat = c.id } label: {
                            HStack {
                                Image(systemName: c.symbol).foregroundStyle(c.color).frame(width: 28)
                                Text(c.name).foregroundStyle(Color.primary)
                                Spacer()
                                if cat == c.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                        }
                    }
                }
                Section {
                    TextField("Nota (facoltativa)", text: $note)
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle(kind == "out" ? "Nuova spesa" : "Nuova entrata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() } }
            }
        }
    }

    private func save() {
        guard let a = Double(amount.replacingOccurrences(of: ",", with: ".")), a > 0 else {
            bad = true
            return
        }
        store.add(kind: kind, cat: cat, amount: a, note: note.trimmingCharacters(in: .whitespaces), date: date)
        onSave(date)
        dismiss()
    }
}
