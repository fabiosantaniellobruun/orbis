import ServiceManagement
import SwiftUI

/// "Apri <app> all'avvio del Mac", con l'avviso quando macOS chiede una conferma.
struct LoginItemSection: View {
  let appName: String

  @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
  @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval

  var body: some View {
    Section {
      Toggle("Apri \(appName) all'avvio del Mac", isOn: Binding(get: { opensAtLogin }, set: setLoginItem))
    } header: {
      Text("Avvio")
    } footer: {
      if needsApproval {
        Text("macOS chiede una conferma: Impostazioni di Sistema → Generali → Elementi login.")
          .foregroundStyle(.orange)
      }
    }
  }

  private func setLoginItem(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      log.error("Elemento login: \(error.localizedDescription, privacy: .private)")
    }
    let status = SMAppService.mainApp.status
    opensAtLogin = status == .enabled || status == .requiresApproval
    needsApproval = status == .requiresApproval
  }
}
