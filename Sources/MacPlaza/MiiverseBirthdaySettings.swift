import SwiftUI
import PlazaCore

struct MiiverseBirthdaySettings: View {
    @ObservedObject var model: PlazaModel
    @State private var month = 0
    @State private var day = 0
    @State private var message: String?
    private var valid: Bool { PrimaryMiiBirthday.isValid(month: month, day: day) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Mii’s birthday").font(.headline)
            HStack {
                Picker("Birth month", selection: $month) {
                    Text("Unset").tag(0)
                    ForEach(1...12, id: \.self) { Text(DateFormatter().monthSymbols[$0 - 1]).tag($0) }
                }.frame(maxWidth: 240)
                Picker("Birth day", selection: $day) {
                    Text("Unset").tag(0)
                    ForEach(1...max(1, PrimaryMiiBirthday.days(in: month)), id: \.self) { Text(String($0)).tag($0) }
                }.frame(maxWidth: 170).disabled(month == 0)
            }
            HStack {
                PlazaButton("Save Birthday") {
                    if model.setPrimaryBirthday(month: month, day: day) { message = "Birthday saved on this Mac." }
                }.disabled(!valid || model.recoveryRequired)
                PlazaButton("Clear Birthday") {
                    if model.setPrimaryBirthday(month: 0, day: 0) { month = 0; day = 0; message = "Birthday cleared." }
                }.disabled(model.recoveryRequired)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            Text("Your primary Mii’s birthday stays on this Mac. On the day, a short celebration appears once while Plaza is available. Reduced Motion shows a still greeting.")
                .font(.callout).foregroundStyle(.secondary)
        }.onAppear(perform: restore)
            .onChange(of: model.document.primaryAvatar.id) { _, _ in restore() }
            .onChange(of: month) { _, value in
                if value == 0 { day = 0 }
                else { day = min(day, PrimaryMiiBirthday.days(in: value)) }
                message = nil
            }.onChange(of: day) { _, _ in message = nil }
    }
    private func restore() {
        month = model.document.primaryAvatar.features.birthMonth
        day = model.document.primaryAvatar.features.birthDay
        message = nil
    }
}

enum PrimaryMiiBirthday {
    static func days(in month: Int) -> Int {
        switch month { case 2: return 29; case 4, 6, 9, 11: return 30; case 1, 3, 5, 7, 8, 10, 12: return 31; default: return 0 }
    }
    static func isValid(month: Int, day: Int) -> Bool {
        (month == 0 && day == 0) || ((1...12).contains(month) && (1...days(in: month)).contains(day))
    }
}

extension PlazaModel {
    @discardableResult func setPrimaryBirthday(month: Int, day: Int) -> Bool {
        guard PrimaryMiiBirthday.isValid(month: month, day: day) else { return false }
        let primary = document.primaryAvatar.id
        return mutate { document in
            if let index = document.avatars.firstIndex(where: { $0.id == primary }) {
                document.avatars[index].features.birthMonth = month
                document.avatars[index].features.birthDay = day
            }
        }
    }
}
