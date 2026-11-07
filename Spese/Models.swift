import SwiftUI
import UniformTypeIdentifiers

struct Cat: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let color: Color
}

let expenseCats: [Cat] = [
    Cat(id: "cibo", name: "Cibo", symbol: "fork.knife", color: .orange),
    Cat(id: "svago", name: "Svago", symbol: "sparkles", color: .purple),
    Cat(id: "abb", name: "Abbonamenti", symbol: "arrow.triangle.2.circlepath", color: .indigo),
    Cat(id: "trasp", name: "Trasporti", symbol: "car", color: .blue),
    Cat(id: "casa", name: "Casa", symbol: "house", color: .green),
    Cat(id: "salute", name: "Salute", symbol: "heart", color: .pink),
    Cat(id: "shop", name: "Shopping", symbol: "bag", color: .red),
    Cat(id: "altro", name: "Altro", symbol: "ellipsis", color: .gray)
]

let incomeCats: [Cat] = [
    Cat(id: "stip", name: "Stipendio", symbol: "banknote", color: .green),
    Cat(id: "risp", name: "Risparmi", symbol: "tray.and.arrow.down", color: .teal),
    Cat(id: "altroin", name: "Altro", symbol: "plus", color: .gray)
]

func catFor(_ id: String) -> Cat {
    (expenseCats + incomeCats).first { $0.id == id } ?? expenseCats[7]
}

let dayFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

// Stesso formato della versione web: t = "in" | "out", d = "yyyy-MM-dd"
struct Transaction: Identifiable, Codable {
    var id: Int
    var t: String
    var k: String
    var a: Double
    var n: String
    var d: String
    var isIncome: Bool { t == "in" }
    var date: Date { dayFmt.date(from: d) ?? Date() }
}

struct Backup: Codable {
    var version: Int
    var tx: [Transaction]
}

struct BackupDoc: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

final class Store: ObservableObject {
    @Published var tx: [Transaction] = [] {
        didSet { save() }
    }
    private let url = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("spese.json")

    init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Transaction].self, from: data) else { return }
        tx = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tx) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func add(kind: String, cat: String, amount: Double, note: String, date: Date) {
        let t = Transaction(id: Int(Date().timeIntervalSince1970 * 1000), t: kind, k: cat,
                            a: (amount * 100).rounded() / 100, n: note, d: dayFmt.string(from: date))
        tx.append(t)
    }

    func remove(_ id: Int) { tx.removeAll { $0.id == id } }

    func backupData() -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? e.encode(Backup(version: 1, tx: tx))) ?? Data()
    }

    // Unisce i movimenti del backup a quelli presenti (nessun duplicato). Restituisce quanti ne ha aggiunti.
    func restore(_ data: Data) -> Int? {
        let dec = JSONDecoder()
        let list: [Transaction]
        if let b = try? dec.decode(Backup.self, from: data) { list = b.tx }
        else if let a = try? dec.decode([Transaction].self, from: data) { list = a }
        else { return nil }
        let have = Set(tx.map { $0.id })
        let new = list.filter { !have.contains($0.id) }
        tx.append(contentsOf: new)
        return new.count
    }
}
