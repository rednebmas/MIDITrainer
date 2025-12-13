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
    }
}
