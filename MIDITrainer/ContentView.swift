//
//  ContentView.swift
//  MIDITrainer
//
//  Created by Sam Bender on 12/12/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var midiService: CoreMIDIAdapter

    var body: some View {
        TabView {
            PracticeView(midiService: midiService)
                .tabItem {
                    Label("Practice", systemImage: "pianokeys")
                }

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}
