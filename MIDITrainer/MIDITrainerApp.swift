//
//  MIDITrainerApp.swift
//  MIDITrainer
//
//  Created by Sam Bender on 12/12/25.
//

import SwiftUI

@main
struct MIDITrainerApp: App {
    @StateObject private var midiService = CoreMIDIAdapter()
    @StateObject private var settingsStore = SettingsStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(midiService)
                .environmentObject(settingsStore)
                .onAppear {
                    midiService.start()
                }
                .onDisappear {
                    midiService.stop()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                print("[MIDI] App became active - refreshing endpoints")
                midiService.refreshEndpoints()
            }
        }
    }
}
